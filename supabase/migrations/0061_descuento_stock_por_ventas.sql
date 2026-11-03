-- Gata Maula: descuento de stock segun las ventas de Postberry (vermut, bebidas y soda) + conteo de stock.
--   * Cada producto de Postberry se vincula a uno o mas insumos: por unidad (bebidas, botellas), por "medida" (vermut: ml que se sirve / ml que trae la botella)
--     o por ml exactos (promo pinguino). La soda sale sola: 1 sifon cada 3 medidas del mismo ticket (4 medidas = 2 sodas).
--   * La merma de servir (4,17%) se suma a cada medida: 90 ml sobre 750 ml = 1/8 de botella (8 vasos por botella).
--   * El vermut Gata Maula de barril se lleva en LITROS (insumo "VERMUT GATA MAULA BARRIL (litros)"). Cuando entra un barril por factura,
--     sus litros pasan solos a ese insumo.
--   * Solo se descuenta lo vendido DESPUES del ultimo conteo de cada producto ("Contar stock"). Sin conteo no se toca el stock (igual se registra lo vendido).
--   * Facu, Manu y el admin pueden subir las ventas de Postberry.
--   * Al terminar se vinculan solos los productos que se reconocen; el resto queda en la lista "sin vincular" para revisar en la app.
-- Correr UNA vez en el SQL Editor (despues de la 0060). Es seguro correrlo mas de una vez.

-- ============================================================ columnas
alter table public.insumos add column if not exists ml_por_unidad numeric(10,2);   -- ml que trae 1 unidad de stock (botella 750, BIB 5000, litro 1000)
alter table public.insumos add column if not exists ml_medida numeric(10,2);       -- ml que se sirve por medida
alter table public.insumos add column if not exists pool_insumo_id uuid references public.insumos(id) on delete set null; -- los barriles que entran se suman en litros a este insumo
alter table public.stock add column if not exists conteo_en timestamptz;           -- hasta cuando llega el ultimo conteo fisico
alter table public.stock drop constraint if exists stock_unidad_check;
alter table public.stock add constraint stock_unidad_check check (unidad in ('kg', 'unidad', 'litro'));

create or replace function public.configurar_pedido_stock(
  p_insumo_id uuid, p_minimo numeric, p_proveedor text, p_dias text, p_cantidad text, p_unidad text default null
)
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if public.rol_actual() not in ('admin', 'encargado') then raise exception 'Sin permiso'; end if;
  if p_minimo is null or p_minimo < 0 then raise exception 'El minimo tiene que ser 0 o mas'; end if;
  if p_unidad is not null and p_unidad not in ('kg', 'unidad', 'litro') then raise exception 'Unidad invalida'; end if;
  update public.stock set
    stock_minimo = p_minimo,
    proveedor_pedido = nullif(trim(coalesce(p_proveedor, '')), ''),
    dias_pedido = nullif(trim(coalesce(p_dias, '')), ''),
    cantidad_pedido = nullif(trim(coalesce(p_cantidad, '')), ''),
    unidad = coalesce(p_unidad, unidad)
  where insumo_id = p_insumo_id;
  if not found then raise exception 'Ese insumo no tiene stock cargado'; end if;
  return jsonb_build_object('ok', true);
end;
$$;
grant execute on function public.configurar_pedido_stock(uuid, numeric, text, text, text, text) to authenticated;

-- ============================================================ tablas
create table if not exists public.pos_config (
  clave text primary key,
  valor text not null
);
alter table public.pos_config enable row level security;

create table if not exists public.pos_producto (            -- productos de Postberry que no descuentan stock (o notas)
  producto text primary key,
  familia text,
  omitir text check (omitir in ('comida', 'sin_stock')),
  nota text
);
alter table public.pos_producto enable row level security;

create table if not exists public.pos_vinculo (             -- que insumo(s) descuenta cada producto de Postberry
  id bigserial primary key,
  producto text not null,
  insumo_id uuid not null references public.insumos(id) on delete cascade,
  modo text not null check (modo in ('unidad', 'medida', 'ml')),
  valor numeric(12,3) not null default 1,                   -- unidad: cuantas unidades; medida: cuantas medidas; ml: cuantos ml
  lleva_soda boolean not null default false,
  unique (producto, insumo_id)
);
alter table public.pos_vinculo enable row level security;

create table if not exists public.pos_consumo (             -- lo que se uso segun las ventas (historial) y si ya se descuento del stock
  id bigserial primary key,
  venta_id text,
  fecha timestamp not null,
  dia date not null,
  producto text,
  insumo_id uuid not null references public.insumos(id) on delete cascade,
  cantidad numeric(14,5) not null,
  descontado boolean not null default false
);
create index if not exists pos_consumo_fecha_idx on public.pos_consumo (fecha);
create index if not exists pos_consumo_insumo_idx on public.pos_consumo (insumo_id, fecha);
alter table public.pos_consumo enable row level security;

drop policy if exists pos_config_select on public.pos_config;
create policy pos_config_select on public.pos_config for select using (public.rol_actual() in ('admin', 'encargado'));
drop policy if exists pos_producto_select on public.pos_producto;
create policy pos_producto_select on public.pos_producto for select using (public.rol_actual() in ('admin', 'encargado'));
drop policy if exists pos_vinculo_select on public.pos_vinculo;
create policy pos_vinculo_select on public.pos_vinculo for select using (public.rol_actual() in ('admin', 'encargado'));
drop policy if exists pos_consumo_select on public.pos_consumo;
create policy pos_consumo_select on public.pos_consumo for select using (public.rol_actual() in ('admin', 'encargado'));

insert into public.pos_config (clave, valor) values ('merma_medida_pct', '4.17'), ('medidas_por_soda', '3')
  on conflict (clave) do nothing;

-- ============================================================ insumos nuevos: vermut Gata Maula en litros y soda
insert into public.insumos (nombre, marca, grupo, subcategoria, precio_costo_kg, unidad_medida, origen_alta, ml_por_unidad, ml_medida)
select 'VERMUT GATA MAULA BARRIL (litros)', null, 'bebidas', 'vermut', 4800, 'kg', 'manual', 1000, 90
 where not exists (select 1 from public.insumos where nombre = 'VERMUT GATA MAULA BARRIL (litros)');
insert into public.insumos (nombre, marca, grupo, subcategoria, precio_costo_kg, unidad_medida, origen_alta, ml_por_unidad)
select 'SODA SIFON 500 CC', null, 'bebidas', 'cerveza y sin alcohol', 0, 'unidad', 'manual', 500
 where not exists (select 1 from public.insumos where nombre = 'SODA SIFON 500 CC');

insert into public.stock (insumo_id, cantidad_actual, stock_minimo, valorizacion, unidad)
select id, 0, 0, 0, 'litro' from public.insumos where nombre = 'VERMUT GATA MAULA BARRIL (litros)'
on conflict (insumo_id) do nothing;
insert into public.stock (insumo_id, cantidad_actual, stock_minimo, valorizacion, unidad)
select id, 0, 0, 0, 'unidad' from public.insumos where nombre = 'SODA SIFON 500 CC'
on conflict (insumo_id) do nothing;

update public.insumos set stock_iva = 1.00 where nombre = 'VERMUT GATA MAULA BARRIL (litros)';   -- como en tu planilla, el barril propio no lleva IVA
insert into public.pos_config (clave, valor) select 'insumo_gm', id::text from public.insumos where nombre = 'VERMUT GATA MAULA BARRIL (litros)'
  on conflict (clave) do update set valor = excluded.valor;
insert into public.pos_config (clave, valor) select 'insumo_soda', id::text from public.insumos where nombre = 'SODA SIFON 500 CC'
  on conflict (clave) do update set valor = excluded.valor;

-- los barriles de Gata Maula que entran por factura se suman en litros al insumo de litros
update public.insumos b set pool_insumo_id = (select valor::uuid from public.pos_config where clave = 'insumo_gm'),
       ml_por_unidad = coalesce((regexp_match(upper(b.nombre), '(\d+)\s*L'))[1]::numeric, 5) * 1000
 where b.subcategoria::text = 'vermut' and public.normalizar_texto(b.nombre) like '%GATA MAULA%' and public.normalizar_texto(b.nombre) like '%BARRIL%'
   and b.nombre <> 'VERMUT GATA MAULA BARRIL (litros)';

-- ============================================================ tamaño de botella y ml por medida de cada vermut
update public.insumos i set ml_por_unidad = case
    when n like '%MAGNUM%' then 1500
    when n ~ '(BAG|BIB| BOX)' and n like '%INTERFERENCIA%' then 3000
    when n ~ '(BAG|BIB| BOX)' and (n like '%LOMBRONI%' or n like '%CHARLA%') then 5000
    when n ~ '(BAG|BIB| BOX)' then null
    else 750 end
  from (select id, public.normalizar_texto(trim(coalesce(marca || ' ', '') || nombre)) as n from public.insumos) x
 where x.id = i.id and i.ml_por_unidad is null and i.pool_insumo_id is null
   and (i.subcategoria::text = 'vermut' or x.n like '%LORENZO%');

update public.insumos i set ml_medida = case
    when n ~ '(MALA MARIA|CACCIATORE|REFUGE|BUM BUM)' then 110
    when n like '%CHARLA%' then 83
    when n like '%LOMBRONI%' then 90
    when n like '%PRIMMO%' then 101
    when n like '%LA FUERZA%' then 85
    when n like '%GIOVANON%' then 98
    else 90 end
  from (select id, public.normalizar_texto(trim(coalesce(marca || ' ', '') || nombre)) as n from public.insumos) x
 where x.id = i.id and i.ml_medida is null and i.ml_por_unidad is not null and i.pool_insumo_id is null
   and (i.subcategoria::text = 'vermut' or x.n like '%LORENZO%');

-- ============================================================ traspaso de barriles a litros (cuando entra stock de un barril)
create or replace function public._stock_pool_trg() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_pool uuid; v_ml numeric; v_delta numeric; v_precio numeric;
begin
  if pg_trigger_depth() > 1 then return new; end if;
  select pool_insumo_id, ml_por_unidad into v_pool, v_ml from public.insumos where id = new.insumo_id;
  if v_pool is null or coalesce(v_ml, 0) <= 0 then return new; end if;
  v_delta := new.cantidad_actual;
  if tg_op = 'UPDATE' then v_delta := new.cantidad_actual - old.cantidad_actual; end if;
  if v_delta <= 0 then return new; end if;
  insert into public.stock (insumo_id, cantidad_actual, stock_minimo, valorizacion, unidad) values (v_pool, 0, 0, 0, 'litro') on conflict (insumo_id) do nothing;
  select precio_costo_kg into v_precio from public.insumos where id = v_pool;
  update public.stock set cantidad_actual = cantidad_actual - v_delta, valorizacion = 0 where insumo_id = new.insumo_id;
  update public.stock set cantidad_actual = cantidad_actual + v_delta * v_ml / 1000,
         valorizacion = greatest(cantidad_actual + v_delta * v_ml / 1000, 0) * coalesce(v_precio, 0), ultima_actualizacion = now()
   where insumo_id = v_pool;
  return new;
end;
$$;
drop trigger if exists stock_pool on public.stock;
create trigger stock_pool after insert or update of cantidad_actual on public.stock for each row execute function public._stock_pool_trg();

-- ============================================================ conteo de stock
create or replace function public._contar_uno(p_insumo uuid, p_cant numeric, p_en timestamptz, p_usuario uuid)
returns numeric
language plpgsql security definer set search_path = public as $$
declare v_precio numeric; v_act numeric; v_local timestamp := (p_en at time zone 'America/Argentina/Buenos_Aires'); v_pend numeric; v_final numeric;
begin
  select precio_costo_kg into v_precio from public.insumos where id = p_insumo;
  if v_precio is null then raise exception 'Insumo no encontrado'; end if;
  select cantidad_actual into v_act from public.stock where insumo_id = p_insumo;
  if not found then raise exception 'Ese insumo no esta en el stock'; end if;
  -- lo vendido despues del conteo y ya descontado sigue valiendo; lo anterior ya estaba incluido en lo que se conto
  select coalesce(sum(cantidad), 0) into v_pend from public.pos_consumo where insumo_id = p_insumo and descontado and fecha > v_local;
  update public.pos_consumo set descontado = false where insumo_id = p_insumo and descontado and fecha <= v_local;
  v_final := p_cant - v_pend;
  if v_final <> v_act then
    insert into public.movimientos_stock (insumo_id, tipo, cantidad, origen, usuario_id) values (p_insumo, 'ajuste', v_final - v_act, 'manual', p_usuario);
  end if;
  update public.stock set cantidad_actual = v_final, valorizacion = greatest(v_final, 0) * v_precio, ultima_actualizacion = now(), conteo_en = p_en
   where insumo_id = p_insumo;
  return v_final;
end;
$$;
revoke all on function public._contar_uno(uuid, numeric, timestamptz, uuid) from public;

drop function if exists public.ajustar_stock_conteo(uuid, numeric);
create or replace function public.ajustar_stock_conteo(p_insumo_id uuid, p_cantidad_nueva numeric, p_contado_en timestamptz default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_usuario uuid := auth.uid(); v_final numeric;
begin
  if v_usuario is null then raise exception 'No autenticado'; end if;
  if public.rol_actual() not in ('admin', 'encargado', 'cocina') then raise exception 'Sin permiso'; end if;
  if p_cantidad_nueva is null or p_cantidad_nueva < 0 then raise exception 'Cantidad inválida'; end if;
  if p_contado_en is not null and p_contado_en > now() + interval '5 minutes' then raise exception 'La fecha del conteo no puede ser futura'; end if;
  v_final := public._contar_uno(p_insumo_id, p_cantidad_nueva, coalesce(p_contado_en, now()), v_usuario);
  return jsonb_build_object('success', true, 'cantidad_actual', v_final);
end;
$$;
grant execute on function public.ajustar_stock_conteo(uuid, numeric, timestamptz) to authenticated;

create or replace function public.contar_stock(p_items jsonb, p_contado_en timestamptz default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_usuario uuid := auth.uid(); r record; n int := 0; v_en timestamptz := coalesce(p_contado_en, now());
begin
  if v_usuario is null then raise exception 'No autenticado'; end if;
  if public.rol_actual() not in ('admin', 'encargado', 'cocina') then raise exception 'Sin permiso'; end if;
  if v_en > now() + interval '5 minutes' then raise exception 'La fecha del conteo no puede ser futura'; end if;
  for r in select * from jsonb_to_recordset(p_items) as t(insumo_id uuid, cantidad numeric) loop
    if r.cantidad is null or r.cantidad < 0 then raise exception 'Cantidad inválida'; end if;
    perform public._contar_uno(r.insumo_id, r.cantidad, v_en, v_usuario);
    n := n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'contados', n);
end;
$$;
grant execute on function public.contar_stock(jsonb, timestamptz) to authenticated;

-- ============================================================ subir ventas: tambien los encargados
create or replace function public.pos_borrar_rango(p_desde timestamp, p_hasta timestamp, p_lineas boolean default true, p_pagos boolean default true)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare a int := 0; b int := 0;
begin
  if public.rol_actual() not in ('admin', 'encargado') then raise exception 'Sin permiso'; end if;
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
  if public.rol_actual() not in ('admin', 'encargado') then raise exception 'Sin permiso'; end if;
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
  if public.rol_actual() not in ('admin', 'encargado') then raise exception 'Sin permiso'; end if;
  insert into public.pos_pagos (fecha, cond_pago, documento, pv, numero, importe, tipo, observacion)
  select fecha, cond_pago, documento, pv, numero, importe, tipo, observacion
    from jsonb_to_recordset(p_filas) as t(fecha timestamp, cond_pago text, documento text, pv int, numero bigint, importe numeric, tipo text, observacion text);
  get diagnostics n = row_count;
  return n;
end;
$$;
grant execute on function public.pos_cargar_pagos(jsonb) to authenticated;

-- ============================================================ calculo del consumo y descuento
-- Vuelve a calcular el periodo: devuelve al stock lo que ya se habia descontado, borra y vuelve a generar. Se puede repetir sin duplicar.
create or replace function public._pos_aplicar(p_desde timestamp, p_hasta timestamp)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_merma numeric := coalesce((select valor::numeric from public.pos_config where clave = 'merma_medida_pct'), 0);
  v_msoda numeric := greatest(coalesce((select valor::numeric from public.pos_config where clave = 'medidas_por_soda'), 3), 1);
  v_soda uuid := (select valor::uuid from public.pos_config where clave = 'insumo_soda');
  v_filas int; v_desc int;
begin
  update public.stock s set cantidad_actual = s.cantidad_actual + x.t,
         valorizacion = greatest(s.cantidad_actual + x.t, 0) * coalesce(i.precio_costo_kg, 0), ultima_actualizacion = now()
    from (select insumo_id, sum(cantidad) as t from public.pos_consumo where fecha between p_desde and p_hasta and descontado group by insumo_id) x
    join public.insumos i on i.id = x.insumo_id
   where s.insumo_id = x.insumo_id;
  delete from public.pos_consumo where fecha between p_desde and p_hasta;

  insert into public.pos_consumo (venta_id, fecha, dia, producto, insumo_id, cantidad, descontado)
  select g.venta_id, g.fecha, (g.fecha - interval '6 hours')::date, g.producto, g.insumo_id, g.cantidad,
         coalesce(st.conteo_en is not null and g.fecha > (st.conteo_en at time zone 'America/Argentina/Buenos_Aires'), false)
    from (
      select l.venta_id, l.fecha, l.producto, v.insumo_id,
             l.cantidad * case v.modo
               when 'unidad' then v.valor
               when 'ml' then v.valor / i.ml_por_unidad
               else v.valor * (i.ml_medida * (1 + v_merma / 100)) / i.ml_por_unidad end as cantidad
        from public.pos_lineas l
        join public.pos_vinculo v on v.producto = l.producto
        join public.insumos i on i.id = v.insumo_id
       where not l.anulado and l.fecha between p_desde and p_hasta and coalesce(l.cantidad, 0) <> 0
         and (v.modo = 'unidad' or coalesce(i.ml_por_unidad, 0) > 0)
         and (v.modo <> 'medida' or coalesce(i.ml_medida, 0) > 0)
      union all
      select t.venta_id, t.fecha, 'SODA (1 cada ' || v_msoda::int || ' medidas)', v_soda, ceil(t.med / v_msoda)
        from (select l.venta_id, min(l.fecha) as fecha, sum(l.cantidad * v.valor) as med
                from public.pos_lineas l join public.pos_vinculo v on v.producto = l.producto
               where v.lleva_soda and not l.anulado and l.fecha between p_desde and p_hasta
               group by l.venta_id) t
       where v_soda is not null and t.med > 0
    ) g
    left join public.stock st on st.insumo_id = g.insumo_id;
  get diagnostics v_filas = row_count;

  update public.stock s set cantidad_actual = s.cantidad_actual - x.t,
         valorizacion = greatest(s.cantidad_actual - x.t, 0) * coalesce(i.precio_costo_kg, 0), ultima_actualizacion = now()
    from (select insumo_id, sum(cantidad) as t from public.pos_consumo where fecha between p_desde and p_hasta and descontado group by insumo_id) x
    join public.insumos i on i.id = x.insumo_id
   where s.insumo_id = x.insumo_id;
  select count(*) into v_desc from public.pos_consumo where fecha between p_desde and p_hasta and descontado;
  return jsonb_build_object('consumos', v_filas, 'descontados', v_desc);
end;
$$;
revoke all on function public._pos_aplicar(timestamp, timestamp) from public;

create or replace function public.pos_aplicar_consumo(p_desde timestamp, p_hasta timestamp)
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if public.rol_actual() not in ('admin', 'encargado') then raise exception 'Sin permiso'; end if;
  return public._pos_aplicar(p_desde, p_hasta);
end;
$$;
grant execute on function public.pos_aplicar_consumo(timestamp, timestamp) to authenticated;

-- Recalcula todo lo que hay cargado de Postberry
create or replace function public.pos_recalcular_todo()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare a timestamp; b timestamp;
begin
  if public.rol_actual() not in ('admin', 'encargado') then raise exception 'Sin permiso'; end if;
  select min(fecha), max(fecha) into a, b from public.pos_lineas;
  if a is null then return jsonb_build_object('consumos', 0, 'descontados', 0); end if;
  return public._pos_aplicar(a, b);
end;
$$;
grant execute on function public.pos_recalcular_todo() to authenticated;

-- ============================================================ vinculos automaticos
create or replace function public._pos_tokens(p text) returns text[]
language sql stable as $$
  select coalesce(array_agg(distinct case when length(t) > 3 and right(t, 1) = 'S' then left(t, length(t) - 1) else t end), '{}'::text[])
    from unnest(regexp_split_to_array(regexp_replace(upper(unaccent(coalesce(p, ''))), '[^A-Z0-9]+', ' ', 'g'), ' ')) as t
   where t <> '' and t not in ('MEDIDA', 'MEDIDDA', 'VERMUT', 'VERMUTH', 'VERMOUTH', 'VERMU', 'SIFON', 'SODA', 'CITRICO', 'CITRICOS', 'HIELO', 'BOTELLA', 'DE', 'DEL', 'LA', 'EL', 'Y', 'CC', 'SIN', 'ALCOHOL');
$$;

create or replace function public._pos_match_insumo(p_producto text, p_subs text[]) returns uuid
language sql stable security definer set search_path = public as $$
  -- devuelve el insumo que mejor coincide; si dos empatan (ej. "aperitivo lorenzo" sin decir tinto o bianco) no elige ninguno
  with c as (
    select i.id, c.comunes::numeric / array_length(k.tp, 1) as score, coalesce(array_length(k.ti, 1), 0) - c.comunes as extras,
           (case when i.ml_por_unidad = 750 then 0 else 1 end) as pri
      from public.insumos i
      join public.stock s on s.insumo_id = i.id,
      lateral (select public._pos_tokens(trim(coalesce(i.marca || ' ', '') || i.nombre)) as ti, public._pos_tokens(p_producto) as tp) k,
      lateral (select (select count(*) from unnest(k.tp) a where a = any(k.ti)) as comunes) c
     where not i.es_preparacion and i.subcategoria::text = any(p_subs)
       and i.nombre not in ('VERMUT GATA MAULA BARRIL (litros)', 'SODA SIFON 500 CC')
       and coalesce(array_length(k.tp, 1), 0) > 0 and c.comunes::numeric / array_length(k.tp, 1) >= 0.67
  ), t as (select * from c order by score desc, extras, pri limit 1)
  select (select id from t) where (select count(*) from c join t on c.score = t.score and c.extras = t.extras and c.pri = t.pri) = 1;
$$;

create or replace function public._pos_autovincular() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  r record; nom text; v_ins uuid; n_v int := 0; n_o int := 0; n_p int := 0;
  v_gm uuid := (select valor::uuid from public.pos_config where clave = 'insumo_gm');
  v_soda uuid := (select valor::uuid from public.pos_config where clave = 'insumo_soda');
begin
  for r in select p.producto, p.familia from (select producto, max(familia) as familia from public.pos_lineas group by producto) p
            where not exists (select 1 from public.pos_vinculo v where v.producto = p.producto)
              and not exists (select 1 from public.pos_producto x where x.producto = p.producto and x.omitir is not null)
  loop
    nom := public.normalizar_texto(r.producto);
    v_ins := null;
    if nom like '%HAPPY HOUR%' then
      insert into public.pos_producto (producto, familia, omitir, nota) values (r.producto, r.familia, 'sin_stock', 'Las 3 medidas se descuentan cuando se usa cada Gata Coin')
        on conflict (producto) do update set omitir = excluded.omitir, nota = excluded.nota;
      n_o := n_o + 1;
    elsif (nom like '%GATA COIN%' or nom ~ '^GM +MEDIDA' or nom like 'VERMUT GATA MAULA%') and v_gm is not null then
      insert into public.pos_vinculo (producto, insumo_id, modo, valor, lleva_soda) values (r.producto, v_gm, 'medida', 1, true) on conflict (producto, insumo_id) do nothing;
      n_v := n_v + 1;
    elsif nom like '%PINGUINO%' and v_gm is not null then
      insert into public.pos_vinculo (producto, insumo_id, modo, valor, lleva_soda) values (r.producto, v_gm, 'ml', 740, false) on conflict (producto, insumo_id) do nothing;
      if v_soda is not null then
        insert into public.pos_vinculo (producto, insumo_id, modo, valor, lleva_soda) values (r.producto, v_soda, 'unidad', 1, false) on conflict (producto, insumo_id) do nothing;
      end if;
      n_v := n_v + 1;
    elsif nom like 'SIFONCITO%' and v_soda is not null then
      insert into public.pos_vinculo (producto, insumo_id, modo, valor, lleva_soda) values (r.producto, v_soda, 'unidad', 1, false) on conflict (producto, insumo_id) do nothing;
      n_v := n_v + 1;
    elsif nom like 'BOTELLA %' then
      v_ins := public._pos_match_insumo(r.producto, array['vermut', 'cerveza y sin alcohol']);
      if v_ins is not null then
        insert into public.pos_vinculo (producto, insumo_id, modo, valor, lleva_soda) values (r.producto, v_ins, 'unidad', 1, false) on conflict (producto, insumo_id) do nothing;
        n_v := n_v + 1;
      else n_p := n_p + 1; end if;
    elsif nom like 'MEDIDA %' or nom like 'MEDIDDA %' or coalesce(r.familia, '') in ('MEDIDA VERMUT', 'VERMOUTH') then
      v_ins := public._pos_match_insumo(r.producto, array['vermut', 'cerveza y sin alcohol']);
      if v_ins is not null then
        insert into public.pos_vinculo (producto, insumo_id, modo, valor, lleva_soda) values (r.producto, v_ins, 'medida', 1, nom not like '%SIN ALCOHOL%') on conflict (producto, insumo_id) do nothing;
        n_v := n_v + 1;
      else n_p := n_p + 1; end if;
    elsif coalesce(r.familia, '') = 'AGUAS, GASEOSAS Y CERVEZAS' then
      v_ins := public._pos_match_insumo(r.producto, array['cerveza y sin alcohol']);
      if v_ins is not null then
        insert into public.pos_vinculo (producto, insumo_id, modo, valor, lleva_soda) values (r.producto, v_ins, 'unidad', 1, false) on conflict (producto, insumo_id) do nothing;
        n_v := n_v + 1;
      else n_p := n_p + 1; end if;
    else
      insert into public.pos_producto (producto, familia, omitir, nota) values (r.producto, r.familia, 'comida', 'Comida: se descuenta en la etapa de recetas')
        on conflict (producto) do update set omitir = excluded.omitir, nota = excluded.nota;
      n_o := n_o + 1;
    end if;
  end loop;
  return jsonb_build_object('vinculados', n_v, 'no_descuentan', n_o, 'sin_encontrar', n_p);
end;
$$;
revoke all on function public._pos_autovincular() from public;

create or replace function public.pos_autovincular() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v jsonb;
begin
  if public.rol_actual() not in ('admin', 'encargado') then raise exception 'Sin permiso'; end if;
  v := public._pos_autovincular();
  perform public.pos_recalcular_todo();
  return v;
end;
$$;
grant execute on function public.pos_autovincular() to authenticated;

-- ============================================================ pantalla de revision
create or replace function public.pos_productos_vinculos() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if public.rol_actual() not in ('admin', 'encargado') then raise exception 'Sin permiso'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'producto', p.producto, 'familia', p.familia, 'unidades', p.u, 'omitir', pp.omitir, 'nota', pp.nota,
      'vinculos', coalesce((select jsonb_agg(jsonb_build_object('insumo_id', v.insumo_id, 'modo', v.modo, 'valor', v.valor, 'lleva_soda', v.lleva_soda,
                                'insumo', trim(coalesce(i.marca || ' ', '') || i.nombre)) order by v.id)
                              from public.pos_vinculo v join public.insumos i on i.id = v.insumo_id where v.producto = p.producto), '[]'::jsonb))
      order by p.u desc)
    from (select producto, max(familia) as familia, sum(cantidad) as u from public.pos_lineas where not anulado group by producto) p
    left join public.pos_producto pp on pp.producto = p.producto), '[]'::jsonb);
end;
$$;
grant execute on function public.pos_productos_vinculos() to authenticated;

create or replace function public.pos_vinculo_guardar(p_producto text, p_vinculos jsonb, p_omitir text default null, p_nota text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare a timestamp; b timestamp;
begin
  if public.rol_actual() not in ('admin', 'encargado') then raise exception 'Sin permiso'; end if;
  if p_omitir is not null and p_omitir not in ('comida', 'sin_stock') then raise exception 'Valor invalido'; end if;
  delete from public.pos_vinculo where producto = p_producto;
  if p_omitir is null then
    insert into public.pos_vinculo (producto, insumo_id, modo, valor, lleva_soda)
    select p_producto, t.insumo_id, t.modo, coalesce(t.valor, 1), coalesce(t.lleva_soda, false)
      from jsonb_to_recordset(coalesce(p_vinculos, '[]'::jsonb)) as t(insumo_id uuid, modo text, valor numeric, lleva_soda boolean)
     where t.insumo_id is not null and t.modo in ('unidad', 'medida', 'ml')
    on conflict (producto, insumo_id) do update set modo = excluded.modo, valor = excluded.valor, lleva_soda = excluded.lleva_soda;
  end if;
  insert into public.pos_producto (producto, familia, omitir, nota)
    values (p_producto, (select max(familia) from public.pos_lineas where producto = p_producto), p_omitir, nullif(trim(coalesce(p_nota, '')), ''))
    on conflict (producto) do update set omitir = excluded.omitir, nota = excluded.nota;
  select min(fecha), max(fecha) into a, b from public.pos_lineas where producto = p_producto;
  if a is not null then perform public._pos_aplicar(a, b); end if;
  return jsonb_build_object('ok', true);
end;
$$;
grant execute on function public.pos_vinculo_guardar(text, jsonb, text, text) to authenticated;

create or replace function public.pos_insumo_ml_guardar(p_insumo uuid, p_ml_unidad numeric, p_ml_medida numeric)
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if public.rol_actual() not in ('admin', 'encargado') then raise exception 'Sin permiso'; end if;
  if (p_ml_unidad is not null and p_ml_unidad <= 0) or (p_ml_medida is not null and p_ml_medida <= 0) then raise exception 'Los ml tienen que ser mayores a 0'; end if;
  update public.insumos set ml_por_unidad = p_ml_unidad, ml_medida = p_ml_medida where id = p_insumo;
  perform public.pos_recalcular_todo();
  return jsonb_build_object('ok', true);
end;
$$;
grant execute on function public.pos_insumo_ml_guardar(uuid, numeric, numeric) to authenticated;

create or replace function public.pos_estado_descuento() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if public.rol_actual() not in ('admin', 'encargado') then raise exception 'Sin permiso'; end if;
  return jsonb_build_object(
    'ventas_hasta', (select max(fecha) from public.pos_lineas),
    'consumo_hasta', (select max(fecha) from public.pos_consumo),
    'sin_vincular', coalesce((select jsonb_agg(jsonb_build_object('producto', p.producto, 'familia', p.familia, 'unidades', p.u) order by p.u desc)
                                from (select producto, max(familia) as familia, sum(cantidad) as u from public.pos_lineas where not anulado group by producto) p
                               where not exists (select 1 from public.pos_vinculo v where v.producto = p.producto)
                                 and not exists (select 1 from public.pos_producto x where x.producto = p.producto and x.omitir is not null)), '[]'::jsonb),
    'sin_conteo', coalesce((select jsonb_agg(jsonb_build_object('id', z.id, 'nombre', z.nombre) order by z.nombre)
                              from (select distinct i.id, trim(coalesce(i.marca || ' ', '') || i.nombre) as nombre
                                      from public.pos_consumo c join public.insumos i on i.id = c.insumo_id
                                      left join public.stock s on s.insumo_id = c.insumo_id
                                     where s.conteo_en is null or s.insumo_id is null) z), '[]'::jsonb),
    'sin_ml', coalesce((select jsonb_agg(jsonb_build_object('id', z.id, 'nombre', z.nombre) order by z.nombre)
                          from (select distinct i.id, trim(coalesce(i.marca || ' ', '') || i.nombre) as nombre
                                  from public.pos_vinculo v join public.insumos i on i.id = v.insumo_id
                                 where (v.modo in ('ml', 'medida') and coalesce(i.ml_por_unidad, 0) <= 0) or (v.modo = 'medida' and coalesce(i.ml_medida, 0) <= 0)) z), '[]'::jsonb)
  );
end;
$$;
grant execute on function public.pos_estado_descuento() to authenticated;

-- lo que se uso segun las ventas en un periodo (dia de negocio)
create or replace function public.pos_consumo_resumen(p_desde date, p_hasta date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if public.rol_actual() not in ('admin', 'encargado') then raise exception 'Sin permiso'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('insumo_id', z.id, 'nombre', z.nombre, 'subcategoria', z.sub, 'unidad', z.unidad, 'cantidad', round(z.cant, 3),
                      'valor', round(z.cant * z.precio), 'descontado', round(coalesce(z.descontada, 0), 3)) order by z.cant * z.precio desc)
      from (select i.id, trim(coalesce(i.marca || ' ', '') || i.nombre) as nombre, i.subcategoria::text as sub, s.unidad, i.precio_costo_kg as precio,
                   sum(c.cantidad) as cant, sum(c.cantidad) filter (where c.descontado) as descontada
              from public.pos_consumo c join public.insumos i on i.id = c.insumo_id left join public.stock s on s.insumo_id = i.id
             where c.dia between p_desde and p_hasta group by i.id, s.unidad) z), '[]'::jsonb);
end;
$$;
grant execute on function public.pos_consumo_resumen(date, date) to authenticated;

-- ============================================================ vincular lo que se reconoce y calcular lo ya cargado
select public._pos_autovincular() as autovinculacion;
do $$
declare a timestamp; b timestamp;
begin
  select min(fecha), max(fecha) into a, b from public.pos_lineas;
  if a is not null then perform public._pos_aplicar(a, b); end if;
end
$$;

-- ============================================================ resultado: como quedo cada producto de Postberry (revisar la columna "insumo")
select coalesce(p.familia, '') as familia, p.producto, round(p.u) as vendidas,
       coalesce((select string_agg(i.nombre || ' [' || v.modo || ']', ' + ') from public.pos_vinculo v join public.insumos i on i.id = v.insumo_id where v.producto = p.producto),
                (select 'NO DESCUENTA: ' || x.omitir from public.pos_producto x where x.producto = p.producto and x.omitir is not null), 'SIN VINCULAR') as insumo
  from (select producto, max(familia) as familia, sum(cantidad) as u from public.pos_lineas where not anulado group by producto) p
 order by 1, 2;
