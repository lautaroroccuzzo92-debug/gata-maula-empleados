-- Gata Maula: estado de resultados automatico (igual a la hoja EERR de tu Excel).
--   * caja_diaria.monto_fiscal: la columna "MONTO FISCAL" de tu planilla de caja
--   * eerr_manual: los datos que no salen solos (stock inicial y final, costo teorico, ventas por sector, saldos de bancos...)
--   * eerr_base(): suma de ventas, egresos por concepto y desperdicios de un periodo (solo admin)
-- Correr UNA vez en el SQL Editor. Despues volver a correr 0013_historial_caja.sql (ahora trae el monto fiscal).

alter table public.caja_diaria add column if not exists monto_fiscal numeric(14,2);

create table if not exists public.eerr_manual (
  mes date primary key,
  ventas_sandwiches numeric(14,2),
  ventas_vermut numeric(14,2),
  stock_inicio numeric(14,2),
  stock_fin numeric(14,2),
  consumos_internos numeric(14,2),
  desperdicios numeric(14,2),
  costo_teorico_pct numeric(8,4),
  costo_laboral_real numeric(14,2),
  saldo_mes_anterior numeric(14,2),
  saldo_mercado_pago numeric(14,2),
  saldo_banco numeric(14,2),
  a_cobrar_tarjetas numeric(14,2),
  saldo_banco_fin numeric(14,2),
  fondo_inversion numeric(14,2),
  actualizado_por uuid references public.usuarios(id),
  actualizado_en timestamptz not null default now()
);
alter table public.eerr_manual enable row level security;
drop policy if exists eerr_manual_admin on public.eerr_manual;
create policy eerr_manual_admin on public.eerr_manual for all using (public.rol_actual() = 'admin') with check (public.rol_actual() = 'admin');

-- Totales por mes: ventas de la caja, egresos por concepto y forma, desperdicios.
-- Los movimientos importados del Excel se agrupan por el mes de su planilla (lote_importacion).
create or replace function public.eerr_base(p_desde date, p_hasta date)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v jsonb;
begin
  if public.rol_actual() <> 'admin' then
    raise exception 'Sin permiso';
  end if;
  with c as (
    select date_trunc('month', fecha)::date as mes,
           sum(tarjeta_credito) as tc, sum(tarjeta_debito) as td, sum(transferencia) as tr,
           sum(qr_posnet) as qp, sum(qr_mercado_pago) as mp, sum(efectivo) as efe,
           sum(coalesce(monto_fiscal, tarjeta_credito + tarjeta_debito + transferencia + qr_posnet)) as fiscal
      from public.caja_diaria where fecha between p_desde and p_hasta group by 1
  ), e as (
    select coalesce(to_date(lote_importacion || '-01', 'YYYY-MM-DD'), date_trunc('month', fecha)::date) as mes,
           concepto as c, forma as f, sum(monto) as t
      from public.ingresos_egresos
     where forma is not null
       and coalesce(to_date(lote_importacion || '-01', 'YYYY-MM-DD'), date_trunc('month', fecha)::date) between date_trunc('month', p_desde)::date and p_hasta
     group by 1, 2, 3
  ), d as (
    select date_trunc('month', fecha)::date as mes, sum(coalesce(valor_calculado, 0)) as t
      from public.desperdicio where fecha between p_desde and p_hasta group by 1
  ), m as (
    select mes from c union select mes from e union select mes from d
  )
  select jsonb_build_object('meses', coalesce(jsonb_agg(jsonb_build_object(
      'mes', to_char(m.mes, 'YYYY-MM'),
      'caja', coalesce((select to_jsonb(c) - 'mes' from c where c.mes = m.mes), '{}'::jsonb),
      'egresos', coalesce((select jsonb_agg(jsonb_build_object('c', e.c, 'f', e.f, 't', e.t)) from e where e.mes = m.mes), '[]'::jsonb),
      'desperdicios', coalesce((select d.t from d where d.mes = m.mes), 0)
    ) order by m.mes), '[]'::jsonb)) into v
  from m;
  return v;
end;
$$;
grant execute on function public.eerr_base(date, date) to authenticated;

-- Datos manuales de tus planillas (enero 2025 a septiembre 2026)
insert into public.eerr_manual (mes, ventas_sandwiches, ventas_vermut, stock_inicio, stock_fin, consumos_internos, desperdicios, costo_teorico_pct, costo_laboral_real, saldo_mes_anterior, saldo_mercado_pago, saldo_banco, a_cobrar_tarjetas, saldo_banco_fin, fondo_inversion) values
('2025-01-01',null,null,5000000,3560253,null,null,0,null,null,null,null,null,null,null),
('2025-02-01',11111484.22,10020799.3,3560253,3451843,null,null,0,null,null,null,null,null,null,null),
('2025-03-01',11488747,8893356,3451843,6733425.37,null,null,0,null,null,null,null,null,null,null),
('2025-04-01',13332499.65,9624059,6733425.37,3826360,null,null,0,null,null,null,null,null,null,null),
('2025-05-01',14352418.1,9960257,3826360,5437428.28,null,null,0,null,null,1170286.36,763893.32,217165,null,null),
('2025-06-01',11225165.42,6269872.27,5437428.28,4443056.85,null,null,0,null,null,1170286.36,763893.32,0,null,null),
('2025-07-01',null,null,4443056.85,4037800,null,null,0,null,null,1170286.36,763893.32,289201,null,null),
('2025-08-01',null,null,4666753,3760705.67,null,null,0,null,null,1170286.36,763893.32,177000,null,null),
('2025-09-01',null,null,3760705.67,5063382.93,null,null,0,null,null,1170286.36,763893.32,467000,null,null),
('2025-10-01',null,null,5063382.93,4704423.3,null,null,0,null,null,1170286.36,763893.32,488197,null,null),
('2025-11-01',null,null,4704423.3,4587233,null,null,0,null,null,1170286.36,763893.32,67352,null,null),
('2025-12-01',null,null,4587233,6225303,null,null,0.3039,null,null,1170286.36,763893.32,70300,null,null),
('2026-01-01',10170101.98,9000564.9,6225303,5553170.46,null,95791,0.3564,null,null,1170286.36,763893.32,408700,null,null),
('2026-02-01',null,null,5553170.46,5965598,null,126688,0.3564,null,null,1170286.36,763893.32,null,null,null),
('2026-03-01',null,null,5965598,5098643,null,146167,0.3564,null,null,1170286.36,763893.32,null,null,null),
('2026-04-01',null,null,5098643,4797148,null,122710,0.3564,null,null,1170286.36,763893.32,null,null,null),
('2026-05-01',null,null,4797148,4621685,null,164782,0.3564,null,null,1170286.36,763893.32,null,null,null),
('2026-06-01',null,null,4621685,3794469.29,null,78696,0.3564,null,null,1170286.36,763893.32,null,null,null),
('2026-07-01',null,null,3794469.29,5807043,null,66735,0.3564,null,null,1170286.36,763893.32,null,null,null),
('2026-08-01',null,null,5807043,3938557,null,75927,0.3564,null,null,1170286.36,763893.32,null,null,null),
('2026-09-01',null,null,5807043,5324904,null,86761,0.3564,null,null,1170286.36,763893.32,null,null,null)
on conflict (mes) do update set ventas_sandwiches = excluded.ventas_sandwiches, ventas_vermut = excluded.ventas_vermut, stock_inicio = excluded.stock_inicio, stock_fin = excluded.stock_fin, consumos_internos = excluded.consumos_internos, desperdicios = excluded.desperdicios, costo_teorico_pct = excluded.costo_teorico_pct, costo_laboral_real = excluded.costo_laboral_real, saldo_mes_anterior = excluded.saldo_mes_anterior, saldo_mercado_pago = excluded.saldo_mercado_pago, saldo_banco = excluded.saldo_banco, a_cobrar_tarjetas = excluded.a_cobrar_tarjetas, saldo_banco_fin = excluded.saldo_banco_fin, fondo_inversion = excluded.fondo_inversion;
