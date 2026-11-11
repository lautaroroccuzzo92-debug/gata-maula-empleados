-- Gata Maula: dos facturas de octubre que ya estaban pagadas pero figuraban "a pagar" en Ingresos/Egresos (no tenian renglon en el calendario).
--   * Zecor del 22/10 ($54.400) y De Chiarrini del 23/10 ($146.016, factura 0004-00001323).
-- Solo cambia el estado a "pagado": NO crea gastos ni pagos nuevos y no modifica el estado de resultados.
-- Correr UNA vez en el SQL Editor. Es seguro correrlo mas de una vez.

update public.ingresos_egresos i
   set estado_pago = 'pagado'
  from public.proveedores p
 where p.id = i.proveedor_id
   and i.forma = 'deuda_proveedores' and i.estado_pago = 'pendiente'
   and not exists (select 1 from public.calendario_pagos cp where cp.egreso_id = i.id)
   and ((i.fecha = '2026-10-22' and upper(p.nombre) like 'ZECOR%' and i.monto = 54400)
     or (i.fecha = '2026-10-23' and upper(p.nombre) like 'DCH%' and i.monto = 146016));

-- resultado: las facturas "a pagar" que quedan sin renglon en el calendario (tiene que salir vacio)
select i.fecha, coalesce(p.nombre, '(sin proveedor)') as proveedor, coalesce(i.factura_numero, i.remito_numero, '') as numero, round(i.monto) as monto, i.concepto
  from public.ingresos_egresos i left join public.proveedores p on p.id = i.proveedor_id
 where i.forma = 'deuda_proveedores' and i.estado_pago = 'pendiente' and i.monto > 0
   and not exists (select 1 from public.calendario_pagos cp where cp.egreso_id = i.id)
 order by i.fecha desc;
