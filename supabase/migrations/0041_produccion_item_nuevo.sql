-- Gata Maula: en Produccion, cualquiera (tambien cocina) puede agregar un producto nuevo al cargar un lote
-- (por ejemplo "Arroz"), sin tener que esperar a que lo sume el administrador.
--   * produccion_items.creado_por_cocina marca los que agrego cocina, para que el administrador los revise en el Catalogo
--   * si ya existe un producto con ese nombre, se usa ese (no se duplica)
-- Correr UNA vez en el SQL Editor (despues de 0035).

alter table public.produccion_items add column if not exists creado_por uuid references public.usuarios(id) on delete set null;
alter table public.produccion_items add column if not exists creado_por_cocina boolean not null default false;

create or replace function public.produccion_nuevo_item(p_nombre text, p_vida_util int, p_unidad text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_nombre text := trim(coalesce(p_nombre, ''));
begin
  if public.rol_actual() is null then raise exception 'Sin permiso'; end if;
  if v_nombre = '' then raise exception 'Falta el nombre del producto'; end if;
  if p_vida_util is null or p_vida_util <= 0 then raise exception 'La vida util tiene que ser de 1 dia o mas'; end if;
  if p_unidad not in ('kg', 'unidad') then raise exception 'Unidad invalida'; end if;
  select id into v_id from public.produccion_items where lower(nombre) = lower(v_nombre);
  if v_id is not null then
    update public.produccion_items set activo = true where id = v_id;
    return jsonb_build_object('id', v_id, 'existia', true);
  end if;
  insert into public.produccion_items (nombre, vida_util_dias, unidad, notas, creado_por, creado_por_cocina)
    values (v_nombre, p_vida_util, p_unidad, 'Agregado al cargar un lote', auth.uid(), public.rol_actual() = 'cocina')
    returning id into v_id;
  return jsonb_build_object('id', v_id, 'existia', false);
end;
$$;
grant execute on function public.produccion_nuevo_item(text, int, text) to authenticated;
