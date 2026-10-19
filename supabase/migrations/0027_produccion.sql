-- Gata Maula: ficha de produccion y vencimientos (de tu planilla "PLANILLA PRODUCCION Y VENCIMIENTOS").
--   * produccion_items: catalogo de lo que se elabora (33 productos) con su vida util en dias y, si corresponde,
--     la preparacion de Recetas con la que se valoriza la merma
--   * produccion_lotes: cada elaboracion (fecha, cantidad, quien, vencimiento) y, al cerrarla, cuanto se uso y cuanto se descarto
--   * al cerrar un lote con merma de un producto vinculado, la merma se suma a Desperdicios (estado de resultados)
-- Correr UNA vez en el SQL Editor.

create or replace function public.hoy_ar()
returns date language sql stable as $$ select (now() at time zone 'America/Argentina/Buenos_Aires')::date $$;
grant execute on function public.hoy_ar() to authenticated;

create table if not exists public.produccion_items (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  vida_util_dias int not null check (vida_util_dias > 0),
  unidad text not null default 'kg' check (unidad in ('kg', 'unidad')),
  notas text,
  insumo_id uuid references public.insumos(id) on delete set null,
  activo boolean not null default true,
  created_at timestamptz not null default now()
);
create unique index if not exists produccion_items_nombre_idx on public.produccion_items (lower(nombre));

create table if not exists public.produccion_lotes (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.produccion_items(id),
  elaborado_el date not null,
  vence_el date not null,
  cantidad_producida numeric(12,3) not null check (cantidad_producida > 0),
  producido_por text,
  estado text not null default 'activo' check (estado in ('activo', 'cerrado')),
  cantidad_usada numeric(12,3),
  cantidad_merma numeric(12,3),
  motivo_merma text,
  cerrado_el timestamptz,
  cerrado_por uuid references public.usuarios(id) on delete set null,
  observaciones text,
  desperdicio_id uuid references public.desperdicio(id) on delete set null,
  creado_por uuid references public.usuarios(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists produccion_lotes_estado_idx on public.produccion_lotes (estado, vence_el);

alter table public.produccion_items enable row level security;
alter table public.produccion_lotes enable row level security;
drop policy if exists produccion_items_select on public.produccion_items;
create policy produccion_items_select on public.produccion_items for select using (public.rol_actual() is not null);
drop policy if exists produccion_lotes_select on public.produccion_lotes;
create policy produccion_lotes_select on public.produccion_lotes for select using (public.rol_actual() is not null);

-- ---------------------------------------------------------------- catalogo (admin y encargado)
create or replace function public.produccion_guardar_item(
  p_id uuid, p_nombre text, p_vida_util int, p_unidad text, p_notas text, p_insumo_id uuid, p_activo boolean default true
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id uuid := p_id;
begin
  if public.rol_actual() not in ('admin', 'encargado') then raise exception 'Sin permiso'; end if;
  if trim(coalesce(p_nombre, '')) = '' then raise exception 'Falta el nombre'; end if;
  if p_vida_util is null or p_vida_util <= 0 then raise exception 'La vida util tiene que ser de 1 dia o mas'; end if;
  if p_unidad not in ('kg', 'unidad') then raise exception 'Unidad invalida'; end if;
  if v_id is null then
    insert into public.produccion_items (nombre, vida_util_dias, unidad, notas, insumo_id, activo)
      values (trim(p_nombre), p_vida_util, p_unidad, nullif(trim(coalesce(p_notas, '')), ''), p_insumo_id, coalesce(p_activo, true))
      returning id into v_id;
  else
    update public.produccion_items set nombre = trim(p_nombre), vida_util_dias = p_vida_util, unidad = p_unidad,
      notas = nullif(trim(coalesce(p_notas, '')), ''), insumo_id = p_insumo_id, activo = coalesce(p_activo, true)
      where id = v_id;
    if not found then raise exception 'Producto no encontrado'; end if;
  end if;
  return jsonb_build_object('id', v_id);
end;
$$;
grant execute on function public.produccion_guardar_item(uuid, text, int, text, text, uuid, boolean) to authenticated;

-- ---------------------------------------------------------------- lotes (todos los roles)
create or replace function public.produccion_crear_lote(
  p_item_id uuid, p_elaborado date, p_cantidad numeric, p_producido_por text, p_vence date default null, p_obs text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_vida int; v_id uuid;
begin
  if public.rol_actual() is null then raise exception 'Sin permiso'; end if;
  if p_cantidad is null or p_cantidad <= 0 then raise exception 'La cantidad tiene que ser mayor a 0'; end if;
  select vida_util_dias into v_vida from public.produccion_items where id = p_item_id and activo;
  if v_vida is null then raise exception 'Producto no encontrado'; end if;
  insert into public.produccion_lotes (item_id, elaborado_el, vence_el, cantidad_producida, producido_por, observaciones, creado_por)
    values (p_item_id, coalesce(p_elaborado, public.hoy_ar()), coalesce(p_vence, coalesce(p_elaborado, public.hoy_ar()) + v_vida), p_cantidad,
            nullif(trim(coalesce(p_producido_por, '')), ''), nullif(trim(coalesce(p_obs, '')), ''), auth.uid())
    returning id into v_id;
  return jsonb_build_object('id', v_id);
end;
$$;
grant execute on function public.produccion_crear_lote(uuid, date, numeric, text, date, text) to authenticated;

create or replace function public.produccion_editar_lote(
  p_id uuid, p_elaborado date, p_vence date, p_cantidad numeric, p_producido_por text, p_obs text
) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if public.rol_actual() is null then raise exception 'Sin permiso'; end if;
  if p_cantidad is null or p_cantidad <= 0 then raise exception 'La cantidad tiene que ser mayor a 0'; end if;
  if p_vence < p_elaborado then raise exception 'El vencimiento no puede ser anterior a la elaboracion'; end if;
  update public.produccion_lotes set elaborado_el = p_elaborado, vence_el = p_vence, cantidad_producida = p_cantidad,
    producido_por = nullif(trim(coalesce(p_producido_por, '')), ''), observaciones = nullif(trim(coalesce(p_obs, '')), '')
    where id = p_id and estado = 'activo';
  if not found then raise exception 'Solo se pueden modificar lotes activos'; end if;
  return jsonb_build_object('ok', true);
end;
$$;
grant execute on function public.produccion_editar_lote(uuid, date, date, numeric, text, text) to authenticated;

create or replace function public.produccion_cerrar_lote(p_id uuid, p_usada numeric, p_merma numeric, p_motivo text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  l record; v_item record; v_precio numeric; v_valor numeric := 0; v_desp uuid;
begin
  if public.rol_actual() is null then raise exception 'Sin permiso'; end if;
  if coalesce(p_usada, 0) < 0 or coalesce(p_merma, 0) < 0 then raise exception 'Las cantidades no pueden ser negativas'; end if;
  select * into l from public.produccion_lotes where id = p_id and estado = 'activo' for update;
  if not found then raise exception 'El lote no existe o ya esta cerrado'; end if;
  select * into v_item from public.produccion_items where id = l.item_id;

  if coalesce(p_merma, 0) > 0 and v_item.insumo_id is not null and v_item.unidad = 'kg' then
    select precio_costo_kg into v_precio from public.insumos where id = v_item.insumo_id;
    v_valor := round(p_merma * coalesce(v_precio, 0), 2);
    insert into public.desperdicio (fecha, insumo_id, motivo, cantidad, valor_calculado, usuario_id)
      values (public.hoy_ar(), v_item.insumo_id, 'Merma de produccion: ' || v_item.nombre || coalesce(' - ' || nullif(trim(p_motivo), ''), ''), p_merma, v_valor, auth.uid())
      returning id into v_desp;
  end if;

  update public.produccion_lotes set estado = 'cerrado', cantidad_usada = coalesce(p_usada, 0), cantidad_merma = coalesce(p_merma, 0),
    motivo_merma = nullif(trim(coalesce(p_motivo, '')), ''), cerrado_el = now(), cerrado_por = auth.uid(), desperdicio_id = v_desp
    where id = p_id;

  return jsonb_build_object('ok', true, 'merma_pct', round(coalesce(p_merma, 0) / l.cantidad_producida * 100, 1),
    'valor_merma', case when public.rol_actual() in ('admin', 'encargado') then v_valor end);
end;
$$;
grant execute on function public.produccion_cerrar_lote(uuid, numeric, numeric, text) to authenticated;

create or replace function public.produccion_reabrir_lote(p_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_desp uuid;
begin
  if public.rol_actual() <> 'admin' then raise exception 'Sin permiso'; end if;
  select desperdicio_id into v_desp from public.produccion_lotes where id = p_id and estado = 'cerrado';
  if not found then raise exception 'El lote no esta cerrado'; end if;
  update public.produccion_lotes set estado = 'activo', cantidad_usada = null, cantidad_merma = null, motivo_merma = null,
    cerrado_el = null, cerrado_por = null, desperdicio_id = null where id = p_id;
  if v_desp is not null then delete from public.desperdicio where id = v_desp; end if;
  return jsonb_build_object('ok', true);
end;
$$;
grant execute on function public.produccion_reabrir_lote(uuid) to authenticated;

-- ---------------------------------------------------------------- consultas
create or replace function public.produccion_estado()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if public.rol_actual() is null then raise exception 'Sin permiso'; end if;
  return (select jsonb_build_object(
    'activos', count(*),
    'vencidos', count(*) filter (where vence_el < public.hoy_ar()),
    'por_vencer', count(*) filter (where vence_el >= public.hoy_ar() and vence_el <= public.hoy_ar() + 2)
  ) from public.produccion_lotes where estado = 'activo');
end;
$$;
grant execute on function public.produccion_estado() to authenticated;

create or replace function public.produccion_reporte(p_desde date, p_hasta date)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_ve boolean := public.rol_actual() in ('admin', 'encargado');
begin
  if public.rol_actual() is null then raise exception 'Sin permiso'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'producto', x.nombre, 'unidad', x.unidad, 'lotes', x.lotes, 'producido', x.producido, 'usado', x.usado, 'merma', x.merma,
      'merma_pct', case when x.producido > 0 then round(x.merma / x.producido * 100, 1) end,
      'valor_merma', case when v_ve then x.valor end
    ) order by x.merma desc nulls last, x.nombre)
    from (
      select i.nombre, i.unidad, count(*) as lotes, sum(l.cantidad_producida) as producido, sum(coalesce(l.cantidad_usada, 0)) as usado,
             sum(coalesce(l.cantidad_merma, 0)) as merma,
             sum(coalesce((select valor_calculado from public.desperdicio d where d.id = l.desperdicio_id), 0)) as valor
        from public.produccion_lotes l join public.produccion_items i on i.id = l.item_id
       where l.estado = 'cerrado' and l.elaborado_el between p_desde and p_hasta
       group by i.nombre, i.unidad
    ) x
  ), '[]'::jsonb);
end;
$$;
grant execute on function public.produccion_reporte(date, date) to authenticated;

-- ---------------------------------------------------------------- catalogo inicial (de tu planilla)
do $$
declare t record; k uuid;
begin
  for t in select * from (values
    ('Aceitunas condimentadas', 15, '15 días', 'aceitunas condimentadas'),
    ('Aderezo de verduras', 5, '5 días', 'ADEREZO VERDURAS ASADAS'),
    ('Antipasti', 5, '5 días', null),
    ('Castañas tostadas', 10, '10 días', 'CASTAÑA DE CAJU ASADAS'),
    ('Cebolla caramelizada', 10, '10 días', 'CEBOLLA CARAMELIZADAS'),
    ('Cherrys asados', 10, '10 días', 'TOMATES CHERRYS'),
    ('Chocolate blanco trozeado', 30, '30 días (tentativo)', null),
    ('Crema de palta', 7, '7 días', 'CREMA DE PALTA'),
    ('Dip mediterráneo', 10, '10 días', 'DIP MEDITERRANEO'),
    ('Escabeche de hongos', 10, '10 días', 'HONGOS EN ESCABECHE'),
    ('Escabeche de porotos', 10, '10 días', 'POROTOS AL ESCABECHE'),
    ('Exquisita', 5, '5 días', null),
    ('Falsa criolla', 3, '3 días', null),
    ('Huancaína', 2, '2 días', null),
    ('Lengua a la vinagreta', 10, '10 días', 'lengua a la vinagreta'),
    ('Manteca saborizada', 15, '15 días (tentativo)', null),
    ('Matambre asado', 5, '5 días', null),
    ('Mayo de chimi', 10, '10 días', 'LACTONESA DE CHIMICHURRI'),
    ('Mostaza', 90, '3 meses (90 dias)', 'MOSTAZA ANTIGUA'),
    ('Paté de hongos', 7, '7 días', 'RECETA PATE DE HONGOS'),
    ('Pepinillos', 10, '10 días', 'RECETA PEPINILLOS'),
    ('Pesto', 10, '10 días', 'PESTO'),
    ('Picada vermutera', 5, '5 días', null),
    ('Pimiento rojo asado', 10, '10 días', 'MORRONES ASADOS'),
    ('Platito ahumado', 5, '5 días', null),
    ('Reducción de vermut', 15, '15 días', 'REDUCCION DE VERMUT'),
    ('Relish', 10, '10 días', 'RELISH DE PEPINILLO'),
    ('Tapenade de aceitunas', 10, '10 días', 'TAPENADE DE ACEITUNAS NEGRAS'),
    ('Tomate rallado', 1, '1 día', 'TOMATE RALLADO'),
    ('Uvas con azúcar', 5, '5 días', null),
    ('Verduras asadas', 5, '5 días', 'VERDURAS ASADAS')
  ) as v(nombre, dias, nota, prep) loop
    k := null;
    if t.prep is not null then k := public._insumo_id('cocina', t.prep, 'Preparacion casera'); end if;
    insert into public.produccion_items (nombre, vida_util_dias, unidad, notas, insumo_id)
      values (t.nombre, t.dias, 'kg', t.nota, k)
      on conflict ((lower(nombre))) do nothing;
  end loop;
end
$$;
