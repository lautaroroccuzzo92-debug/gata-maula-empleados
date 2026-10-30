-- Gata Maula: datos del estado de resultados que salen solos desde Postberry + un arreglo en la confirmacion de sueldos.
--   * ARREGLO: al confirmar los sueldos, las filas de PERSONAL tenian una marca que el estado de resultados no entendia
--     (tiene que ser el mes en formato AAAA-MM). Ahora se carga bien. Todavia no habias confirmado ningun mes, asi que no hay nada que corregir.
--   * eerr_familia_sector: a que sector va cada familia de Postberry (sandwiches y picada / vermut y otros / aparte = no suma a ninguno)
--   * eerr_postberry(): por mes, ventas de cada sector, descuentos y un estimado de lo que falta cobrar de tarjetas
--       - dia de negocio: lo vendido hasta las 6 de la manana cuenta para el dia anterior
--       - a cobrar de tarjetas (estimado): debito de los ultimos 2 dias del mes + credito de los ultimos 10 dias del mes
-- Correr UNA vez en el SQL Editor (despues de la 0049).

-- ===== arreglo de sueldos =====
create or replace function public.sueldos_confirmar_mes(p_mes date)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_ini date := date_trunc('month', p_mes)::date;
  v_fin date := (date_trunc('month', p_mes) + interval '1 month - 1 day')::date;
  v_lote text := to_char(date_trunc('month', p_mes), 'YYYY-MM');
  v_efe numeric; v_ban numeric; v_n int; v_ab int; v_sin_tarifa text; v_neg text;
begin
  if public.rol_actual() <> 'admin' then raise exception 'Sin permiso'; end if;
  if public._mes_confirmado(v_ini) then raise exception 'Ese mes ya esta confirmado'; end if;
  select coalesce(sum(abiertos), 0) into v_ab from public._sueldos_calculo(v_ini);
  if v_ab > 0 then raise exception 'Hay % turnos con entrada sin salida. Corregilos antes de confirmar el mes.', v_ab; end if;
  select string_agg(nombre, ', ') into v_sin_tarifa from public._sueldos_calculo(v_ini) where valor_hora is null and (h_normales + h_feriado + h_licencia) > 0;
  if v_sin_tarifa is not null then raise exception 'Falta el valor hora de: %', v_sin_tarifa; end if;
  select string_agg(nombre, ', ') into v_neg from public._sueldos_calculo(v_ini) where transferencia > neto or transferencia < 0;
  if v_neg is not null then raise exception 'La transferencia no puede ser mayor al sueldo (revisa: %)', v_neg; end if;

  select coalesce(sum(efectivo), 0), coalesce(sum(transferencia), 0), count(*) filter (where neto <> 0) into v_efe, v_ban, v_n from public._sueldos_calculo(v_ini);
  if v_efe + v_ban <= 0 then raise exception 'No hay sueldos para confirmar en ese mes'; end if;

  if v_efe > 0 then
    insert into public.ingresos_egresos (fecha, concepto, monto, forma, estado_pago, medio_pago, fecha_pago, origen, usuario_id, observaciones, lote_importacion)
      values (v_fin, 'PERSONAL', v_efe, 'egreso_efectivo', 'pagado', 'efectivo', v_fin, 'manual', auth.uid(), 'Sueldos de ' || to_char(v_ini, 'MM/YYYY') || ' (' || v_n || ' personas), parte en efectivo', v_lote);
  end if;
  if v_ban > 0 then
    insert into public.ingresos_egresos (fecha, concepto, monto, forma, estado_pago, medio_pago, fecha_pago, origen, usuario_id, observaciones, lote_importacion)
      values (v_fin, 'PERSONAL', v_ban, 'egreso_banco', 'pagado', 'banco', v_fin, 'manual', auth.uid(), 'Sueldos de ' || to_char(v_ini, 'MM/YYYY') || ' (' || v_n || ' personas), parte por transferencia', v_lote);
  end if;
  insert into public.sueldos_meses (mes, estado, confirmado_el, confirmado_por) values (v_ini, 'confirmado', now(), auth.uid())
    on conflict (mes) do update set estado = 'confirmado', confirmado_el = now(), confirmado_por = auth.uid();
  return jsonb_build_object('ok', true, 'efectivo', v_efe, 'transferencia', v_ban);
end;
$$;
grant execute on function public.sueldos_confirmar_mes(date) to authenticated;

create or replace function public.sueldos_reabrir_mes(p_mes date)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_ini date := date_trunc('month', p_mes)::date; v_lote text := to_char(date_trunc('month', p_mes), 'YYYY-MM');
begin
  if public.rol_actual() <> 'admin' then raise exception 'Sin permiso'; end if;
  delete from public.ingresos_egresos
   where lote_importacion = v_lote and concepto = 'PERSONAL' and origen = 'manual' and observaciones like 'Sueldos de ' || to_char(v_ini, 'MM/YYYY') || ' (%';
  update public.sueldos_meses set estado = 'abierto', confirmado_el = null, confirmado_por = null where mes = v_ini;
  return jsonb_build_object('ok', true);
end;
$$;
grant execute on function public.sueldos_reabrir_mes(date) to authenticated;

-- ===== familias de Postberry por sector =====
create table if not exists public.eerr_familia_sector (
  familia text primary key,
  sector text not null check (sector in ('sandwiches', 'vermut', 'aparte'))
);
alter table public.eerr_familia_sector enable row level security;

insert into public.eerr_familia_sector (familia, sector) values
  ('SANDWICH FOCACCIA', 'sandwiches'), ('SANDWICHES PAN DE LEVADURA', 'sandwiches'), ('SANDWICHES', 'sandwiches'), ('SANDWICH CIABATTA', 'sandwiches'),
  ('SANDWICH PAN DE MOLDE', 'sandwiches'), ('PICADAS', 'sandwiches'), ('RACIONES', 'sandwiches'), ('KUTSI SANDWICH', 'sandwiches'),
  ('COMBOS KUTSI SANDWICH', 'sandwiches'), ('FIAMBRES', 'sandwiches'), ('QUESOS', 'sandwiches'), ('PANES', 'sandwiches'),
  ('MEDIDA VERMUT', 'vermut'), ('VERMOUTH', 'vermut'), ('AGUAS, GASEOSAS Y CERVEZAS', 'vermut'),
  ('EVENTO GATA MAULA', 'aparte')
on conflict (familia) do nothing;

create or replace function public.eerr_postberry(p_desde date, p_hasta date)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if public.rol_actual() <> 'admin' then raise exception 'Sin permiso'; end if;
  return coalesce((
    with l as (
      select date_trunc('month', fecha - interval '6 hours')::date as mes, upper(trim(coalesce(familia, ''))) as fam,
             coalesce(neto, 0) + coalesce(impuestos, 0) - coalesce(descuentos, 0) as imp, coalesce(descuentos, 0) as dto
        from public.pos_lineas
       where not anulado and (fecha - interval '6 hours')::date between p_desde and p_hasta
    ), v as (
      select l.mes,
             sum(l.imp) filter (where s.sector = 'sandwiches') as sand,
             sum(l.imp) filter (where s.sector = 'vermut') as verm,
             sum(l.imp) filter (where s.sector is null) as sin_clasificar,
             sum(l.dto) as dto, count(*) as n
        from l left join public.eerr_familia_sector s on s.familia = l.fam group by l.mes
    ), p as (
      select (fecha - interval '6 hours')::date as dia, upper(cond_pago) as cp, importe
        from public.pos_pagos where (fecha - interval '6 hours')::date between p_desde and p_hasta
    ), t as (
      select date_trunc('month', dia)::date as mes,
             sum(importe) filter (where cp like 'TARJETA DE DEBITO%' and dia > (date_trunc('month', dia) + interval '1 month - 1 day')::date - 2)
           + sum(importe) filter (where cp like 'TARJETA DE CREDITO%' and dia > (date_trunc('month', dia) + interval '1 month - 1 day')::date - 10) as a_cobrar
        from p group by 1
    )
    select jsonb_agg(jsonb_build_object('mes', to_char(v.mes, 'YYYY-MM'), 'ventas_sandwiches', round(coalesce(v.sand, 0)), 'ventas_vermut', round(coalesce(v.verm, 0)),
             'sin_clasificar', round(coalesce(v.sin_clasificar, 0)), 'descuentos', round(coalesce(v.dto, 0)), 'a_cobrar_tarjetas', round(coalesce(t.a_cobrar, 0))) order by v.mes)
      from v left join t on t.mes = v.mes
  ), '[]'::jsonb);
end;
$$;
grant execute on function public.eerr_postberry(date, date) to authenticated;

-- Control: ventas por sector de los ultimos meses, con las familias que quedaron sin clasificar (si aparece alguna, avisame)
select to_char(date_trunc('month', l.fecha - interval '6 hours'), 'YYYY-MM') as mes, coalesce(s.sector, 'SIN CLASIFICAR') as sector,
       string_agg(distinct coalesce(nullif(trim(l.familia), ''), '(sin familia)'), ' | ') filter (where s.sector is null) as familias_sin_clasificar,
       round(sum(coalesce(l.neto, 0) + coalesce(l.impuestos, 0) - coalesce(l.descuentos, 0))) as vendido
  from public.pos_lineas l left join public.eerr_familia_sector s on s.familia = upper(trim(coalesce(l.familia, '')))
 where not l.anulado
 group by 1, 2 order by 1 desc, 2;
