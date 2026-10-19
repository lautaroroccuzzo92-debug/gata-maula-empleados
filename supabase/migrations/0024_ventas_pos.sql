-- Gata Maula: ventas del sistema Postberry (se cargan subiendo los Excel exportados) y su analisis.
--   * pos_lineas: una fila por producto de cada venta (archivo "ventas_detalle")
--   * pos_pagos: cada cobro con su medio de pago, y las anulaciones (archivo "movcaja")
--   * pos_cargar_*: cargan los archivos; pos_borrar_rango borra el periodo antes de volver a cargarlo (asi no se duplica)
--   * pos_analisis: productos, familias, dias, horas. pos_control_caja: compara Postberry contra la caja que cargan los chicos.
-- "Dia de negocio": lo vendido de madrugada (hasta las 6) cuenta para el dia anterior.
-- Correr UNA vez en el SQL Editor.

create table if not exists public.pos_lineas (
  id bigserial primary key,
  venta_id text not null,
  tipo text,
  pv int,
  numero bigint,
  fecha timestamp not null,
  total_venta numeric(14,2),
  anulado boolean not null default false,
  producto text not null,
  familia text,
  proveedor text,
  costo numeric(14,2),
  precio_unit numeric(14,2),
  cantidad numeric(14,3),
  neto numeric(14,2),
  descuentos numeric(14,2),
  impuestos numeric(14,2)
);
create index if not exists pos_lineas_fecha_idx on public.pos_lineas (fecha);
create index if not exists pos_lineas_venta_idx on public.pos_lineas (venta_id);

create table if not exists public.pos_pagos (
  id bigserial primary key,
  fecha timestamp not null,
  cond_pago text not null,
  documento text,
  pv int,
  numero bigint,
  importe numeric(14,2) not null,
  tipo text,
  observacion text
);
create index if not exists pos_pagos_fecha_idx on public.pos_pagos (fecha);

alter table public.pos_lineas enable row level security;
alter table public.pos_pagos enable row level security;
drop policy if exists pos_lineas_select on public.pos_lineas;
create policy pos_lineas_select on public.pos_lineas for select using (public.rol_actual() in ('admin', 'encargado'));
drop policy if exists pos_pagos_select on public.pos_pagos;
create policy pos_pagos_select on public.pos_pagos for select using (public.rol_actual() in ('admin', 'encargado'));

-- ---------------------------------------------------------------- carga (solo admin)
create or replace function public.pos_borrar_rango(p_desde timestamp, p_hasta timestamp, p_lineas boolean default true, p_pagos boolean default true)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare a int := 0; b int := 0;
begin
  if public.rol_actual() <> 'admin' then raise exception 'Sin permiso'; end if;
  if p_lineas then
    delete from public.pos_lineas where fecha between p_desde and p_hasta;
    get diagnostics a = row_count;
  end if;
  if p_pagos then
    delete from public.pos_pagos where fecha between p_desde and p_hasta;
    get diagnostics b = row_count;
  end if;
  return jsonb_build_object('lineas_borradas', a, 'pagos_borrados', b);
end;
$$;
grant execute on function public.pos_borrar_rango(timestamp, timestamp, boolean, boolean) to authenticated;

create or replace function public.pos_cargar_lineas(p_filas jsonb)
returns integer
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if public.rol_actual() <> 'admin' then raise exception 'Sin permiso'; end if;
  insert into public.pos_lineas (venta_id, tipo, pv, numero, fecha, total_venta, anulado, producto, familia, proveedor, costo, precio_unit, cantidad, neto, descuentos, impuestos)
  select venta_id, tipo, pv, numero, fecha, total_venta, coalesce(anulado, false), producto, familia, proveedor, costo, precio_unit, cantidad, neto, descuentos, impuestos
    from jsonb_to_recordset(p_filas) as t(venta_id text, tipo text, pv int, numero bigint, fecha timestamp, total_venta numeric, anulado boolean,
      producto text, familia text, proveedor text, costo numeric, precio_unit numeric, cantidad numeric, neto numeric, descuentos numeric, impuestos numeric);
  get diagnostics n = row_count;
  return n;
end;
$$;
grant execute on function public.pos_cargar_lineas(jsonb) to authenticated;

create or replace function public.pos_cargar_pagos(p_filas jsonb)
returns integer
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if public.rol_actual() <> 'admin' then raise exception 'Sin permiso'; end if;
  insert into public.pos_pagos (fecha, cond_pago, documento, pv, numero, importe, tipo, observacion)
  select fecha, cond_pago, documento, pv, numero, importe, tipo, observacion
    from jsonb_to_recordset(p_filas) as t(fecha timestamp, cond_pago text, documento text, pv int, numero bigint, importe numeric, tipo text, observacion text);
  get diagnostics n = row_count;
  return n;
end;
$$;
grant execute on function public.pos_cargar_pagos(jsonb) to authenticated;

-- ---------------------------------------------------------------- consultas (admin y encargado)
create or replace function public.pos_estado()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v jsonb;
begin
  if public.rol_actual() not in ('admin', 'encargado') then raise exception 'Sin permiso'; end if;
  select jsonb_build_object(
    'desde', (select min(fecha) from public.pos_lineas), 'hasta', (select max(fecha) from public.pos_lineas),
    'dia_desde', (select min((fecha - interval '6 hours')::date) from public.pos_lineas),
    'dia_hasta', (select max((fecha - interval '6 hours')::date) from public.pos_lineas),
    'ventas', (select count(distinct venta_id) from public.pos_lineas),
    'pagos_desde', (select min(fecha) from public.pos_pagos), 'pagos_hasta', (select max(fecha) from public.pos_pagos),
    'pagos', (select count(*) from public.pos_pagos)
  ) into v;
  return v;
end;
$$;
grant execute on function public.pos_estado() to authenticated;

create or replace function public.pos_analisis(p_desde date, p_hasta date)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v jsonb;
begin
  if public.rol_actual() not in ('admin', 'encargado') then raise exception 'Sin permiso'; end if;
  with l as (
    select *, (fecha - interval '6 hours')::date as dia,
           coalesce(neto, 0) + coalesce(impuestos, 0) - coalesce(descuentos, 0) as importe
      from public.pos_lineas
     where not anulado and (fecha - interval '6 hours')::date between p_desde and p_hasta
  ), ventas as (
    select distinct on (venta_id) venta_id, fecha, dia, total_venta, tipo from l order by venta_id, fecha
  ), prod as (
    select producto, max(familia) as familia, sum(cantidad) as cant, sum(importe) as imp,
           sum(coalesce(neto, 0) - coalesce(costo, 0) * coalesce(cantidad, 0)) as margen_abs, sum(coalesce(neto, 0)) as neto
      from l where importe >= 1 group by producto
  ), dias_sem as (
    select extract(dow from dia)::int as dow, count(distinct dia) as dias, sum(total_venta) as total, count(*) as tickets
      from ventas group by 1
  ), horas as (
    select extract(hour from fecha)::int as hora, count(*) as tickets, sum(total_venta) as total from ventas group by 1
  ), por_dia as (
    select dia, count(*) as tickets, sum(total_venta) as total from ventas group by 1
  )
  select jsonb_build_object(
    'resumen', jsonb_build_object(
      'desde', (select min(dia) from ventas), 'hasta', (select max(dia) from ventas),
      'dias_con_venta', (select count(*) from por_dia),
      'ventas_total', coalesce((select sum(total_venta) from ventas), 0),
      'tickets', (select count(*) from ventas),
      'ticket_promedio', coalesce((select round(avg(total_venta)) from ventas), 0),
      'ventas_fiscales_FCB', coalesce((select sum(total_venta) from ventas where tipo = 'FCB'), 0),
      'ventas_no_fiscales_PSP', coalesce((select sum(total_venta) from ventas where tipo = 'PSP'), 0)
    ),
    'productos_mas_vendidos', coalesce((select jsonb_agg(jsonb_build_object('producto', producto, 'familia', familia, 'cantidad', cant, 'importe', round(imp),
        'margen_pct', case when neto > 0 then round(margen_abs / neto * 100, 1) end) order by imp desc)
        from (select * from prod order by imp desc limit 30) x), '[]'::jsonb),
    'productos_menos_vendidos', coalesce((select jsonb_agg(jsonb_build_object('producto', producto, 'familia', familia, 'cantidad', cant, 'importe', round(imp)) order by cant)
        from (select * from prod order by cant, imp limit 20) x), '[]'::jsonb),
    'familias', coalesce((select jsonb_agg(jsonb_build_object('familia', familia, 'cantidad', cant, 'importe', round(imp)) order by imp desc)
        from (select coalesce(familia, 'SIN FAMILIA') as familia, sum(cantidad) as cant, sum(importe) as imp from l where importe >= 1 group by 1) f), '[]'::jsonb),
    'por_dia_de_semana', coalesce((select jsonb_agg(jsonb_build_object(
        'dia', (array['domingo','lunes','martes','miercoles','jueves','viernes','sabado'])[dow + 1], 'dias', dias, 'total', round(total),
        'promedio_por_dia', round(total / dias), 'tickets', tickets) order by dow) from dias_sem), '[]'::jsonb),
    'por_hora', coalesce((select jsonb_agg(jsonb_build_object('hora', hora, 'tickets', tickets, 'total', round(total)) order by hora) from horas), '[]'::jsonb),
    'por_dia', coalesce((select jsonb_agg(jsonb_build_object('dia', dia, 'tickets', tickets, 'total', round(total)) order by dia) from por_dia), '[]'::jsonb)
  ) into v;
  return v;
end;
$$;
grant execute on function public.pos_analisis(date, date) to authenticated;

create or replace function public.pos_control_caja(p_desde date, p_hasta date)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v jsonb;
begin
  if public.rol_actual() not in ('admin', 'encargado') then raise exception 'Sin permiso'; end if;
  with p as (
    select (fecha - interval '6 hours')::date as dia,
           sum(importe) filter (where cond_pago = 'EFECTIVO') as efectivo,
           sum(importe) filter (where cond_pago = 'TRANSFERENCIA') as transferencia,
           sum(importe) filter (where cond_pago = 'TARJETA DE CREDITO') as credito,
           sum(importe) filter (where cond_pago = 'TARJETA DE DEBITO') as debito,
           sum(importe) filter (where cond_pago = 'QR') as qr,
           sum(importe) as total,
           count(*) filter (where importe < 0) as anulaciones,
           coalesce(sum(importe) filter (where importe < 0), 0) as monto_anulado
      from public.pos_pagos
     where (fecha - interval '6 hours')::date between p_desde and p_hasta
     group by 1
  ), c as (
    select fecha as dia, efectivo, transferencia, tarjeta_credito as credito, tarjeta_debito as debito,
           coalesce(qr_posnet, 0) + coalesce(qr_mercado_pago, 0) as qr, venta_total as total
      from public.caja_diaria where fecha between p_desde and p_hasta
  ), d as (
    select coalesce(p.dia, c.dia) as dia, p as pos, c as caja from p full join c on c.dia = p.dia
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'dia', dia,
    'postberry', jsonb_build_object('total', round(coalesce((pos).total, 0)), 'efectivo', round(coalesce((pos).efectivo, 0)), 'transferencia', round(coalesce((pos).transferencia, 0)),
        'credito', round(coalesce((pos).credito, 0)), 'debito', round(coalesce((pos).debito, 0)), 'qr', round(coalesce((pos).qr, 0))),
    'caja_cargada', case when (caja).dia is null then null else jsonb_build_object('total', round(coalesce((caja).total, 0)), 'efectivo', round(coalesce((caja).efectivo, 0)),
        'transferencia', round(coalesce((caja).transferencia, 0)), 'credito', round(coalesce((caja).credito, 0)), 'debito', round(coalesce((caja).debito, 0)), 'qr', round(coalesce((caja).qr, 0))) end,
    'diferencia_total', round(coalesce((caja).total, 0) - coalesce((pos).total, 0)),
    'dif_efectivo', round(coalesce((caja).efectivo, 0) - coalesce((pos).efectivo, 0)),
    'dif_transferencia', round(coalesce((caja).transferencia, 0) - coalesce((pos).transferencia, 0)),
    'dif_credito', round(coalesce((caja).credito, 0) - coalesce((pos).credito, 0)),
    'dif_debito', round(coalesce((caja).debito, 0) - coalesce((pos).debito, 0)),
    'dif_qr', round(coalesce((caja).qr, 0) - coalesce((pos).qr, 0)),
    'anulaciones', coalesce((pos).anulaciones, 0), 'monto_anulado', round(coalesce((pos).monto_anulado, 0)),
    'falta', case when (caja).dia is null then 'no hay cierre de caja cargado' when (pos).dia is null then 'no hay ventas de Postberry cargadas' end
  ) order by dia), '[]'::jsonb) into v from d;
  return v;
end;
$$;
grant execute on function public.pos_control_caja(date, date) to authenticated;
