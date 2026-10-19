-- Gata Maula: cocina puede crear y modificar sus propias recetas, sin ver costos ni precios.
--   * recetas.creada_por_cocina marca las recetas hechas por cocina (admin/encargado las revisan y les cargan el precio de carta;
--     al guardarlas desde su editor pasan a ser oficiales y cocina deja de poder modificarlas)
--   * insumos_para_cocina(): lista de ingredientes disponibles (sin precios)
--   * guardar_receta_cocina(): crea/modifica una receta de cocina; el costo se calcula en el servidor
--   * recetas_para_cocina(): ahora tambien dice cuales puede editar cocina
-- Correr UNA vez en el SQL Editor.

alter table public.recetas add column if not exists creada_por_cocina boolean not null default false;
alter table public.recetas add column if not exists creada_por uuid references public.usuarios(id) on delete set null;

create or replace function public.insumos_para_cocina()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if public.rol_actual() is null then raise exception 'Sin permiso'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', id, 'nombre', nombre, 'marca', marca, 'categoria', subcategoria, 'preparacion', es_preparacion)
                     order by nombre, marca)
      from public.insumos
  ), '[]'::jsonb);
end;
$$;
grant execute on function public.insumos_para_cocina() to authenticated;

create or replace function public.recetas_para_cocina()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if public.rol_actual() is null then raise exception 'Sin permiso'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', r.id,
      'nombre', r.nombre_producto,
      'categoria', r.categoria_carta,
      'tipo', r.tipo,
      'preparacion', r.preparacion,
      'merma_pct', r.merma_pct,
      'creada_por_cocina', r.creada_por_cocina,
      'editable', (r.creada_por_cocina and r.tipo = 'plato'),
      'ingredientes', coalesce((
        select jsonb_agg(jsonb_build_object(
          'insumo_id', ri.insumo_id, 'nombre', i.nombre, 'marca', i.marca, 'cantidad', ri.cantidad, 'medida', ri.tipo_medida
        ) order by ri.cantidad desc)
        from public.receta_insumos ri join public.insumos i on i.id = ri.insumo_id
        where ri.receta_id = r.id
      ), '[]'::jsonb)
    ) order by r.categoria_carta, r.nombre_producto)
    from public.recetas r
  ), '[]'::jsonb);
end;
$$;
grant execute on function public.recetas_para_cocina() to authenticated;

create or replace function public.guardar_receta_cocina(
  p_receta_id uuid, p_nombre text, p_categoria text, p_preparacion text, p_ingredientes jsonb
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid := p_receta_id;
  v_nombre text := trim(coalesce(p_nombre, ''));
  v_ing jsonb;
  v_cant numeric;
  v_med text;
  v_cat text := trim(coalesce(p_categoria, ''));
begin
  if public.rol_actual() <> 'cocina' then raise exception 'Sin permiso'; end if;
  if v_nombre = '' then raise exception 'Falta el nombre de la receta'; end if;
  if v_cat not in ('Sandwiches', 'Picadas y platitos', 'Conservas', 'Conito de picada', 'Kutsi', 'Sandwiches de Focaccia entera', 'Fuera de carta') then
    raise exception 'Categoria invalida';
  end if;
  if p_ingredientes is null or jsonb_typeof(p_ingredientes) <> 'array' or jsonb_array_length(p_ingredientes) = 0 then
    raise exception 'La receta necesita al menos un ingrediente';
  end if;

  for v_ing in select * from jsonb_array_elements(p_ingredientes) loop
    v_cant := nullif(v_ing->>'cantidad', '')::numeric;
    v_med := coalesce(v_ing->>'medida', 'gramos');
    if v_cant is null or v_cant <= 0 then raise exception 'Cada ingrediente necesita una cantidad mayor a 0'; end if;
    if v_med not in ('gramos', 'unidad') then raise exception 'Medida invalida'; end if;
    if not exists (select 1 from public.insumos where id = (v_ing->>'insumo_id')::uuid) then raise exception 'Hay un ingrediente que no existe'; end if;
  end loop;

  if v_id is null then
    insert into public.recetas (nombre_producto, categoria_carta, preparacion, tipo, margen_objetivo, creada_por_cocina, creada_por)
      values (v_nombre, v_cat, nullif(trim(coalesce(p_preparacion, '')), ''), 'plato', 65, true, auth.uid())
      returning id into v_id;
  else
    if not exists (select 1 from public.recetas where id = v_id and creada_por_cocina and tipo = 'plato') then
      raise exception 'Solo se pueden modificar las recetas creadas por cocina';
    end if;
    update public.recetas set nombre_producto = v_nombre, categoria_carta = v_cat, preparacion = nullif(trim(coalesce(p_preparacion, '')), '')
      where id = v_id;
    delete from public.receta_insumos where receta_id = v_id;
  end if;

  insert into public.receta_insumos (receta_id, insumo_id, cantidad, tipo_medida)
  select v_id, (x->>'insumo_id')::uuid, (x->>'cantidad')::numeric, coalesce(x->>'medida', 'gramos')::tipo_medida_receta
    from jsonb_array_elements(p_ingredientes) x;

  update public.recetas set costo_total_calculado = round(coalesce((
      select sum(case when ri.tipo_medida = 'unidad' then ri.cantidad * i.precio_costo_kg else ri.cantidad / 1000 * i.precio_costo_kg end)
        from public.receta_insumos ri join public.insumos i on i.id = ri.insumo_id where ri.receta_id = v_id), 0), 2)
    where id = v_id;

  return jsonb_build_object('id', v_id);
end;
$$;
grant execute on function public.guardar_receta_cocina(uuid, text, text, text, jsonb) to authenticated;
