-- Gata Maula: los platos armados se cargan en UNIDADES en Produccion (antes figuraban en kilos).
--   Picada vermutera, antipasti, La Exquisita y plato ahumado: 1 lote = N unidades armadas.
--   (El cono de fiambres y quesos ya estaba en unidades.)
-- Seguro de correr mas de una vez.

update public.produccion_items set unidad = 'unidad'
 where public.normalizar_texto(nombre) in ('ANTIPASTI', 'EXQUISITA', 'PICADA VERMUTERA', 'PLATITO AHUMADO', 'CONO FIAMBRES Y QUESOS')
   and unidad is distinct from 'unidad';

-- los lotes ya cargados de esos productos (si hubiera) quedan como estaban: no tocaron el stock

select pi.nombre as producto, pi.unidad as se_carga_en, trim(coalesce(i.marca || ' ', '') || i.nombre) as stock, s.unidad as stock_en
  from public.produccion_items pi
  left join public.insumos i on i.id = pi.insumo_id
  left join public.stock s on s.insumo_id = pi.insumo_id
 where public.normalizar_texto(pi.nombre) in ('ANTIPASTI', 'EXQUISITA', 'PICADA VERMUTERA', 'PLATITO AHUMADO', 'CONO FIAMBRES Y QUESOS')
 order by pi.nombre;
