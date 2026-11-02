-- Gata Maula: lista de cada producto del stock con cantidad, precio y valor (para comparar con tu planilla PPTO, hoja TOTAL DE MERCADERIA).
-- Correr en el SQL Editor y exportar el resultado a CSV (boton Export). No modifica nada.
-- valor_hoy_app  = como lo calcula la app hoy (todo x1,21)
-- valor_planilla = con la regla de tu planilla (x1,21 solo en vermut, fiambres y quesos)
select i.subcategoria::text as rubro,
       trim(coalesce(i.marca || ' ', '') || i.nombre) as producto,
       s.cantidad_actual as hay,
       i.unidad_medida as unidad,
       i.precio_costo_kg as precio_sin_iva,
       round(greatest(s.cantidad_actual, 0) * coalesce(i.precio_costo_kg, 0) * 1.21) as valor_hoy_app,
       round(greatest(s.cantidad_actual, 0) * coalesce(i.precio_costo_kg, 0) * case when i.subcategoria::text in ('vermut', 'fiambres', 'quesos') then 1.21 else 1.0 end) as valor_planilla,
       i.fecha_ultima_actualizacion::date as precio_actualizado
  from public.stock s join public.insumos i on i.id = s.insumo_id
 where i.subcategoria::text not in ('limpieza', 'descartables')
 order by 1, 2;
