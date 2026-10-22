-- Gata Maula: en Produccion, la cantidad de cada lote se carga en Kg, Gr o Unidades (se elige al cargar el lote).
--   * los gramos se guardan convertidos a kilos (unidad base 'kg'); las unidades quedan en 'unidad'
--   * unidad_ingreso recuerda como se cargo (kg, gr o unidad) para mostrar y corregir el lote en esa unidad
--   * el reporte de merma separa kilos y unidades de un mismo producto
-- Correr UNA vez en el SQL Editor (despues de 0027).

alter table public.produccion_lotes add column if not exists unidad text;
alter table public.produccion_lotes add column if not exists unidad_ingreso text;
update public.produccion_lotes l set unidad = i.unidad, unidad_ingreso = i.unidad
  from public.produccion_items i where i.id = l.item_id and (l.unidad is null or l.unidad_ingreso is null);
alter table public.produccion_lotes alter column unidad set default 'kg';
alter table public.produccion_lotes alter column unidad set not null;
alter table public.produccion_lotes alter column unidad_ingreso set default 'kg';
alter table public.produccion_lotes alter column unidad_ingreso set not null;
alter table public.produccion_lotes drop constraint if exists produccion_lotes_unidad_check;
alter table public.produccion_lotes add constraint produccion_lotes_unidad_check check (unidad in ('kg', 'unidad') and unidad_ingreso in ('kg', 'gr', 'unidad'));

drop function if exists public.produccion_crear_lote(uuid, date, int, numeric, text, numeric, text, text);
drop function if exists public.produccion_editar_lote(uuid, date, int, numeric, text, numeric, text, text);

create or replace function public.produccion_crear_lote(
  p_item_id uuid, p_elaborado date, p_vida_util int, p_cantidad numeric, p_producido_por text,
  p_merma numeric default 0, p_motivo text default null, p_obs text default null, p_unidad text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_elab date := coalesce(p_elaborado, public.hoy_ar()); v_id uuid; v_item_unidad text;
  v_ing text; v_base text; v_f numeric; v_cant numeric; v_merma numeric;
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
  insert into public.produccion_lotes (item_id, elaborado_el, vida_util_dias, vence_el, cantidad_producida, unidad, unidad_ingreso, producido_por, cantidad_merma, motivo_merma, observaciones, creado_por)
    values (p_item_id, v_elab, p_vida_util, v_elab + p_vida_util, v_cant, v_base, v_ing, nullif(trim(coalesce(p_producido_por, '')), ''),
            v_merma, nullif(trim(coalesce(p_motivo, '')), ''), nullif(trim(coalesce(p_obs, '')), ''), auth.uid())
    returning id into v_id;
  return jsonb_build_object('id', v_id);
end;
$$;
grant execute on function public.produccion_crear_lote(uuid, date, int, numeric, text, numeric, text, text, text) to authenticated;

create or replace function public.produccion_editar_lote(
  p_id uuid, p_elaborado date, p_vida_util int, p_cantidad numeric, p_producido_por text,
  p_merma numeric, p_motivo text, p_obs text, p_unidad text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_ing text; v_base text; v_f numeric; v_cant numeric; v_merma numeric; v_actual text;
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
  return jsonb_build_object('ok', true);
end;
$$;
grant execute on function public.produccion_editar_lote(uuid, date, int, numeric, text, numeric, text, text, text) to authenticated;

-- Terminar un lote: la merma se escribe en la misma unidad en la que se cargo el lote
create or replace function public.produccion_cerrar_lote(p_id uuid, p_merma numeric default null, p_motivo text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  l record; v_item record; v_merma numeric; v_motivo text; v_precio numeric; v_valor numeric := 0; v_desp uuid;
begin
  if public.rol_actual() is null then raise exception 'Sin permiso'; end if;
  select * into l from public.produccion_lotes where id = p_id and estado = 'activo' for update;
  if not found then raise exception 'El lote no existe o ya esta terminado'; end if;
  v_merma := case when p_merma is null then coalesce(l.cantidad_merma, 0) else p_merma * (case when l.unidad_ingreso = 'gr' then 0.001 else 1 end) end;
  v_motivo := coalesce(nullif(trim(coalesce(p_motivo, '')), ''), l.motivo_merma);
  if v_merma < 0 or v_merma > l.cantidad_producida + 0.0005 then raise exception 'La merma no puede ser negativa ni mayor a lo elaborado'; end if;
  select * into v_item from public.produccion_items where id = l.item_id;

  if v_merma > 0 and v_item.insumo_id is not null and l.unidad = 'kg' then
    select precio_costo_kg into v_precio from public.insumos where id = v_item.insumo_id;
    v_valor := round(v_merma * coalesce(v_precio, 0), 2);
    insert into public.desperdicio (fecha, insumo_id, motivo, cantidad, valor_calculado, usuario_id)
      values (public.hoy_ar(), v_item.insumo_id, 'Merma de produccion: ' || v_item.nombre || coalesce(' - ' || v_motivo, ''), v_merma, v_valor, auth.uid())
      returning id into v_desp;
  end if;

  update public.produccion_lotes set estado = 'cerrado', cantidad_merma = v_merma, motivo_merma = v_motivo,
    cerrado_el = now(), cerrado_por = auth.uid(), desperdicio_id = v_desp
    where id = p_id;

  return jsonb_build_object('ok', true, 'merma_pct', round(v_merma / l.cantidad_producida * 100, 1),
    'valor_merma', case when public.rol_actual() in ('admin', 'encargado') then v_valor end);
end;
$$;
grant execute on function public.produccion_cerrar_lote(uuid, numeric, text) to authenticated;

-- Reporte: kilos y unidades de un mismo producto van en renglones separados
create or replace function public.produccion_reporte(p_desde date, p_hasta date)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_ve boolean := public.rol_actual() in ('admin', 'encargado');
begin
  if public.rol_actual() is null then raise exception 'Sin permiso'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'producto', x.nombre, 'unidad', x.unidad, 'lotes', x.lotes, 'producido', x.producido, 'usado', x.producido - x.merma, 'merma', x.merma,
      'merma_pct', case when x.producido > 0 then round(x.merma / x.producido * 100, 1) end,
      'valor_merma', case when v_ve then x.valor end
    ) order by x.merma desc nulls last, x.nombre)
    from (
      select i.nombre, l.unidad, count(*) as lotes, sum(l.cantidad_producida) as producido, sum(l.cantidad_merma) as merma,
             sum(coalesce((select valor_calculado from public.desperdicio d where d.id = l.desperdicio_id), 0)) as valor
        from public.produccion_lotes l join public.produccion_items i on i.id = l.item_id
       where l.estado = 'cerrado' and l.elaborado_el between p_desde and p_hasta
       group by i.nombre, l.unidad
    ) x
  ), '[]'::jsonb);
end;
$$;
grant execute on function public.produccion_reporte(date, date) to authenticated;
