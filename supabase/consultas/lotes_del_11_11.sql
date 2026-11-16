-- SOLO MIRA. Lotes de produccion de esos dias (cualquier estado), para ver si arroz y aderezo de verdura quedaron cargados.
select l.elaborado_el as elaborado, pi.nombre as producto, l.estado, l.cantidad_producida as cantidad, l.unidad_ingreso as unidad,
       l.cantidad_merma as merma, l.producido_por, u.nombre as cargado_por,
       (l.created_at at time zone 'America/Argentina/Buenos_Aires')::text as cargado_el,
       (l.cerrado_el at time zone 'America/Argentina/Buenos_Aires')::text as cerrado_el
  from public.produccion_lotes l
  join public.produccion_items pi on pi.id = l.item_id
  left join public.usuarios u on u.id = l.creado_por
 where l.elaborado_el between date '2026-11-08' and date '2026-11-13'
    or (l.created_at at time zone 'America/Argentina/Buenos_Aires')::date between date '2026-11-08' and date '2026-11-13'
 order by l.elaborado_el desc, pi.nombre;

-- y los lotes de esos dos productos, sin importar la fecha (ultimos 20)
select l.elaborado_el as elaborado, pi.nombre as producto, l.estado, l.cantidad_producida as cantidad, l.unidad_ingreso as unidad,
       (l.created_at at time zone 'America/Argentina/Buenos_Aires')::text as cargado_el
  from public.produccion_lotes l
  join public.produccion_items pi on pi.id = l.item_id
 where public.normalizar_texto(pi.nombre) in ('ARROZ', 'ADEREZO DE VERDURAS')
 order by l.created_at desc
 limit 20;
