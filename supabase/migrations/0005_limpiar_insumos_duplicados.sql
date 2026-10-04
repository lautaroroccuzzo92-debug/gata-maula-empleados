-- Gata Maula: fusiona insumos duplicados (mismo nombre y subcategoria) que
-- quedaron por correr el import de datos varias veces.
-- De cada grupo de duplicados se conserva UNO: el que tiene la carga de stock
-- mas reciente (asi no se pierde un conteo hecho a mano). Todo lo que apuntaba
-- a los duplicados (movimientos, desperdicio, recetas, egresos) pasa al que se
-- conserva. NO se suman cantidades de stock (son copias, no stock distinto).
-- Correr ESTE archivo primero y despues el 0002_import_datos.sql.
-- Va todo en un solo bloque DO porque el editor de Supabase ejecuta cada
-- instruccion por separado y una tabla temporal no sobreviviria entre ellas.

do $$
begin
  create temp table _dup_map on commit drop as
  with ranked as (
    select i.id,
           lower(i.nombre) as nombre_lower,
           i.subcategoria,
           row_number() over (
             partition by lower(i.nombre), i.subcategoria
             order by coalesce(s.ultima_actualizacion, i.fecha_ultima_actualizacion) desc, i.id
           ) as rn
    from public.insumos i
    left join public.stock s on s.insumo_id = i.id
  )
  select dup.id as dup_id, keeper.id as keep_id
  from ranked dup
  join ranked keeper
    on keeper.nombre_lower = dup.nombre_lower
   and keeper.subcategoria = dup.subcategoria
   and keeper.rn = 1
  where dup.rn > 1;

  update public.movimientos_stock m set insumo_id = d.keep_id from _dup_map d where m.insumo_id = d.dup_id;
  update public.desperdicio x set insumo_id = d.keep_id from _dup_map d where x.insumo_id = d.dup_id;
  update public.receta_insumos x set insumo_id = d.keep_id from _dup_map d where x.insumo_id = d.dup_id;
  update public.ingresos_egresos x set insumo_relacionado_id = d.keep_id from _dup_map d where x.insumo_relacionado_id = d.dup_id;

  delete from public.stock where insumo_id in (select dup_id from _dup_map);
  delete from public.insumos where id in (select dup_id from _dup_map);
end
$$;
