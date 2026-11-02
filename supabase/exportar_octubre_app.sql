-- Gata Maula: todo lo que la app tiene cargado en Ingresos y egresos en octubre 2026 (para compararlo con tu planilla EERR OCTUBRE y no duplicar).
-- Correr en el SQL Editor y exportar el resultado a CSV (boton Export). No modifica nada.
select e.fecha, coalesce(p.nombre, '(sin proveedor)') as proveedor, e.concepto, e.factura_numero, e.monto, e.forma, e.estado_pago, e.origen,
       e.lote_importacion, left(coalesce(e.observaciones, ''), 80) as observaciones
  from public.ingresos_egresos e left join public.proveedores p on p.id = e.proveedor_id
 where e.fecha >= '2026-10-01' and e.fecha < '2026-11-01'
 order by e.fecha, 2, e.concepto;
