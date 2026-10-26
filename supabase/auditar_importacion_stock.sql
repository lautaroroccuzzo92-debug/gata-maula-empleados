-- Gata Maula: detalle de la ultima importacion de stock (para revisar cada renglon de tu planilla contra la app).
-- Correr en el SQL Editor y exportar el resultado a CSV (boton Export).
select hoja, nombre_hoja, hay as planilla, estado, insumo as insumo_en_la_app, antes, ahora, via
  from public.import_stock_log
 where corrida = (select max(corrida) from public.import_stock_log)
 order by hoja, nombre_hoja;
