-- Gata Maula: datos para el "Estado financiero" detallado (solo admin).
--   * dias: efectivo que entro por ventas y efectivo que salio, dia por dia
--   * proveedores: cuanto se compro, cuanto se debe generado y cuanto se pago a cada proveedor
--   * calendario: total pendiente de pago y total vencido
-- Correr UNA vez en el SQL Editor.

create or replace function public.eerr_financiero(p_desde date, p_hasta date)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v jsonb;
begin
  if public.rol_actual() <> 'admin' then
    raise exception 'Sin permiso';
  end if;
  with ef as (
    select fecha, sum(efectivo) as efe from public.caja_diaria where fecha between p_desde and p_hasta group by fecha
  ), sal as (
    select fecha, sum(monto) as egr
      from public.ingresos_egresos
     where forma = 'egreso_efectivo' and fecha between p_desde and p_hasta group by fecha
  ), fechas as (
    select fecha from ef union select fecha from sal
  ), prov as (
    select coalesce(p.nombre, 'SIN PROVEEDOR') as proveedor,
           sum(case when ie.concepto <> 'PAGO DEUDA PROVEEDORES' and ie.forma in ('deuda_proveedores', 'egreso_banco', 'egreso_efectivo') then ie.monto else 0 end) as compras,
           sum(case when ie.forma = 'deuda_proveedores' then ie.monto else 0 end) as a_credito,
           sum(case when ie.concepto = 'PAGO DEUDA PROVEEDORES' then ie.monto else 0 end) as pagos
      from public.ingresos_egresos ie
      left join public.proveedores p on p.id = ie.proveedor_id
     where ie.forma is not null
       and coalesce(to_date(ie.lote_importacion || '-01', 'YYYY-MM-DD'), date_trunc('month', ie.fecha)::date)
           between date_trunc('month', p_desde)::date and p_hasta
     group by 1
    having sum(case when ie.concepto <> 'PAGO DEUDA PROVEEDORES' and ie.forma in ('deuda_proveedores', 'egreso_banco', 'egreso_efectivo') then ie.monto else 0 end) > 0
        or sum(case when ie.concepto = 'PAGO DEUDA PROVEEDORES' then ie.monto else 0 end) > 0
  )
  select jsonb_build_object(
    'dias', coalesce((select jsonb_agg(jsonb_build_object('f', f.fecha, 'efe', coalesce(ef.efe, 0), 'egr', coalesce(sal.egr, 0)) order by f.fecha)
                        from fechas f left join ef on ef.fecha = f.fecha left join sal on sal.fecha = f.fecha), '[]'::jsonb),
    'proveedores', coalesce((select jsonb_agg(jsonb_build_object('p', proveedor, 'compras', compras, 'a_credito', a_credito, 'pagos', pagos) order by compras desc) from prov), '[]'::jsonb),
    'pendiente', coalesce((select sum(total) from public.calendario_pagos where not pagado), 0),
    'vencido', coalesce((select sum(total) from public.calendario_pagos where not pagado and fecha_vencimiento < current_date), 0)
  ) into v;
  return v;
end;
$$;
grant execute on function public.eerr_financiero(date, date) to authenticated;
