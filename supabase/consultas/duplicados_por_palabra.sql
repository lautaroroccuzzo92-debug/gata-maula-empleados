-- SOLO MIRA. Productos con estas palabras: los que usan las recetas (sin stock) al lado de los que se cuentan en el stock.
select trim(coalesce(i.marca || ' ', '') || i.nombre) as producto,
       case when s.insumo_id is not null then 'EN STOCK' else 'solo receta/costos' end as donde,
       i.precio_costo_kg as precio, s.cantidad_actual as stock,
       (select count(distinct ri.receta_id) from public.receta_insumos ri where ri.insumo_id = i.id) as en_recetas
  from public.insumos i left join public.stock s on s.insumo_id = i.id
 where public.normalizar_texto(trim(coalesce(i.marca || ' ', '') || i.nombre)) ~
       '(CHAMPI|HONGO|VINAGRE|GIRASOL|LECHE|MORRON|PIMIENTO|LAUREL|ACEITE DE OLIVA|OLIVA|PIMIENTA|ROMERO|AZUCAR|WRAP|CHERRY|VINO BLANCO|ACETO|JAMON COCIDO|COCIDO|MANTECA)'
   and (s.insumo_id is not null or exists (select 1 from public.receta_insumos ri where ri.insumo_id = i.id))
 order by 1;
