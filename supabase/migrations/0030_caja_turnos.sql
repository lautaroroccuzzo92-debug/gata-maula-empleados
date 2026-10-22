-- Gata Maula: caja diaria por turno (manana / tarde) y registro de quien hizo cada cierre.
--   * un cierre por dia y por turno; los cierres viejos quedan como turno 'completo' (dia entero)
--   * usuario_id = quien cargo el cierre por primera vez; actualizado_por / actualizado_en = quien lo corrigio despues
--   * guardar_cierre_caja(): carga o corrige un cierre (admin y encargado) dejando constancia del usuario
--   * caja_cierres(): lista de cierres con el nombre de quien los hizo
--   * pos_control_caja(): ahora tambien compara cada turno con Postberry (manana hasta las 17:00, tarde desde las 17:00 hasta las 6:00)
-- Correr UNA vez en el SQL Editor.

alter table public.caja_diaria add column if not exists turno text not null default 'completo';
alter table public.caja_diaria drop constraint if exists caja_diaria_turno_check;
alter table public.caja_diaria add constraint caja_diaria_turno_check check (turno in ('manana', 'tarde', 'completo'));
alter table public.caja_diaria add column if not exists actualizado_por uuid references public.usuarios(id) on delete set null;
alter table public.caja_diaria add column if not exists actualizado_en timestamptz;

alter table public.caja_diaria drop constraint if exists caja_diaria_fecha_key;
create unique index if not exists caja_diaria_fecha_turno_idx on public.caja_diaria (fecha, turno);

-- ---------------------------------------------------------------- guardar un cierre
create or replace function public.guardar_cierre_caja(
  p_fecha date, p_turno text, p_credito numeric, p_debito numeric, p_transferencia numeric,
  p_qr_posnet numeric, p_qr_mp numeric, p_efectivo numeric
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_nombre text; v_id uuid; v_nuevo boolean;
begin
  if public.rol_actual() not in ('admin', 'encargado') then raise exception 'Sin permiso'; end if;
  if p_fecha is null then raise exception 'Falta la fecha'; end if;
  if p_turno not in ('manana', 'tarde', 'completo') then raise exception 'Turno invalido'; end if;
  if p_turno = 'completo' and exists (select 1 from public.caja_diaria where fecha = p_fecha and turno <> 'completo') then
    raise exception 'Ese dia ya tiene cierres por turno; cargalo como turno manana o tarde';
  end if;
  if p_turno <> 'completo' and exists (select 1 from public.caja_diaria where fecha = p_fecha and turno = 'completo') then
    raise exception 'Ese dia ya tiene un cierre de dia completo; no se puede sumar un turno';
  end if;

  select nombre into v_nombre from public.usuarios where id = auth.uid();
  select id into v_id from public.caja_diaria where fecha = p_fecha and turno = p_turno;

  if v_id is null then
    insert into public.caja_diaria (fecha, turno, tarjeta_credito, tarjeta_debito, transferencia, qr_posnet, qr_mercado_pago, efectivo, usuario_id, responsable)
      values (p_fecha, p_turno, coalesce(p_credito, 0), coalesce(p_debito, 0), coalesce(p_transferencia, 0), coalesce(p_qr_posnet, 0), coalesce(p_qr_mp, 0), coalesce(p_efectivo, 0), auth.uid(), v_nombre)
      returning id into v_id;
    v_nuevo := true;
  else
    update public.caja_diaria set tarjeta_credito = coalesce(p_credito, 0), tarjeta_debito = coalesce(p_debito, 0), transferencia = coalesce(p_transferencia, 0),
      qr_posnet = coalesce(p_qr_posnet, 0), qr_mercado_pago = coalesce(p_qr_mp, 0), efectivo = coalesce(p_efectivo, 0),
      actualizado_por = auth.uid(), actualizado_en = now()
      where id = v_id;
    v_nuevo := false;
  end if;
  return jsonb_build_object('id', v_id, 'nuevo', v_nuevo);
end;
$$;
grant execute on function public.guardar_cierre_caja(date, text, numeric, numeric, numeric, numeric, numeric, numeric) to authenticated;

-- ---------------------------------------------------------------- lista de cierres (con quien los hizo)
create or replace function public.caja_cierres(p_desde date, p_hasta date)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if public.rol_actual() not in ('admin', 'encargado') then raise exception 'Sin permiso'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'fecha', c.fecha, 'turno', c.turno, 'total', c.venta_total,
      'credito', c.tarjeta_credito, 'debito', c.tarjeta_debito, 'transferencia', c.transferencia,
      'qr_posnet', c.qr_posnet, 'qr_mp', c.qr_mercado_pago, 'efectivo', c.efectivo,
      'cerro', coalesce(u.nombre, c.responsable), 'cerro_el', c.created_at,
      'edito', ue.nombre, 'edito_el', c.actualizado_en
    ) order by c.fecha desc, c.turno)
    from public.caja_diaria c
    left join public.usuarios u on u.id = c.usuario_id
    left join public.usuarios ue on ue.id = c.actualizado_por
    where c.fecha between p_desde and p_hasta
  ), '[]'::jsonb);
end;
$$;
grant execute on function public.caja_cierres(date, date) to authenticated;

-- ---------------------------------------------------------------- control contra Postberry, dia y turno
create or replace function public.pos_control_caja(p_desde date, p_hasta date)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v jsonb;
begin
  if public.rol_actual() not in ('admin', 'encargado') then raise exception 'Sin permiso'; end if;
  with pp as (
    select (fecha - interval '6 hours')::date as dia,
           case when extract(hour from fecha) >= 17 or extract(hour from fecha) < 6 then 'tarde' else 'manana' end as turno,
           cond_pago, importe
      from public.pos_pagos
     where (fecha - interval '6 hours')::date between p_desde and p_hasta
  ), pt as (
    select dia, turno,
           sum(importe) filter (where cond_pago = 'EFECTIVO') as efectivo,
           sum(importe) filter (where cond_pago = 'TRANSFERENCIA') as transferencia,
           sum(importe) filter (where cond_pago = 'TARJETA DE CREDITO') as credito,
           sum(importe) filter (where cond_pago = 'TARJETA DE DEBITO') as debito,
           sum(importe) filter (where cond_pago = 'QR') as qr,
           sum(importe) as total,
           count(*) filter (where importe < 0) as anulaciones,
           coalesce(sum(importe) filter (where importe < 0), 0) as monto_anulado
      from pp group by 1, 2
  ), pd as (
    select dia, sum(efectivo) as efectivo, sum(transferencia) as transferencia, sum(credito) as credito, sum(debito) as debito, sum(qr) as qr,
           sum(total) as total, sum(anulaciones) as anulaciones, sum(monto_anulado) as monto_anulado
      from pt group by 1
  ), ct as (
    select c.fecha as dia, c.turno, c.efectivo, c.transferencia, c.tarjeta_credito as credito, c.tarjeta_debito as debito,
           coalesce(c.qr_posnet, 0) + coalesce(c.qr_mercado_pago, 0) as qr, c.venta_total as total,
           coalesce(u.nombre, c.responsable) as cerro
      from public.caja_diaria c left join public.usuarios u on u.id = c.usuario_id
     where c.fecha between p_desde and p_hasta
  ), cd as (
    select dia, sum(efectivo) as efectivo, sum(transferencia) as transferencia, sum(credito) as credito, sum(debito) as debito, sum(qr) as qr,
           sum(total) as total, string_agg(distinct cerro, ', ') as cerro
      from ct group by 1
  ), d as (
    select coalesce(pd.dia, cd.dia) as dia, pd.dia is not null as hay_pos, cd.dia is not null as hay_caja,
           pd.efectivo as p_efe, pd.transferencia as p_tra, pd.credito as p_cre, pd.debito as p_deb, pd.qr as p_qr, pd.total as p_tot,
           pd.anulaciones, pd.monto_anulado,
           cd.efectivo as c_efe, cd.transferencia as c_tra, cd.credito as c_cre, cd.debito as c_deb, cd.qr as c_qr, cd.total as c_tot, cd.cerro
      from pd full join cd on cd.dia = pd.dia
  ), tt as (
    select coalesce(pt.dia, c.dia) as dia, coalesce(pt.turno, c.turno) as turno,
           pt.dia is not null as hay_pos, c.dia is not null as hay_caja,
           pt.efectivo as p_efe, pt.transferencia as p_tra, pt.credito as p_cre, pt.debito as p_deb, pt.qr as p_qr, pt.total as p_tot,
           c.efectivo as c_efe, c.transferencia as c_tra, c.credito as c_cre, c.debito as c_deb, c.qr as c_qr, c.total as c_tot, c.cerro
      from pt full join (select * from ct where turno in ('manana', 'tarde')) c on c.dia = pt.dia and c.turno = pt.turno
     where coalesce(pt.dia, c.dia) in (select dia from ct where turno <> 'completo')
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'dia', d.dia,
    'postberry', jsonb_build_object('total', round(coalesce(d.p_tot, 0)), 'efectivo', round(coalesce(d.p_efe, 0)), 'transferencia', round(coalesce(d.p_tra, 0)),
        'credito', round(coalesce(d.p_cre, 0)), 'debito', round(coalesce(d.p_deb, 0)), 'qr', round(coalesce(d.p_qr, 0))),
    'caja_cargada', case when not d.hay_caja then null else jsonb_build_object('total', round(coalesce(d.c_tot, 0)), 'efectivo', round(coalesce(d.c_efe, 0)),
        'transferencia', round(coalesce(d.c_tra, 0)), 'credito', round(coalesce(d.c_cre, 0)), 'debito', round(coalesce(d.c_deb, 0)), 'qr', round(coalesce(d.c_qr, 0))) end,
    'cerro', d.cerro,
    'diferencia_total', round(coalesce(d.c_tot, 0) - coalesce(d.p_tot, 0)),
    'dif_efectivo', round(coalesce(d.c_efe, 0) - coalesce(d.p_efe, 0)),
    'dif_transferencia', round(coalesce(d.c_tra, 0) - coalesce(d.p_tra, 0)),
    'dif_credito', round(coalesce(d.c_cre, 0) - coalesce(d.p_cre, 0)),
    'dif_debito', round(coalesce(d.c_deb, 0) - coalesce(d.p_deb, 0)),
    'dif_qr', round(coalesce(d.c_qr, 0) - coalesce(d.p_qr, 0)),
    'anulaciones', coalesce(d.anulaciones, 0), 'monto_anulado', round(coalesce(d.monto_anulado, 0)),
    'falta', case when not d.hay_caja then 'no hay cierre de caja cargado' when not d.hay_pos then 'no hay ventas de Postberry cargadas' end,
    'turnos', coalesce((select jsonb_agg(jsonb_build_object(
        'turno', t.turno, 'cerro', t.cerro,
        'postberry_total', round(coalesce(t.p_tot, 0)), 'caja_total', case when t.hay_caja then round(coalesce(t.c_tot, 0)) end,
        'diferencia_total', round(coalesce(t.c_tot, 0) - coalesce(t.p_tot, 0)),
        'dif_efectivo', round(coalesce(t.c_efe, 0) - coalesce(t.p_efe, 0)), 'dif_transferencia', round(coalesce(t.c_tra, 0) - coalesce(t.p_tra, 0)),
        'dif_credito', round(coalesce(t.c_cre, 0) - coalesce(t.p_cre, 0)), 'dif_debito', round(coalesce(t.c_deb, 0) - coalesce(t.p_deb, 0)),
        'dif_qr', round(coalesce(t.c_qr, 0) - coalesce(t.p_qr, 0)),
        'falta', case when not t.hay_caja then 'no hay cierre de este turno' when not t.hay_pos then 'sin ventas de Postberry en este turno' end
      ) order by t.turno) from tt t where t.dia = d.dia), '[]'::jsonb)
  ) order by d.dia), '[]'::jsonb) into v from d;
  return v;
end;
$$;
grant execute on function public.pos_control_caja(date, date) to authenticated;
