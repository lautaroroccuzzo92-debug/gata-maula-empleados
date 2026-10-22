-- Gata Maula: el control de caja contra Postberry separa QR Posnet y QR.
--   * Postberry trae un solo medio "QR", pero cada venta tiene su comprobante:
--       QR con factura (FCB)  -> se compara con "QR Posnet" de la caja
--       QR sin factura (PSP)  -> se compara con "QR" de la caja
--   * facturado (caja) = credito + debito + transferencia + QR Posnet ; sin facturar (caja) = efectivo + QR
-- Correr UNA vez en el SQL Editor (despues de 0031).

create or replace function public.pos_control_caja(p_desde date, p_hasta date)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v jsonb;
begin
  if public.rol_actual() not in ('admin', 'encargado') then raise exception 'Sin permiso'; end if;
  with pp as (
    select (fecha - interval '6 hours')::date as dia,
           case when extract(hour from fecha) >= 17 or extract(hour from fecha) < 6 then 'tarde' else 'manana' end as turno,
           cond_pago, documento, importe
      from public.pos_pagos
     where (fecha - interval '6 hours')::date between p_desde and p_hasta
  ), pt as (
    select dia, turno,
           sum(importe) filter (where cond_pago = 'EFECTIVO') as efectivo,
           sum(importe) filter (where cond_pago = 'TRANSFERENCIA') as transferencia,
           sum(importe) filter (where cond_pago = 'TARJETA DE CREDITO') as credito,
           sum(importe) filter (where cond_pago = 'TARJETA DE DEBITO') as debito,
           sum(importe) filter (where cond_pago = 'QR' and coalesce(documento, '') = 'FCB') as qr_posnet,
           sum(importe) filter (where cond_pago = 'QR' and coalesce(documento, '') <> 'FCB') as qr,
           sum(importe) as total,
           count(*) filter (where importe < 0) as anulaciones,
           coalesce(sum(importe) filter (where importe < 0), 0) as monto_anulado
      from pp group by 1, 2
  ), pd as (
    select dia, sum(efectivo) as efectivo, sum(transferencia) as transferencia, sum(credito) as credito, sum(debito) as debito,
           sum(qr_posnet) as qr_posnet, sum(qr) as qr,
           sum(total) as total, sum(anulaciones) as anulaciones, sum(monto_anulado) as monto_anulado
      from pt group by 1
  ), ct as (
    select c.fecha as dia, c.turno, c.efectivo, c.transferencia, c.tarjeta_credito as credito, c.tarjeta_debito as debito,
           coalesce(c.qr_posnet, 0) as qr_posnet, coalesce(c.qr_mercado_pago, 0) as qr, c.venta_total as total,
           coalesce(u.nombre, c.responsable) as cerro
      from public.caja_diaria c left join public.usuarios u on u.id = c.usuario_id
     where c.fecha between p_desde and p_hasta
  ), cd as (
    select dia, sum(efectivo) as efectivo, sum(transferencia) as transferencia, sum(credito) as credito, sum(debito) as debito,
           sum(qr_posnet) as qr_posnet, sum(qr) as qr, sum(total) as total, string_agg(distinct cerro, ', ') as cerro
      from ct group by 1
  ), d as (
    select coalesce(pd.dia, cd.dia) as dia, pd.dia is not null as hay_pos, cd.dia is not null as hay_caja,
           pd.efectivo as p_efe, pd.transferencia as p_tra, pd.credito as p_cre, pd.debito as p_deb, pd.qr_posnet as p_qrp, pd.qr as p_qr, pd.total as p_tot,
           pd.anulaciones, pd.monto_anulado,
           cd.efectivo as c_efe, cd.transferencia as c_tra, cd.credito as c_cre, cd.debito as c_deb, cd.qr_posnet as c_qrp, cd.qr as c_qr, cd.total as c_tot, cd.cerro
      from pd full join cd on cd.dia = pd.dia
  ), tt as (
    select coalesce(pt.dia, c.dia) as dia, coalesce(pt.turno, c.turno) as turno,
           pt.dia is not null as hay_pos, c.dia is not null as hay_caja,
           pt.efectivo as p_efe, pt.transferencia as p_tra, pt.credito as p_cre, pt.debito as p_deb, pt.qr_posnet as p_qrp, pt.qr as p_qr, pt.total as p_tot,
           c.efectivo as c_efe, c.transferencia as c_tra, c.credito as c_cre, c.debito as c_deb, c.qr_posnet as c_qrp, c.qr as c_qr, c.total as c_tot, c.cerro
      from pt full join (select * from ct where turno in ('manana', 'tarde')) c on c.dia = pt.dia and c.turno = pt.turno
     where coalesce(pt.dia, c.dia) in (select dia from ct where turno <> 'completo')
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'dia', d.dia,
    'postberry', jsonb_build_object('total', round(coalesce(d.p_tot, 0)), 'efectivo', round(coalesce(d.p_efe, 0)), 'transferencia', round(coalesce(d.p_tra, 0)),
        'credito', round(coalesce(d.p_cre, 0)), 'debito', round(coalesce(d.p_deb, 0)), 'qr_posnet', round(coalesce(d.p_qrp, 0)), 'qr', round(coalesce(d.p_qr, 0))),
    'caja_cargada', case when not d.hay_caja then null else jsonb_build_object('total', round(coalesce(d.c_tot, 0)), 'efectivo', round(coalesce(d.c_efe, 0)),
        'transferencia', round(coalesce(d.c_tra, 0)), 'credito', round(coalesce(d.c_cre, 0)), 'debito', round(coalesce(d.c_deb, 0)),
        'qr_posnet', round(coalesce(d.c_qrp, 0)), 'qr', round(coalesce(d.c_qr, 0)),
        'facturado', round(coalesce(d.c_cre, 0) + coalesce(d.c_deb, 0) + coalesce(d.c_tra, 0) + coalesce(d.c_qrp, 0)),
        'sin_facturar', round(coalesce(d.c_efe, 0) + coalesce(d.c_qr, 0))) end,
    'cerro', d.cerro,
    'dif_tarjetas_transferencia', round((coalesce(d.c_cre, 0) + coalesce(d.c_deb, 0) + coalesce(d.c_tra, 0)) - (coalesce(d.p_cre, 0) + coalesce(d.p_deb, 0) + coalesce(d.p_tra, 0))),
    'diferencia_total', round(coalesce(d.c_tot, 0) - coalesce(d.p_tot, 0)),
    'dif_efectivo', round(coalesce(d.c_efe, 0) - coalesce(d.p_efe, 0)),
    'dif_transferencia', round(coalesce(d.c_tra, 0) - coalesce(d.p_tra, 0)),
    'dif_credito', round(coalesce(d.c_cre, 0) - coalesce(d.p_cre, 0)),
    'dif_debito', round(coalesce(d.c_deb, 0) - coalesce(d.p_deb, 0)),
    'dif_qr_posnet', round(coalesce(d.c_qrp, 0) - coalesce(d.p_qrp, 0)),
    'dif_qr', round(coalesce(d.c_qr, 0) - coalesce(d.p_qr, 0)),
    'anulaciones', coalesce(d.anulaciones, 0), 'monto_anulado', round(coalesce(d.monto_anulado, 0)),
    'falta', case when not d.hay_caja then 'no hay cierre de caja cargado' when not d.hay_pos then 'no hay ventas de Postberry cargadas' end,
    'turnos', coalesce((select jsonb_agg(jsonb_build_object(
        'turno', t.turno, 'cerro', t.cerro,
        'postberry_total', round(coalesce(t.p_tot, 0)), 'caja_total', case when t.hay_caja then round(coalesce(t.c_tot, 0)) end,
        'diferencia_total', round(coalesce(t.c_tot, 0) - coalesce(t.p_tot, 0)),
        'dif_efectivo', round(coalesce(t.c_efe, 0) - coalesce(t.p_efe, 0)), 'dif_transferencia', round(coalesce(t.c_tra, 0) - coalesce(t.p_tra, 0)),
        'dif_credito', round(coalesce(t.c_cre, 0) - coalesce(t.p_cre, 0)), 'dif_debito', round(coalesce(t.c_deb, 0) - coalesce(t.p_deb, 0)),
        'dif_qr_posnet', round(coalesce(t.c_qrp, 0) - coalesce(t.p_qrp, 0)), 'dif_qr', round(coalesce(t.c_qr, 0) - coalesce(t.p_qr, 0)),
        'falta', case when not t.hay_caja then 'no hay cierre de este turno' when not t.hay_pos then 'sin ventas de Postberry en este turno' end
      ) order by t.turno) from tt t where t.dia = d.dia), '[]'::jsonb)
  ) order by d.dia), '[]'::jsonb) into v from d;
  return v;
end;
$$;
grant execute on function public.pos_control_caja(date, date) to authenticated;
