-- Gata Maula: que cocina pueda VER las recetas (ingredientes, cantidades y preparacion) sin ver costos ni precios.
-- La funcion devuelve solo lo que cocina necesita; las tablas de recetas siguen cerradas para cocina.
-- Correr UNA vez en el SQL Editor.

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
      'ingredientes', coalesce((
        select jsonb_agg(jsonb_build_object(
          'nombre', i.nombre, 'marca', i.marca, 'cantidad', ri.cantidad, 'medida', ri.tipo_medida
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
