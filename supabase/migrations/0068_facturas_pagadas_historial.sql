-- Gata Maula: las facturas que el Calendario de pagos ya marco como pagadas tambien pasan a "pagada" en Ingresos/Egresos.
--   Pasaba que al marcar "Ya estaba pagado y anotado" en el calendario, la factura de origen seguia como pendiente.
--   Esto NO cambia el estado de resultados (que se calcula por la forma del movimiento, no por el estado de pago).
-- Correr UNA vez en el SQL Editor. Es seguro correrlo mas de una vez.

update public.ingresos_egresos i
   set estado_pago = 'pagado', fecha_pago = coalesce(i.fecha_pago, cp.fecha_pago)
  from public.calendario_pagos cp
 where cp.egreso_id = i.id and cp.pagado
   and i.forma = 'deuda_proveedores' and i.estado_pago = 'pendiente';

-- Lo que sigue figurando "a pagar" (para revisar): una fila por factura, con lo que dice el calendario sobre ella.
select to_char(i.fecha, 'YYYY-MM-DD') as fecha,
       coalesce(p.nombre, '(sin proveedor)') as proveedor,
       coalesce(i.factura_numero, i.remito_numero, '') as numero,
       round(sum(i.monto)) as monto,
       case when bool_or(cp.id is null) then 'SIN renglon en el calendario'
            when bool_and(cp.pagado) then 'calendario dice PAGADA'
            else 'calendario pendiente' end as calendario,
       max(i.origen) as origen
  from public.ingresos_egresos i
  left join public.proveedores p on p.id = i.proveedor_id
  left join public.calendario_pagos cp on cp.egreso_id = i.id
 where i.forma = 'deuda_proveedores' and i.estado_pago = 'pendiente' and i.monto > 0
 group by i.fecha, p.nombre, coalesce(i.factura_numero, i.remito_numero, ''), i.comprobante_id
 order by 5, 1 desc, 2;
