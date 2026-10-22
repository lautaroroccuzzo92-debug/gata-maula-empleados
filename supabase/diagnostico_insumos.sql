-- Gata Maula: lista de insumos de los rubros con repetidos / errores, para revisar juntos.
-- Correr en el SQL Editor y exportar el resultado a CSV (boton Export).
select i.subcategoria, coalesce(i.marca, '') as marca, i.nombre, i.precio_costo_kg as precio,
       s.cantidad_actual as stock, s.stock_minimo as minimo,
       (select count(*) from public.receta_insumos ri where ri.insumo_id = i.id) as recetas,
       i.id
  from public.insumos i
  left join public.stock s on s.insumo_id = i.id
 where i.subcategoria in ('cerveza y sin alcohol', 'vermut', 'fiambres', 'quesos', 'cocina', 'kutsi') and not i.es_preparacion
 order by i.subcategoria, i.nombre, i.marca;
