-- Gata Maula: los lotes de produccion mueven el stock por receta, y los platos armados se descuentan al venderse.
--   * Al cargar un lote de un producto con receta (los chicos solo eligen el producto y cargan el total elaborado):
--       - SUBE al stock lo elaborado (preparaciones en kg; picadas, antipasti, conos y exquisita en unidades), si ese producto se cuenta en el stock
--       - BAJAN del stock los ingredientes crudos de la receta, en proporcion a lo elaborado (solo los que se llevan en el stock)
--       - la merma declarada al cargar BAJA el stock en ese momento
--     Al editar el lote se recalcula todo. Al terminarlo con merma, baja la merma final. Al reabrirlo se recalcula. Los lotes viejos (anteriores a esto) no se tocan.
--   * Para una preparacion, el rendimiento de la receta es la suma de sus gramos menos la merma de coccion; para un plato armado, 1 receta = 1 unidad
--     (si el lote se carga en kilos, se divide por el peso de la receta).
--   * Los platos armados (picada vermutera, antipasti, plato ahumado, La Exquisita y cono de fiambres y quesos) se descuentan 1 unidad por venta.
--     El dip mediterraneo (racion de 90 g), el dip de camembert y La Cabrita se descuentan por receta al venderse.
--   * Manteca noisette: nueva preparacion con receta 1 kg de manteca tonadita (su precio sigue al de la manteca).
--   * produccion_control: elaborado, vendido y merma por producto en un periodo.
-- Correr UNA vez en el SQL Editor y mandar el resultado. Es seguro correrlo mas de una vez.

-- ============================================================ estructura
alter table public.produccion_items add column if not exists receta_id uuid references public.recetas(id) on delete set null;
alter table public.produccion_lotes add column if not exists aplicar_stock boolean not null default false;

create table if not exists public.produccion_movimientos (
  id bigserial primary key,
  lote_id uuid not null references public.produccion_lotes(id) on delete cascade,
  insumo_id uuid not null references public.insumos(id) on delete cascade,
  tipo text not null check (tipo in ('elaborado', 'ingrediente', 'merma')),
  cantidad numeric(14,5) not null,      -- con signo: + suma al stock, - resta
  created_at timestamptz not null default now()
);
create index if not exists produccion_movimientos_lote_idx on public.produccion_movimientos (lote_id);
alter table public.produccion_movimientos enable row level security;
drop policy if exists produccion_movimientos_select on public.produccion_movimientos;
create policy produccion_movimientos_select on public.produccion_movimientos for select using (public.rol_actual() in ('admin', 'encargado'));

-- ============================================================ aplicar un lote al stock (se puede repetir: primero devuelve lo aplicado antes)
create or replace function public._prod_aplicar_lote(p_lote uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  l record; it record; rc record; v_gr numeric; v_factor numeric; v_unid text;
begin
  select * into l from public.produccion_lotes where id = p_lote;
  if not found or not l.aplicar_stock then return null; end if;

  -- 1) devolver lo aplicado antes
  update public.stock s set cantidad_actual = s.cantidad_actual - x.t,
         valorizacion = greatest(s.cantidad_actual - x.t, 0) * coalesce(i.precio_costo_kg, 0), ultima_actualizacion = now()
    from (select insumo_id, sum(cantidad) as t from public.produccion_movimientos where lote_id = p_lote group by insumo_id) x
    join public.insumos i on i.id = x.insumo_id
   where s.insumo_id = x.insumo_id;
  delete from public.produccion_movimientos where lote_id = p_lote;

  select * into it from public.produccion_items where id = l.item_id;

  -- 2) lo elaborado sube y la merma baja (si el producto se cuenta en el stock y en la misma unidad)
  if it.insumo_id is not null then
    select coalesce(s.unidad, i.unidad_medida) into v_unid from public.stock s join public.insumos i on i.id = s.insumo_id where s.insumo_id = it.insumo_id;
    if v_unid is not null and ((l.unidad = 'kg' and v_unid = 'kg') or (l.unidad = 'unidad' and v_unid = 'unidad')) then
      insert into public.produccion_movimientos (lote_id, insumo_id, tipo, cantidad) values (p_lote, it.insumo_id, 'elaborado', l.cantidad_producida);
      if coalesce(l.cantidad_merma, 0) > 0 then
        insert into public.produccion_movimientos (lote_id, insumo_id, tipo, cantidad) values (p_lote, it.insumo_id, 'merma', -l.cantidad_merma);
      end if;
    end if;
  end if;

  -- 3) ingredientes crudos por receta, en proporcion a lo elaborado
  v_factor := null;
  if it.receta_id is not null then
    select tipo, merma_pct into rc from public.recetas where id = it.receta_id;
    select sum(case when tipo_medida::text = 'gramos' then cantidad else 0 end) into v_gr from public.receta_insumos where receta_id = it.receta_id;
    if rc.tipo = 'preparacion' then
      if l.unidad = 'kg' and coalesce(v_gr, 0) * (1 - coalesce(rc.merma_pct, 0) / 100) > 0 then
        v_factor := l.cantidad_producida * 1000 / (v_gr * (1 - coalesce(rc.merma_pct, 0) / 100));
      end if;
    else
      if l.unidad = 'unidad' then v_factor := l.cantidad_producida;
      elsif coalesce(v_gr, 0) > 0 then v_factor := l.cantidad_producida * 1000 / v_gr;
      end if;
    end if;
    if v_factor is not null then
      insert into public.produccion_movimientos (lote_id, insumo_id, tipo, cantidad)
      select p_lote, x.insumo_id, 'ingrediente', - sum(v_factor * x.cant / x.divisor)
        from (
          select ri.insumo_id, ri.cantidad as cant,
                 case when ri.tipo_medida::text = 'unidad' then (case when st2.unidad = 'kg' then null else 1 end)
                      when coalesce(st2.unidad, i2.unidad_medida) = 'kg' then 1000
                      when coalesce(st2.unidad, i2.unidad_medida) = 'unidad' and coalesce(i2.gramos_paquete, 0) > 0 then i2.gramos_paquete
                      else null end as divisor
            from public.receta_insumos ri
            join public.insumos i2 on i2.id = ri.insumo_id
            join public.stock st2 on st2.insumo_id = ri.insumo_id
           where ri.receta_id = it.receta_id and ri.insumo_id is distinct from it.insumo_id
        ) x
       where x.divisor is not null
       group by x.insumo_id;
    end if;
  end if;

  -- 4) aplicar al stock
  update public.stock s set cantidad_actual = s.cantidad_actual + x.t,
         valorizacion = greatest(s.cantidad_actual + x.t, 0) * coalesce(i.precio_costo_kg, 0), ultima_actualizacion = now()
    from (select insumo_id, sum(cantidad) as t from public.produccion_movimientos where lote_id = p_lote group by insumo_id) x
    join public.insumos i on i.id = x.insumo_id
   where s.insumo_id = x.insumo_id;

  return coalesce((select jsonb_agg(jsonb_build_object('producto', trim(coalesce(i.marca || ' ', '') || i.nombre), 'tipo', m.tipo,
                         'cantidad', round(m.cantidad, 3), 'unidad', coalesce(s.unidad, i.unidad_medida)) order by (m.tipo = 'ingrediente'), m.cantidad desc)
                     from public.produccion_movimientos m join public.insumos i on i.id = m.insumo_id left join public.stock s on s.insumo_id = i.id
                    where m.lote_id = p_lote), '[]'::jsonb);
end;
$$;
revoke all on function public._prod_aplicar_lote(uuid) from public;

-- ============================================================ lotes: crear, editar, terminar y reabrir (igual que antes + mueven el stock)
create or replace function public.produccion_crear_lote(
  p_item_id uuid, p_elaborado date, p_vida_util int, p_cantidad numeric, p_producido_por text,
  p_merma numeric default 0, p_motivo text default null, p_obs text default null, p_unidad text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_elab date := coalesce(p_elaborado, public.hoy_ar()); v_id uuid; v_item_unidad text;
  v_ing text; v_base text; v_f numeric; v_cant numeric; v_merma numeric; v_mov jsonb;
begin
  if public.rol_actual() is null then raise exception 'Sin permiso'; end if;
  select unidad into v_item_unidad from public.produccion_items where id = p_item_id and activo;
  if v_item_unidad is null then raise exception 'Producto no encontrado'; end if;
  v_ing := coalesce(p_unidad, v_item_unidad);
  if v_ing not in ('kg', 'gr', 'unidad') then raise exception 'Unidad invalida'; end if;
  v_base := case when v_ing = 'unidad' then 'unidad' else 'kg' end;
  v_f := case when v_ing = 'gr' then 0.001 else 1 end;
  v_cant := p_cantidad * v_f; v_merma := coalesce(p_merma, 0) * v_f;
  if p_cantidad is null or p_cantidad <= 0 then raise exception 'La cantidad elaborada tiene que ser mayor a 0'; end if;
  if p_vida_util is null or p_vida_util <= 0 then raise exception 'La vida util tiene que ser de 1 dia o mas'; end if;
  if v_merma < 0 or v_merma > v_cant then raise exception 'La merma no puede ser negativa ni mayor a lo elaborado'; end if;
  insert into public.produccion_lotes (item_id, elaborado_el, vida_util_dias, vence_el, cantidad_producida, unidad, unidad_ingreso, producido_por, cantidad_merma, motivo_merma, observaciones, creado_por, aplicar_stock)
    values (p_item_id, v_elab, p_vida_util, v_elab + p_vida_util, v_cant, v_base, v_ing, nullif(trim(coalesce(p_producido_por, '')), ''),
            v_merma, nullif(trim(coalesce(p_motivo, '')), ''), nullif(trim(coalesce(p_obs, '')), ''), auth.uid(), true)
    returning id into v_id;
  v_mov := public._prod_aplicar_lote(v_id);
  return jsonb_build_object('id', v_id, 'movimientos', coalesce(v_mov, '[]'::jsonb));
end;
$$;
grant execute on function public.produccion_crear_lote(uuid, date, int, numeric, text, numeric, text, text, text) to authenticated;

create or replace function public.produccion_editar_lote(
  p_id uuid, p_elaborado date, p_vida_util int, p_cantidad numeric, p_producido_por text,
  p_merma numeric, p_motivo text, p_obs text, p_unidad text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_ing text; v_base text; v_f numeric; v_cant numeric; v_merma numeric; v_actual text; v_mov jsonb;
begin
  if public.rol_actual() is null then raise exception 'Sin permiso'; end if;
  select unidad_ingreso into v_actual from public.produccion_lotes where id = p_id and estado = 'activo';
  if v_actual is null then raise exception 'Solo se pueden modificar lotes activos'; end if;
  v_ing := coalesce(p_unidad, v_actual);
  if v_ing not in ('kg', 'gr', 'unidad') then raise exception 'Unidad invalida'; end if;
  v_base := case when v_ing = 'unidad' then 'unidad' else 'kg' end;
  v_f := case when v_ing = 'gr' then 0.001 else 1 end;
  v_cant := p_cantidad * v_f; v_merma := coalesce(p_merma, 0) * v_f;
  if p_cantidad is null or p_cantidad <= 0 then raise exception 'La cantidad elaborada tiene que ser mayor a 0'; end if;
  if p_vida_util is null or p_vida_util <= 0 then raise exception 'La vida util tiene que ser de 1 dia o mas'; end if;
  if v_merma < 0 or v_merma > v_cant then raise exception 'La merma no puede ser negativa ni mayor a lo elaborado'; end if;
  update public.produccion_lotes set elaborado_el = p_elaborado, vida_util_dias = p_vida_util, vence_el = p_elaborado + p_vida_util,
    cantidad_producida = v_cant, unidad = v_base, unidad_ingreso = v_ing, producido_por = nullif(trim(coalesce(p_producido_por, '')), ''),
    cantidad_merma = v_merma, motivo_merma = nullif(trim(coalesce(p_motivo, '')), ''), observaciones = nullif(trim(coalesce(p_obs, '')), '')
    where id = p_id and estado = 'activo';
  v_mov := public._prod_aplicar_lote(p_id);
  return jsonb_build_object('ok', true, 'movimientos', coalesce(v_mov, '[]'::jsonb));
end;
$$;
grant execute on function public.produccion_editar_lote(uuid, date, int, numeric, text, numeric, text, text, text) to authenticated;

create or replace function public.produccion_cerrar_lote(p_id uuid, p_merma numeric default null, p_motivo text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  l record; v_item record; v_merma numeric; v_motivo text; v_precio numeric; v_um text; v_valor numeric := 0; v_desp uuid; v_mov jsonb;
begin
  if public.rol_actual() is null then raise exception 'Sin permiso'; end if;
  select * into l from public.produccion_lotes where id = p_id and estado = 'activo' for update;
  if not found then raise exception 'El lote no existe o ya esta terminado'; end if;
  v_merma := case when p_merma is null then coalesce(l.cantidad_merma, 0) else p_merma * (case when l.unidad_ingreso = 'gr' then 0.001 else 1 end) end;
  v_motivo := coalesce(nullif(trim(coalesce(p_motivo, '')), ''), l.motivo_merma);
  if v_merma < 0 or v_merma > l.cantidad_producida + 0.0005 then raise exception 'La merma no puede ser negativa ni mayor a lo elaborado'; end if;
  select * into v_item from public.produccion_items where id = l.item_id;

  -- la merma queda en Desperdicios (se valoriza con el precio del producto cuando la unidad coincide)
  if v_merma > 0 and v_item.insumo_id is not null then
    select precio_costo_kg, unidad_medida into v_precio, v_um from public.insumos where id = v_item.insumo_id;
    if (l.unidad = 'kg' and v_um = 'kg') or (l.unidad = 'unidad' and v_um = 'unidad') then
      v_valor := round(v_merma * coalesce(v_precio, 0), 2);
      insert into public.desperdicio (fecha, insumo_id, motivo, cantidad, valor_calculado, usuario_id)
        values (public.hoy_ar(), v_item.insumo_id, 'Merma de produccion: ' || v_item.nombre || coalesce(' - ' || v_motivo, ''), v_merma, v_valor, auth.uid())
        returning id into v_desp;
    end if;
  end if;

  update public.produccion_lotes set estado = 'cerrado', cantidad_merma = v_merma, motivo_merma = v_motivo,
    cerrado_el = now(), cerrado_por = auth.uid(), desperdicio_id = v_desp
    where id = p_id;
  v_mov := public._prod_aplicar_lote(p_id);

  return jsonb_build_object('ok', true, 'merma_pct', round(v_merma / l.cantidad_producida * 100, 1),
    'valor_merma', case when public.rol_actual() in ('admin', 'encargado') then v_valor end, 'movimientos', coalesce(v_mov, '[]'::jsonb));
end;
$$;
grant execute on function public.produccion_cerrar_lote(uuid, numeric, text) to authenticated;

create or replace function public.produccion_reabrir_lote(p_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_desp uuid;
begin
  if public.rol_actual() <> 'admin' then raise exception 'Sin permiso'; end if;
  select desperdicio_id into v_desp from public.produccion_lotes where id = p_id and estado = 'cerrado';
  if not found then raise exception 'El lote no esta terminado'; end if;
  update public.produccion_lotes set estado = 'activo', cerrado_el = null, cerrado_por = null, desperdicio_id = null where id = p_id;
  if v_desp is not null then delete from public.desperdicio where id = v_desp; end if;
  perform public._prod_aplicar_lote(p_id);
  return jsonb_build_object('ok', true);
end;
$$;
grant execute on function public.produccion_reabrir_lote(uuid) to authenticated;

-- ============================================================ comparativo: elaborado, vendido y merma
create or replace function public.produccion_control(p_desde date, p_hasta date)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if public.rol_actual() not in ('admin', 'encargado') then raise exception 'Sin permiso'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('producto', x.nombre, 'unidad', x.unidad, 'elaborado', round(x.elab, 3), 'vendido', round(x.vend, 3),
             'merma', round(x.merma, 3), 'diferencia', round(x.elab - x.vend - x.merma, 3), 'stock', x.stock) order by x.nombre)
      from (
        select pi.nombre, coalesce(s.unidad, i.unidad_medida) as unidad, s.cantidad_actual as stock,
               coalesce((select sum(l.cantidad_producida) from public.produccion_lotes l where l.item_id = pi.id and l.aplicar_stock and l.elaborado_el between p_desde and p_hasta), 0) as elab,
               coalesce((select sum(l.cantidad_merma) from public.produccion_lotes l where l.item_id = pi.id and l.aplicar_stock and l.elaborado_el between p_desde and p_hasta), 0) as merma,
               coalesce((select sum(c.cantidad) from public.pos_consumo c where c.insumo_id = pi.insumo_id and c.dia between p_desde and p_hasta), 0) as vend
          from public.produccion_items pi join public.insumos i on i.id = pi.insumo_id left join public.stock s on s.insumo_id = pi.insumo_id
         where pi.insumo_id is not null
      ) x
     where x.elab > 0 or x.vend > 0 or x.merma > 0
  ), '[]'::jsonb);
end;
$$;
grant execute on function public.produccion_control(date, date) to authenticated;

-- ============================================================ vincular productos de produccion con su receta y su stock
create or replace function pg_temp._ins(p_pats text[]) returns uuid
language plpgsql as $$
declare p text; v uuid;
begin
  foreach p in array p_pats loop
    select i.id into v from public.insumos i left join public.stock st on st.insumo_id = i.id
     where public.normalizar_texto(trim(coalesce(i.marca || ' ', '') || i.nombre)) like p
     order by (st.insumo_id is not null) desc, length(i.nombre), i.id limit 1;
    if v is not null then return v; end if;
  end loop;
  return null;
end
$$;

drop table if exists _res80;
create temp table _res80 (orden serial, seccion text, producto text, detalle text);

-- manteca noisette: 1 kg de manteca tonadita (el precio sigue al de la manteca)
do $$
declare v_ins uuid; v_ton uuid; v_rec uuid; v_cat text;
begin
  v_ins := pg_temp._ins(array['GATA MAULA MANTECA NOISETTE', '%MANTECA NOISETTE%']);
  v_ton := pg_temp._ins(array['%MANTECA TONADITA%']);
  if v_ins is null or v_ton is null then
    insert into _res80 (seccion, producto, detalle) values ('MANTECA NOISETTE', 'manteca noisette', 'NO ENCONTRE la manteca noisette o la tonadita: no se creo la receta');
  else
    select id into v_rec from public.recetas where tipo = 'preparacion' and insumo_id = v_ins limit 1;
    if v_rec is null then
      select categoria_carta into v_cat from public.recetas where tipo = 'preparacion' order by created_at limit 1;
      insert into public.recetas (nombre_producto, categoria_carta, tipo, insumo_id, merma_pct, margen_objetivo)
        values ('MANTECA NOISETTE', coalesce(v_cat, 'PREPARACIONES'), 'preparacion', v_ins, 0, 65) returning id into v_rec;
      insert into public.receta_insumos (receta_id, insumo_id, cantidad, tipo_medida) values (v_rec, v_ton, 1000, 'gramos');
      update public.insumos set es_preparacion = true, unidad_medida = 'kg' where id = v_ins;
      insert into _res80 (seccion, producto, detalle) values ('MANTECA NOISETTE', 'manteca noisette', 'CREADA la receta: 1 kg de manteca tonadita (el precio sigue al de la tonadita)');
    else
      insert into _res80 (seccion, producto, detalle) values ('MANTECA NOISETTE', 'manteca noisette', 'ya tenia receta');
    end if;
  end if;
end
$$;

-- gruyerito: precio informado
update public.insumos set precio_costo_kg = 17070, fecha_ultima_actualizacion = now()
 where public.normalizar_texto(trim(coalesce(marca || ' ', '') || nombre)) = 'GRUYERITO LACTOS PREMIUM' and coalesce(precio_costo_kg, 0) = 0;

-- productos de produccion con producto del stock y receta
do $$
declare r record; v_ins uuid; v_rec uuid; n_uni int := 0;
begin
  -- los que tienen producto vinculado: la receta es la de produccion de ese producto
  update public.produccion_items pi set receta_id = rc.id
    from (select distinct on (insumo_id) id, insumo_id from public.recetas where insumo_id is not null order by insumo_id, tipo desc, created_at) rc
   where rc.insumo_id = pi.insumo_id and pi.receta_id is null;
  -- platos armados y los que faltaban vincular
  for r in select * from (values
      ('Antipasti',               'ANTIPASTI',          'plato',       'ANTIPASTI'),
      ('Exquisita',               'EXQUISITA',          'plato',       'LA EXQUISITA'),
      ('Picada vermutera',        'PICADA VERMUTERA',   'plato',       'PICADA VERMUTERA'),
      ('Platito ahumado',         'PLATO AHUMADO',      'plato',       'PLATO AHUMADO'),
      ('Cono fiambres y quesos',  'CONO FYQ',           'plato',       'CONO DE FIAMBRES Y QUESOS'),
      ('Uvas con azúcar',         'UVAS CON AZUCAR',    'preparacion', 'UVAS%'),
      ('Manteca Noisette',        'GATA MAULA MANTECA NOISETTE', 'preparacion', 'MANTECA NOISETTE')
    ) as t(item, stock_label, tipo, receta_pat)
  loop
    select id into v_ins from public.insumos where public.normalizar_texto(trim(coalesce(marca || ' ', '') || nombre)) = r.stock_label limit 1;
    select id into v_rec from public.recetas where tipo = r.tipo and public.normalizar_texto(nombre_producto) like public.normalizar_texto(r.receta_pat) order by created_at limit 1;
    if v_ins is null or v_rec is null then
      insert into _res80 (seccion, producto, detalle) values ('PRODUCCION', r.item, 'NO ENCONTRE ' || case when v_ins is null then 'el producto del stock' else 'la receta' end || ': no se vinculo');
    else
      update public.produccion_items set insumo_id = v_ins, receta_id = v_rec
       where public.normalizar_texto(nombre) = public.normalizar_texto(r.item);
      get diagnostics n_uni = row_count;
      insert into _res80 (seccion, producto, detalle) values ('PRODUCCION', r.item, case when n_uni > 0 then 'VINCULADO con su stock y su receta' else 'el producto de produccion no existe' end);
    end if;
  end loop;
end
$$;

-- ============================================================ Postberry: platos armados = 1 unidad por venta; dips y La Cabrita por receta
do $$
declare r record; v_ins uuid; v_prod text;
begin
  for r in select * from (values
      ('PICADA VERMUTERA', 'PICADA VERMUTERA'), ('ANTIPASTI', 'ANTIPASTI'), ('PLATO AHUMADO', 'PLATO AHUMADO'),
      ('LA EXQUISITA', 'EXQUISITA'), ('CONO DE FIAMBRES Y QUESOS', 'CONO FYQ')
    ) as t(producto, stock_label)
  loop
    select l.producto into v_prod from (select distinct producto from public.pos_lineas) l
     where regexp_replace(public.normalizar_texto(l.producto), '\s+', ' ', 'g') = r.producto limit 1;
    select i.id into v_ins from public.insumos i join public.stock s on s.insumo_id = i.id
     where public.normalizar_texto(trim(coalesce(i.marca || ' ', '') || i.nombre)) = r.stock_label limit 1;
    if v_prod is null or v_ins is null then
      insert into _res80 (seccion, producto, detalle) values ('VENTA', r.producto, 'NO SE VINCULO: ' || case when v_prod is null then 'no tiene ventas cargadas' else 'no esta el plato armado en el stock' end);
    else
      delete from public.pos_receta where producto = v_prod;
      delete from public.pos_vinculo where producto = v_prod;
      insert into public.pos_vinculo (producto, insumo_id, modo, valor, lleva_soda) values (v_prod, v_ins, 'unidad', 1, false);
      delete from public.pos_producto where producto = v_prod and omitir is not null;
      insert into _res80 (seccion, producto, detalle) values ('VENTA', v_prod, 'resta 1 unidad del plato armado del stock');
    end if;
  end loop;
  update public.pos_receta set modo = 'venta' where producto in (select producto from public.pos_receta where modo = 'lote');
  insert into _res80 (seccion, producto, detalle) values ('VENTA', 'DIP MEDITERRANEO, DIP DE CAMEMBERT y LA CABRITA', 'se descuentan por receta al venderse');
end
$$;

select public._recalcular_costo_recetas(null) as recetas_recalculadas;
do $$
declare a timestamp; b timestamp;
begin
  select min(fecha), max(fecha) into a, b from public.pos_lineas;
  if a is not null then perform public._pos_aplicar(a, b); end if;
end
$$;

-- ============================================================ resultado
select x.seccion, x.producto, x.detalle
  from (
    select orden, seccion, producto, detalle from _res80
    union all
    select 1000 + row_number() over (order by pi.nombre), 'PRODUCCION: COMO QUEDO', pi.nombre,
           coalesce('stock: ' || trim(coalesce(i.marca || ' ', '') || i.nombre), 'sin producto en el stock') || ' · ' || coalesce('receta: ' || r.nombre_producto, 'sin receta')
      from public.produccion_items pi left join public.insumos i on i.id = pi.insumo_id left join public.recetas r on r.id = pi.receta_id
     where pi.activo
  ) x
 order by x.orden;
