-- Gata Maula: calendario de pagos que se descuenta solo + descuento por pago en efectivo de proveedores.
--   * proveedores.descuento_efectivo_pct: % de descuento si se paga en efectivo (Papu Cuisine = 10)
--   * Cuando alguien anota en "Ingresos y egresos" un pago (efectivo o banco) de un proveedor y coincide con un pago pendiente del calendario
--     (mismo proveedor y mismo monto; o el monto con el descuento por efectivo), el calendario lo marca como pagado solo.
--       - el pago anotado pasa al concepto "PAGO DEUDA PROVEEDORES" (si no, el gasto se contaba dos veces: una con la deuda y otra con el pago)
--       - si hubo descuento, se registra el descuento (baja el gasto de la compra, igual que una nota de credito)
--   * El boton "Pagar" del calendario tambien aplica el descuento si se paga en efectivo.
--   * Al final se corre una vez sobre los pagos de los ultimos 60 dias y se muestra que se concilio.
-- Correr UNA vez en el SQL Editor.

alter table public.proveedores add column if not exists descuento_efectivo_pct numeric(5,2);
update public.proveedores set descuento_efectivo_pct = 10 where lower(nombre) like '%papu%';

create or replace function public._calendario_conciliar(p_egreso_id uuid)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  e record; v_nombre text; v_ids uuid[]; v_tot numeric; v_pct numeric; v_nro text;
  v_dto boolean; c record; v_desc numeric; v_conc text;
begin
  select * into e from public.ingresos_egresos where id = p_egreso_id;
  if not found or e.forma not in ('egreso_efectivo', 'egreso_banco') or e.origen <> 'manual' or e.lote_importacion is not null
     or e.proveedor_id is null or coalesce(e.monto, 0) <= 0 or coalesce(e.observaciones, '') like 'Pago de % del %' then
    return null;
  end if;
  select nombre into v_nombre from public.proveedores where id = e.proveedor_id;
  if v_nombre is null then return null; end if;

  with cand as (
    select cp.*, coalesce(pr.descuento_efectivo_pct, 0) as pct
      from public.calendario_pagos cp left join public.proveedores pr on pr.id = cp.proveedor_id
     where not cp.pagado and cp.total > 0
       and (cp.fecha_factura is null or e.fecha >= cp.fecha_factura)
       and cp.egreso_id is distinct from e.id
       and (cp.proveedor_id = e.proveedor_id
            or public.similitud_palabras(public.normalizar_texto(cp.proveedor_texto), public.normalizar_texto(v_nombre)) >= 0.5)
  )
  select z.ids, z.tot, z.pct, z.nro into v_ids, v_tot, v_pct, v_nro from (
    select array[id] as ids, total as tot, pct, nro_factura as nro, 1 as pri, fecha_vencimiento as fv from cand
    union all
    select array_agg(id order by fecha_vencimiento), sum(total), max(pct), nro_factura, 2, min(fecha_vencimiento)
      from cand where nro_factura is not null group by nro_factura
  ) z
  where abs(z.tot - e.monto) < 1
     or (e.forma = 'egreso_efectivo' and z.pct > 0 and abs(round(z.tot * (1 - z.pct / 100), 2) - e.monto) < 1)
  order by z.pri, z.fv limit 1;

  if v_ids is null then return null; end if;
  v_dto := e.forma = 'egreso_efectivo' and v_pct > 0 and abs(v_tot - e.monto) >= 1;

  perform set_config('app.sin_conciliar', '1', true);
  for c in select * from public.calendario_pagos where id = any(v_ids) order by fecha_vencimiento loop
    update public.calendario_pagos set pagado = true, fecha_pago = e.fecha,
        medio_pago = case when e.forma = 'egreso_banco' then 'banco' else 'efectivo' end,
        nota = trim(coalesce(nota || ' · ', '') || 'Se marco pagado solo: pago anotado en Ingresos y egresos el ' || to_char(e.fecha, 'DD/MM') || case when v_dto then ' (con ' || v_pct || '% de descuento por efectivo)' else '' end)
      where id = c.id;
    if c.egreso_id is not null then
      update public.ingresos_egresos set estado_pago = 'pagado', fecha_pago = e.fecha where id = c.egreso_id;
      if v_dto then
        v_desc := round(c.total * v_pct / 100, 2);
        select concepto into v_conc from public.ingresos_egresos where id = c.egreso_id;
        insert into public.ingresos_egresos (fecha, proveedor_id, concepto, factura_numero, monto, forma, estado_pago, medio_pago, fecha_pago, origen, usuario_id, observaciones, lote_importacion, nc_de_factura)
          values (e.fecha, c.proveedor_id, v_conc, null, -v_desc, 'deuda_proveedores', 'pagado'::estado_pago_tipo, 'descuento por pago en efectivo', e.fecha,
                  'manual', e.usuario_id, 'Descuento por pago en efectivo (' || v_pct || '%) factura ' || coalesce(c.nro_factura, 's/n'), to_char(e.fecha, 'YYYY-MM'), c.nro_factura);
      end if;
    end if;
  end loop;

  if e.concepto is distinct from 'PAGO DEUDA PROVEEDORES' then
    update public.ingresos_egresos set concepto = 'PAGO DEUDA PROVEEDORES',
        observaciones = trim(coalesce(observaciones || ' | ', '') || 'Pago de factura' || coalesce(' ' || v_nro, '') || ' (concepto que se habia cargado: ' || e.concepto || ')')
      where id = e.id;
  end if;
  return v_ids[1];
end;
$$;
revoke all on function public._calendario_conciliar(uuid) from public;

create or replace function public.trg_conciliar_pago_calendario()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(current_setting('app.sin_conciliar', true), '') <> '1' then
    perform public._calendario_conciliar(new.id);
  end if;
  return new;
end;
$$;
drop trigger if exists ingresos_egresos_conciliar on public.ingresos_egresos;
create trigger ingresos_egresos_conciliar
  after insert on public.ingresos_egresos
  for each row execute function public.trg_conciliar_pago_calendario();

-- "Pagar" del calendario: ahora aplica el descuento por efectivo del proveedor
create or replace function public.pagar_calendario(p_id uuid, p_forma text, p_fecha date)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  c record;
  v_fecha date := coalesce(p_fecha, public.hoy_ar());
  v_pct numeric := 0; v_desc numeric := 0; v_pago numeric; v_conc text;
begin
  if public.rol_actual() <> 'admin' then
    raise exception 'Sin permiso';
  end if;
  if p_forma not in ('egreso_banco', 'egreso_efectivo') then
    raise exception 'Forma de pago invalida';
  end if;
  select * into c from public.calendario_pagos where id = p_id for update;
  if not found then raise exception 'No se encontro el pago'; end if;
  if c.pagado then raise exception 'Este pago ya figura como pagado'; end if;

  v_pago := c.total;
  if c.egreso_id is not null and p_forma = 'egreso_efectivo' and c.total > 0 then
    select coalesce(descuento_efectivo_pct, 0) into v_pct from public.proveedores where id = c.proveedor_id;
    if v_pct > 0 then v_desc := round(c.total * v_pct / 100, 2); v_pago := c.total - v_desc; end if;
  end if;

  update public.calendario_pagos set pagado = true, fecha_pago = v_fecha,
    medio_pago = case when p_forma = 'egreso_banco' then 'banco' else 'efectivo' end,
    nota = case when v_desc > 0 then trim(coalesce(nota || ' · ', '') || 'Pagado con ' || v_pct || '% de descuento por efectivo') else nota end
  where id = p_id;

  if c.egreso_id is not null then
    perform set_config('app.sin_conciliar', '1', true);
    if v_desc > 0 then
      select concepto into v_conc from public.ingresos_egresos where id = c.egreso_id;
      insert into public.ingresos_egresos (fecha, proveedor_id, concepto, factura_numero, monto, forma, estado_pago, medio_pago, fecha_pago, origen, usuario_id, observaciones, lote_importacion, nc_de_factura)
        values (v_fecha, c.proveedor_id, v_conc, null, -v_desc, 'deuda_proveedores', 'pagado'::estado_pago_tipo, 'descuento por pago en efectivo', v_fecha,
                'manual', auth.uid(), 'Descuento por pago en efectivo (' || v_pct || '%) factura ' || coalesce(c.nro_factura, 's/n'), to_char(v_fecha, 'YYYY-MM'), c.nro_factura);
    end if;
    insert into public.ingresos_egresos
      (fecha, proveedor_id, concepto, factura_numero, monto, forma, estado_pago, medio_pago, fecha_pago, origen, usuario_id, observaciones)
    values
      (v_fecha, c.proveedor_id, 'PAGO DEUDA PROVEEDORES', c.nro_factura, v_pago, p_forma, 'pagado',
       case when p_forma = 'egreso_banco' then 'banco' else 'efectivo' end, v_fecha, 'manual', auth.uid(),
       'Pago de ' || coalesce(c.concepto, '') || ' del ' || coalesce(c.fecha_factura::text, ''));
    update public.ingresos_egresos set estado_pago = 'pagado', fecha_pago = v_fecha where id = c.egreso_id;
  end if;
  return jsonb_build_object('ok', true, 'pagado', v_pago, 'descuento', v_desc);
end;
$$;
grant execute on function public.pagar_calendario(uuid, text, date) to authenticated;

-- Una pasada sobre los pagos anotados en los ultimos 60 dias
do $$
declare r record;
begin
  for r in select id from public.ingresos_egresos
            where origen = 'manual' and forma in ('egreso_efectivo', 'egreso_banco') and lote_importacion is null and proveedor_id is not null
              and fecha >= public.hoy_ar() - 60
            order by fecha, id loop
    perform public._calendario_conciliar(r.id);
  end loop;
end
$$;

-- Lo que se marco pagado solo (para revisar)
select proveedor_texto as proveedor, total, fecha_pago, nro_factura, nota
  from public.calendario_pagos where nota like '%Se marco pagado solo%' order by fecha_pago desc, proveedor_texto;
