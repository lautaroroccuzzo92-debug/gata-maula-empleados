-- Gata Maula: sueldos con aguinaldo y vacaciones, feriados por tipo, historial de horas y busqueda por dia.
--   * Feriados: cada uno tiene un tipo (nacional, provincial, local o dia no laborable) y si se paga doble.
--     Se pagan dobles los feriados nacionales y los que decreta la provincia o la ciudad de Cordoba. Los dias no laborables NO se pagan doble.
--   * Sueldos: bono por rendimiento, vacaciones y aguinaldo (sugerido solo en junio y diciembre: 50% del mejor sueldo del semestre, proporcional a los dias).
--     Al confirmar el mes, el aguinaldo y las vacaciones se cargan en Ingresos y egresos como "AGUINALDOS, VACACIONES" (aparte de PERSONAL).
--   * Personal: fecha de ingreso (para el aguinaldo).
--   * Historial: horas de todos los meses por persona y busqueda de quien trabajo un dia.
-- Correr UNA vez en el SQL Editor (despues de la 0049 y la 0053).

-- ===== feriados =====
alter table public.feriados add column if not exists tipo text not null default 'nacional';
alter table public.feriados add column if not exists paga_doble boolean not null default true;
alter table public.feriados drop constraint if exists feriados_tipo_check;
alter table public.feriados add constraint feriados_tipo_check check (tipo in ('nacional', 'provincial', 'local', 'no_laborable'));

insert into public.feriados (fecha, nombre, tipo, paga_doble) values
  ('2026-01-01', 'Año Nuevo', 'nacional', true),
  ('2026-02-16', 'Carnaval', 'nacional', true),
  ('2026-02-17', 'Carnaval', 'nacional', true),
  ('2026-03-23', 'Día no laborable con fines turísticos', 'no_laborable', false),
  ('2026-03-24', 'Día de la Memoria', 'nacional', true),
  ('2026-04-02', 'Día del Veterano y de los Caídos en Malvinas', 'nacional', true),
  ('2026-04-03', 'Viernes Santo', 'nacional', true),
  ('2026-05-01', 'Día del Trabajador', 'nacional', true),
  ('2026-05-25', 'Revolución de Mayo', 'nacional', true),
  ('2026-06-15', 'Paso a la Inmortalidad del Gral. Güemes (trasladado)', 'nacional', true),
  ('2026-06-20', 'Paso a la Inmortalidad del Gral. Belgrano', 'nacional', true),
  ('2026-07-09', 'Día de la Independencia', 'nacional', true),
  ('2026-07-10', 'Día no laborable con fines turísticos', 'no_laborable', false),
  ('2026-08-17', 'Paso a la Inmortalidad del Gral. San Martín', 'nacional', true),
  ('2026-10-12', 'Día del Respeto a la Diversidad Cultural', 'nacional', true),
  ('2026-11-09', 'Feriado en Córdoba (informado por Lautaro)', 'provincial', true),
  ('2026-11-10', 'Feriado en Córdoba (informado por Lautaro)', 'provincial', true),
  ('2026-11-23', 'Día de la Soberanía Nacional (trasladado; verificar fecha)', 'nacional', true),
  ('2026-12-07', 'Día no laborable con fines turísticos', 'no_laborable', false),
  ('2026-12-08', 'Inmaculada Concepción de María', 'nacional', true),
  ('2026-12-25', 'Navidad', 'nacional', true)
on conflict (fecha) do update set nombre = excluded.nombre, tipo = excluded.tipo, paga_doble = excluded.paga_doble;

drop function if exists public.feriados_listar(int);
create or replace function public.feriados_listar(p_anio int)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._es_gestor() then raise exception 'Sin permiso'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('fecha', fecha, 'nombre', nombre, 'tipo', tipo, 'paga_doble', paga_doble) order by fecha)
                     from public.feriados where extract(year from fecha) = p_anio), '[]'::jsonb);
end;
$$;
grant execute on function public.feriados_listar(int) to authenticated;

drop function if exists public.feriado_guardar(date, text);
create or replace function public.feriado_guardar(p_fecha date, p_nombre text, p_tipo text default 'nacional', p_paga_doble boolean default true)
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if public.rol_actual() <> 'admin' then raise exception 'Sin permiso'; end if;
  if p_tipo not in ('nacional', 'provincial', 'local', 'no_laborable') then raise exception 'Tipo invalido'; end if;
  insert into public.feriados (fecha, nombre, tipo, paga_doble)
    values (p_fecha, coalesce(nullif(trim(coalesce(p_nombre, '')), ''), 'Feriado'), p_tipo, case when p_tipo = 'no_laborable' then false else coalesce(p_paga_doble, true) end)
    on conflict (fecha) do update set nombre = excluded.nombre, tipo = excluded.tipo, paga_doble = excluded.paga_doble;
  return jsonb_build_object('ok', true);
end;
$$;
grant execute on function public.feriado_guardar(date, text, text, boolean) to authenticated;

-- ===== personal y ajustes =====
alter table public.empleados add column if not exists fecha_ingreso date;
alter table public.sueldos_ajustes add column if not exists vacaciones numeric(14,2) not null default 0;

drop function if exists public.empleados_listar();
create or replace function public.empleados_listar()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_admin boolean := public.rol_actual() = 'admin';
begin
  if not public._es_gestor() then raise exception 'Sin permiso'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'nombre', e.nombre, 'casual', e.casual, 'activo', e.activo,
            'usuario_id', e.usuario_id, 'usuario', u.nombre,
            'fecha_ingreso', case when v_admin then e.fecha_ingreso end,
            'valor_hora', case when v_admin then (select t.valor_hora from public.empleado_tarifas t where t.empleado_id = e.id order by t.desde desc limit 1) end,
            'tarifa_desde', case when v_admin then (select t.desde from public.empleado_tarifas t where t.empleado_id = e.id order by t.desde desc limit 1) end)
          order by e.activo desc, e.nombre)
        from public.empleados e left join public.usuarios u on u.id = e.usuario_id), '[]'::jsonb);
end;
$$;
grant execute on function public.empleados_listar() to authenticated;

drop function if exists public.empleado_guardar(uuid, text, boolean, boolean, uuid);
create or replace function public.empleado_guardar(p_id uuid, p_nombre text, p_casual boolean, p_activo boolean, p_usuario uuid default null, p_ingreso date default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id uuid := p_id; v_admin boolean := public.rol_actual() = 'admin';
begin
  if not public._es_gestor() then raise exception 'Sin permiso'; end if;
  if nullif(trim(coalesce(p_nombre, '')), '') is null then raise exception 'Falta el nombre'; end if;
  if v_id is null then
    insert into public.empleados (nombre, casual, activo, usuario_id, fecha_ingreso)
      values (trim(p_nombre), coalesce(p_casual, false), coalesce(p_activo, true), case when v_admin then p_usuario end, case when v_admin then p_ingreso end)
      returning id into v_id;
  else
    update public.empleados set nombre = trim(p_nombre), casual = coalesce(p_casual, casual), activo = coalesce(p_activo, activo),
        usuario_id = case when v_admin then p_usuario else usuario_id end,
        fecha_ingreso = case when v_admin then p_ingreso else fecha_ingreso end
      where id = v_id;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id);
exception when unique_violation then
  raise exception 'Ya hay una persona con ese nombre o ese usuario ya esta asignado a otra persona';
end;
$$;
grant execute on function public.empleado_guardar(uuid, text, boolean, boolean, uuid, date) to authenticated;

-- ===== horas =====
-- Un turno sin salida solo cuenta "en vivo" si es de hoy o de ayer; uno viejo sin salida vale 0 (queda marcado "sin salida" para corregir)
create or replace function public._horas_turno_vivo(p_fecha date, p_entrada time, p_salida time, p_tipo text, p_lic numeric)
returns numeric language sql stable as $$
  select case
    when p_tipo = 'trabajo' and p_salida is null and p_entrada is not null then
      case when p_fecha >= (now() at time zone 'America/Argentina/Buenos_Aires')::date - 1
           then least(24, greatest(0, round(extract(epoch from ((now() at time zone 'America/Argentina/Buenos_Aires') - (p_fecha + p_entrada))) / 3600.0, 4)))
           else 0 end
    else public._horas_turno(p_entrada, p_salida, p_tipo, p_lic) end
$$;

create or replace function public.horas_mes(p_mes date, p_empleado uuid default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_emp uuid; v_ini date := date_trunc('month', p_mes)::date; v_admin boolean := public.rol_actual() = 'admin';
        v_hoy date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
begin
  if public.rol_actual() is null then raise exception 'Sin permiso'; end if;
  v_emp := coalesce(p_empleado, public._empleado_actual());
  if v_emp is null then return jsonb_build_object('turnos', '[]'::jsonb, 'total', 0); end if;
  if v_emp is distinct from public._empleado_actual() and not public._es_gestor() then raise exception 'Sin permiso'; end if;
  return jsonb_build_object(
    'empleado', (select nombre from public.empleados where id = v_emp),
    'cerrado', public._mes_confirmado(v_ini),
    'total', coalesce((select sum(public._horas_turno_vivo(fecha, entrada, salida, tipo, horas_licencia)) from public.horas_turnos
                        where empleado_id = v_emp and fecha >= v_ini and fecha < v_ini + interval '1 month' and (tipo = 'trabajo' or v_admin)), 0),
    'turnos', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'fecha', t.fecha, 'entrada', to_char(t.entrada, 'HH24:MI'), 'salida', to_char(t.salida, 'HH24:MI'),
                              'horas', public._horas_turno_vivo(t.fecha, t.entrada, t.salida, t.tipo, t.horas_licencia), 'tipo', t.tipo, 'nota', t.nota,
                              'feriado', exists (select 1 from public.feriados f where f.fecha = t.fecha and f.paga_doble),
                              'abierto', (t.tipo = 'trabajo' and t.salida is null and t.fecha >= v_hoy - 1),
                              'sin_salida', (t.tipo = 'trabajo' and t.salida is null and t.fecha < v_hoy - 1)) order by t.fecha desc, t.entrada desc nulls last)
                          from public.horas_turnos t
                         where t.empleado_id = v_emp and t.fecha >= v_ini and t.fecha < v_ini + interval '1 month' and (t.tipo = 'trabajo' or v_admin)), '[]'::jsonb));
end;
$$;
grant execute on function public.horas_mes(date, uuid) to authenticated;

-- Historial: horas por mes. Cada persona ve las suyas; Manu, Facu y el admin pueden ver las de cualquiera (o de todos juntos).
create or replace function public.horas_historial(p_empleado uuid default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_emp uuid; v_admin boolean := public.rol_actual() = 'admin';
begin
  if public.rol_actual() is null then raise exception 'Sin permiso'; end if;
  if p_empleado is null and not public._es_gestor() then v_emp := public._empleado_actual(); else v_emp := p_empleado; end if;
  if v_emp is not null and v_emp is distinct from public._empleado_actual() and not public._es_gestor() then raise exception 'Sin permiso'; end if;
  if v_emp is null and not public._es_gestor() then return '[]'::jsonb; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('mes', x.mes, 'horas', round(x.horas, 2), 'turnos', x.n, 'personas', x.personas) order by x.mes desc)
      from (select to_char(date_trunc('month', t.fecha), 'YYYY-MM') as mes,
                   sum(public._horas_turno_vivo(t.fecha, t.entrada, t.salida, t.tipo, t.horas_licencia)) as horas, count(*) as n,
                   count(distinct t.empleado_id) as personas
              from public.horas_turnos t
             where (v_emp is null or t.empleado_id = v_emp) and (t.tipo = 'trabajo' or v_admin)
             group by 1) x), '[]'::jsonb);
end;
$$;
grant execute on function public.horas_historial(uuid) to authenticated;

-- Buscar por dia: quien trabajo ese dia (cada persona ve solo los suyos)
create or replace function public.horas_dia(p_fecha date)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_admin boolean := public.rol_actual() = 'admin'; v_emp uuid := public._empleado_actual();
begin
  if public.rol_actual() is null then raise exception 'Sin permiso'; end if;
  return jsonb_build_object(
    'feriado', (select jsonb_build_object('nombre', f.nombre, 'paga_doble', f.paga_doble) from public.feriados f where f.fecha = p_fecha),
    'turnos', coalesce((
      select jsonb_agg(jsonb_build_object('nombre', e.nombre, 'entrada', to_char(t.entrada, 'HH24:MI'), 'salida', to_char(t.salida, 'HH24:MI'),
               'horas', public._horas_turno_vivo(t.fecha, t.entrada, t.salida, t.tipo, t.horas_licencia), 'tipo', t.tipo, 'nota', t.nota) order by t.entrada nulls last, e.nombre)
        from public.horas_turnos t join public.empleados e on e.id = t.empleado_id
       where t.fecha = p_fecha and (t.tipo = 'trabajo' or v_admin) and (public._es_gestor() or t.empleado_id = v_emp)), '[]'::jsonb));
end;
$$;
grant execute on function public.horas_dia(date) to authenticated;

-- ===== sueldos =====
drop function if exists public._sueldos_calculo(date);
create or replace function public._sueldos_calculo(p_mes date)
returns table (empleado_id uuid, nombre text, h_normales numeric, h_feriado numeric, h_licencia numeric, valor_hora numeric,
               bruto numeric, aguinaldo numeric, vacaciones numeric, bono numeric, descuentos numeric, neto numeric, transferencia numeric, efectivo numeric, nota text, abiertos int)
language sql stable security definer set search_path = public as $$
  with ini as (select date_trunc('month', p_mes)::date as d),
  h as (
    select t.empleado_id,
           sum(public._horas_turno(t.entrada, t.salida, t.tipo, t.horas_licencia)) filter (where t.tipo = 'trabajo' and not exists (select 1 from public.feriados f where f.fecha = t.fecha and f.paga_doble)) as hn,
           sum(public._horas_turno(t.entrada, t.salida, t.tipo, t.horas_licencia)) filter (where t.tipo = 'trabajo' and exists (select 1 from public.feriados f where f.fecha = t.fecha and f.paga_doble)) as hf,
           sum(public._horas_turno(t.entrada, t.salida, t.tipo, t.horas_licencia)) filter (where t.tipo = 'licencia') as hl,
           count(*) filter (where t.tipo = 'trabajo' and t.salida is null) as ab
      from public.horas_turnos t, ini where t.fecha >= ini.d and t.fecha < ini.d + interval '1 month' group by t.empleado_id
  ),
  base as (
    select e.id, e.nombre, coalesce(h.hn, 0) as hn, coalesce(h.hf, 0) as hf, coalesce(h.hl, 0) as hl, coalesce(h.ab, 0)::int as ab,
           coalesce((select t.valor_hora from public.empleado_tarifas t, ini where t.empleado_id = e.id and t.desde < ini.d + interval '1 month' order by t.desde desc limit 1),
                    (select t.valor_hora from public.empleado_tarifas t where t.empleado_id = e.id order by t.desde asc limit 1)) as vh,
           coalesce(a.aguinaldo, 0) as ag, coalesce(a.vacaciones, 0) as va, coalesce(a.bono, 0) as bo, coalesce(a.descuentos, 0) as de, coalesce(a.transferencia, 0) as tr, a.nota
      from public.empleados e
      left join h on h.empleado_id = e.id
      left join public.sueldos_ajustes a on a.empleado_id = e.id and a.mes = (select d from ini)
     where h.empleado_id is not null or a.empleado_id is not null
  )
  select id, nombre, round(hn, 2), round(hf, 2), round(hl, 2), vh,
         round((hn + hf * 2 + hl) * coalesce(vh, 0)),
         ag, va, bo, de,
         round((hn + hf * 2 + hl) * coalesce(vh, 0)) + ag + va + bo - de,
         tr, round((hn + hf * 2 + hl) * coalesce(vh, 0)) + ag + va + bo - de - tr, nota, ab
    from base order by nombre
$$;

create or replace function public.sueldos_mes(p_mes date)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_ini date := date_trunc('month', p_mes)::date;
begin
  if public.rol_actual() <> 'admin' then raise exception 'Sin permiso'; end if;
  return jsonb_build_object(
    'mes', to_char(v_ini, 'YYYY-MM'),
    'estado', coalesce((select estado from public.sueldos_meses where mes = v_ini), 'abierto'),
    'filas', coalesce((select jsonb_agg(jsonb_build_object('empleado_id', c.empleado_id, 'nombre', c.nombre, 'h_normales', c.h_normales, 'h_feriado', c.h_feriado,
              'h_licencia', c.h_licencia, 'valor_hora', c.valor_hora, 'bruto', c.bruto, 'aguinaldo', c.aguinaldo, 'vacaciones', c.vacaciones, 'bono', c.bono, 'descuentos', c.descuentos,
              'neto', c.neto, 'transferencia', c.transferencia, 'efectivo', c.efectivo, 'nota', c.nota, 'abiertos', c.abiertos) order by c.nombre)
            from public._sueldos_calculo(v_ini) c), '[]'::jsonb));
end;
$$;
grant execute on function public.sueldos_mes(date) to authenticated;

drop function if exists public.sueldos_ajuste_guardar(date, uuid, numeric, numeric, numeric, numeric, text);
create or replace function public.sueldos_ajuste_guardar(p_mes date, p_empleado uuid, p_aguinaldo numeric, p_vacaciones numeric, p_bono numeric, p_descuentos numeric, p_transferencia numeric, p_nota text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_ini date := date_trunc('month', p_mes)::date;
begin
  if public.rol_actual() <> 'admin' then raise exception 'Sin permiso'; end if;
  if public._mes_confirmado(v_ini) then raise exception 'Ese mes ya esta confirmado. Reabrilo para cambiar algo.'; end if;
  insert into public.sueldos_ajustes (empleado_id, mes, aguinaldo, vacaciones, bono, descuentos, transferencia, nota)
    values (p_empleado, v_ini, coalesce(p_aguinaldo, 0), coalesce(p_vacaciones, 0), coalesce(p_bono, 0), coalesce(p_descuentos, 0), coalesce(p_transferencia, 0), nullif(trim(coalesce(p_nota, '')), ''))
    on conflict (empleado_id, mes) do update set aguinaldo = excluded.aguinaldo, vacaciones = excluded.vacaciones, bono = excluded.bono, descuentos = excluded.descuentos,
        transferencia = excluded.transferencia, nota = excluded.nota;
  return jsonb_build_object('ok', true);
end;
$$;
grant execute on function public.sueldos_ajuste_guardar(date, uuid, numeric, numeric, numeric, numeric, numeric, text) to authenticated;

-- Aguinaldo sugerido (solo junio y diciembre): 50% del mejor sueldo mensual (por horas) del semestre, proporcional a los dias desde que entro
create or replace function public.sueldos_aguinaldo_sugerido(p_mes date)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_ini date := date_trunc('month', p_mes)::date; v_sem_ini date; v_sem_fin date; v_total int;
begin
  if public.rol_actual() <> 'admin' then raise exception 'Sin permiso'; end if;
  if extract(month from v_ini) not in (6, 12) then raise exception 'El aguinaldo se calcula solo en junio y diciembre'; end if;
  v_sem_ini := case when extract(month from v_ini) = 6 then make_date(extract(year from v_ini)::int, 1, 1) else make_date(extract(year from v_ini)::int, 7, 1) end;
  v_sem_fin := (v_sem_ini + interval '6 months - 1 day')::date;
  v_total := v_sem_fin - v_sem_ini + 1;
  return coalesce((
    select jsonb_agg(jsonb_build_object('empleado_id', z.id, 'nombre', z.nombre, 'mejor_mes', z.mejor, 'dias', z.dias, 'dias_semestre', v_total,
              'aguinaldo', round(z.mejor / 2.0 * z.dias / v_total)) order by z.nombre)
      from (
        select e.id, e.nombre,
               (select coalesce(max(c.bruto), 0) from generate_series(v_sem_ini, v_sem_fin, interval '1 month') m(d), lateral public._sueldos_calculo(m.d::date) c where c.empleado_id = e.id) as mejor,
               v_sem_fin - greatest(v_sem_ini, coalesce(e.fecha_ingreso, (select min(t.fecha) from public.horas_turnos t where t.empleado_id = e.id and t.fecha between v_sem_ini and v_sem_fin), v_sem_ini)) + 1 as dias
          from public.empleados e
         where exists (select 1 from public.horas_turnos t where t.empleado_id = e.id and t.fecha >= v_ini and t.fecha < v_ini + interval '1 month')
      ) z), '[]'::jsonb);
end;
$$;
grant execute on function public.sueldos_aguinaldo_sugerido(date) to authenticated;

-- Confirmar el mes: PERSONAL (sueldo, bono, descuentos) y AGUINALDOS, VACACIONES aparte; cada uno en efectivo y por banco
create or replace function public.sueldos_confirmar_mes(p_mes date)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_ini date := date_trunc('month', p_mes)::date;
  v_fin date := (date_trunc('month', p_mes) + interval '1 month - 1 day')::date;
  v_lote text := to_char(date_trunc('month', p_mes), 'YYYY-MM');
  v_mes_txt text := to_char(date_trunc('month', p_mes), 'MM/YYYY');
  r record; v_su numeric; v_ag numeric; v_tot numeric; v_tr_ag numeric; v_tr_su numeric;
  s_ef numeric := 0; s_ba numeric := 0; a_ef numeric := 0; a_ba numeric := 0;
  v_n int := 0; v_ab int; v_sin_tarifa text; v_neg text;
begin
  if public.rol_actual() <> 'admin' then raise exception 'Sin permiso'; end if;
  if public._mes_confirmado(v_ini) then raise exception 'Ese mes ya esta confirmado'; end if;
  select coalesce(sum(abiertos), 0) into v_ab from public._sueldos_calculo(v_ini);
  if v_ab > 0 then raise exception 'Hay % turnos con entrada sin salida. Corregilos antes de confirmar el mes.', v_ab; end if;
  select string_agg(nombre, ', ') into v_sin_tarifa from public._sueldos_calculo(v_ini) where valor_hora is null and (h_normales + h_feriado + h_licencia) > 0;
  if v_sin_tarifa is not null then raise exception 'Falta el valor hora de: %', v_sin_tarifa; end if;
  select string_agg(nombre, ', ') into v_neg from public._sueldos_calculo(v_ini) where transferencia > neto or transferencia < 0;
  if v_neg is not null then raise exception 'La transferencia no puede ser mayor al total a pagar (revisa: %)', v_neg; end if;

  for r in select * from public._sueldos_calculo(v_ini) where neto <> 0 loop
    v_n := v_n + 1;
    v_ag := r.aguinaldo + r.vacaciones;
    v_su := r.neto - v_ag;
    v_tot := r.neto;
    v_tr_ag := case when v_tot = 0 then 0 else round(r.transferencia * v_ag / v_tot, 2) end;
    v_tr_su := r.transferencia - v_tr_ag;
    s_ba := s_ba + v_tr_su; s_ef := s_ef + (v_su - v_tr_su);
    a_ba := a_ba + v_tr_ag; a_ef := a_ef + (v_ag - v_tr_ag);
  end loop;
  if v_n = 0 then raise exception 'No hay sueldos para confirmar en ese mes'; end if;
  if s_ef < 0 or s_ba < 0 or a_ef < 0 or a_ba < 0 then raise exception 'Hay montos negativos (descuentos mayores al sueldo). Revisalos.'; end if;

  if s_ef > 0 then
    insert into public.ingresos_egresos (fecha, concepto, monto, forma, estado_pago, medio_pago, fecha_pago, origen, usuario_id, observaciones, lote_importacion)
      values (v_fin, 'PERSONAL', s_ef, 'egreso_efectivo', 'pagado', 'efectivo', v_fin, 'manual', auth.uid(), 'Sueldos de ' || v_mes_txt || ' (' || v_n || ' personas), parte en efectivo', v_lote);
  end if;
  if s_ba > 0 then
    insert into public.ingresos_egresos (fecha, concepto, monto, forma, estado_pago, medio_pago, fecha_pago, origen, usuario_id, observaciones, lote_importacion)
      values (v_fin, 'PERSONAL', s_ba, 'egreso_banco', 'pagado', 'banco', v_fin, 'manual', auth.uid(), 'Sueldos de ' || v_mes_txt || ' (' || v_n || ' personas), parte por transferencia', v_lote);
  end if;
  if a_ef > 0 then
    insert into public.ingresos_egresos (fecha, concepto, monto, forma, estado_pago, medio_pago, fecha_pago, origen, usuario_id, observaciones, lote_importacion)
      values (v_fin, 'AGUINALDOS, VACACIONES', a_ef, 'egreso_efectivo', 'pagado', 'efectivo', v_fin, 'manual', auth.uid(), 'Aguinaldo y vacaciones de ' || v_mes_txt || ', parte en efectivo', v_lote);
  end if;
  if a_ba > 0 then
    insert into public.ingresos_egresos (fecha, concepto, monto, forma, estado_pago, medio_pago, fecha_pago, origen, usuario_id, observaciones, lote_importacion)
      values (v_fin, 'AGUINALDOS, VACACIONES', a_ba, 'egreso_banco', 'pagado', 'banco', v_fin, 'manual', auth.uid(), 'Aguinaldo y vacaciones de ' || v_mes_txt || ', parte por transferencia', v_lote);
  end if;
  insert into public.sueldos_meses (mes, estado, confirmado_el, confirmado_por) values (v_ini, 'confirmado', now(), auth.uid())
    on conflict (mes) do update set estado = 'confirmado', confirmado_el = now(), confirmado_por = auth.uid();
  return jsonb_build_object('ok', true, 'personal_efectivo', s_ef, 'personal_banco', s_ba, 'aguinaldo_efectivo', a_ef, 'aguinaldo_banco', a_ba);
end;
$$;
grant execute on function public.sueldos_confirmar_mes(date) to authenticated;

create or replace function public.sueldos_reabrir_mes(p_mes date)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_ini date := date_trunc('month', p_mes)::date; v_lote text := to_char(date_trunc('month', p_mes), 'YYYY-MM'); v_txt text := to_char(date_trunc('month', p_mes), 'MM/YYYY');
begin
  if public.rol_actual() <> 'admin' then raise exception 'Sin permiso'; end if;
  delete from public.ingresos_egresos
   where lote_importacion = v_lote and origen = 'manual'
     and ((concepto = 'PERSONAL' and observaciones like 'Sueldos de ' || v_txt || ' (%')
       or (concepto = 'AGUINALDOS, VACACIONES' and observaciones like 'Aguinaldo y vacaciones de ' || v_txt || ',%'));
  update public.sueldos_meses set estado = 'abierto', confirmado_el = null, confirmado_por = null where mes = v_ini;
  return jsonb_build_object('ok', true);
end;
$$;
grant execute on function public.sueldos_reabrir_mes(date) to authenticated;
