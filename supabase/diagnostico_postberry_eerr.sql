-- Gata Maula: mirar como viene la informacion de Postberry para armar solos los datos del estado de resultados.
-- Correr en el SQL Editor y exportar el resultado a CSV (boton Export). No modifica nada.

-- 1) Familias de producto: cuanto se vendio, descuentos, costo cargado en Postberry y cuantos renglones no tienen costo
select 'familia' as parte, coalesce(familia, '(sin familia)') as nombre,
       count(*) as renglones,
       round(sum(coalesce(neto, 0) + coalesce(impuestos, 0) - coalesce(descuentos, 0))) as vendido,
       round(sum(coalesce(descuentos, 0))) as descuentos,
       round(sum(coalesce(costo, 0) * coalesce(cantidad, 0))) as costo_postberry,
       count(*) filter (where coalesce(costo, 0) = 0) as renglones_sin_costo
  from public.pos_lineas
 where not anulado and fecha >= date_trunc('month', current_date) - interval '2 months'
 group by 2
union all
-- 2) Medios de pago y movimientos de caja: aca se ve si Postberry separa consumos internos, cortesias, etc.
select 'pago', coalesce(cond_pago, '(vacio)') || ' / ' || coalesce(tipo, '(vacio)'),
       count(*), round(sum(importe)), null, null, null
  from public.pos_pagos
 where fecha >= date_trunc('month', current_date) - interval '2 months'
 group by 2
order by 1, 4 desc nulls last;
