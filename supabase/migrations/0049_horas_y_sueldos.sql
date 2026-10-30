-- Gata Maula: horas del personal y sueldos.
--   * Cada persona marca entrada y salida (con la hora actual) y ve sus turnos y el total de horas del mes.
--   * Manu, Facu y el admin cargan o corrigen horas de cualquiera y agregan personal casual. Solo el admin ve valores hora, sueldos y licencias.
--   * Sueldos por mes: horas normales + horas en feriado (se pagan doble) + horas de licencia (certificados), mas aguinaldo, bono y descuentos.
--   * Al confirmar el mes se carga solo en Ingresos y egresos una fila PERSONAL en efectivo y otra por banco, con fecha del ultimo dia del mes.
-- Correr UNA vez en el SQL Editor.

create table if not exists public.empleados (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  usuario_id uuid unique references public.usuarios(id) on delete set null,
  casual boolean not null default false,
  activo boolean not null default true,
  created_at timestamptz not null default now()
);
create unique index if not exists empleados_nombre_idx on public.empleados (lower(nombre));

create table if not exists public.empleado_tarifas (
  empleado_id uuid not null references public.empleados(id) on delete cascade,
  desde date not null,
  valor_hora numeric(12,2) not null check (valor_hora >= 0),
  primary key (empleado_id, desde)
);

create table if not exists public.horas_turnos (
  id uuid primary key default gen_random_uuid(),
  empleado_id uuid not null references public.empleados(id) on delete cascade,
  fecha date not null,
  entrada time,
  salida time,
  tipo text not null default 'trabajo' check (tipo in ('trabajo', 'licencia')),
  horas_licencia numeric(6,2),
  nota text,
  creado_por uuid references public.usuarios(id),
  created_at timestamptz not null default now(),
  check (tipo = 'licencia' or entrada is not null)
);
create index if not exists horas_turnos_emp_fecha_idx on public.horas_turnos (empleado_id, fecha);
create index if not exists horas_turnos_fecha_idx on public.horas_turnos (fecha);

create table if not exists public.feriados (
  fecha date primary key,
  nombre text not null
);

create table if not exists public.sueldos_ajustes (
  empleado_id uuid not null references public.empleados(id) on delete cascade,
  mes date not null,
  aguinaldo numeric(14,2) not null default 0,
  bono numeric(14,2) not null default 0,
  descuentos numeric(14,2) not null default 0,
  transferencia numeric(14,2) not null default 0,
  nota text,
  primary key (empleado_id, mes)
);

create table if not exists public.sueldos_meses (
  mes date primary key,
  estado text not null default 'abierto' check (estado in ('abierto', 'confirmado')),
  confirmado_el timestamptz,
  confirmado_por uuid references public.usuarios(id)
);

-- Todo se maneja por funciones; las tablas no se leen ni escriben directo desde la app.
alter table public.empleados enable row level security;
alter table public.empleado_tarifas enable row level security;
alter table public.horas_turnos enable row level security;
alter table public.feriados enable row level security;
alter table public.sueldos_ajustes enable row level security;
alter table public.sueldos_meses enable row level security;

-- ===== ayudas internas =====
create or replace function public._horas_turno(p_entrada time, p_salida time, p_tipo text, p_lic numeric)
returns numeric language sql immutable as $$
  select case when p_tipo = 'licencia' then coalesce(p_lic, 0)
              when p_salida is null or p_entrada is null then 0
              else round(extract(epoch from ((p_salida - p_entrada) + case when p_salida < p_entrada then interval '24 hours' else interval '0 hours' end)) / 3600.0, 4) end
$$;

create or replace function public._mes_confirmado(p_fecha date)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.sueldos_meses where mes = date_trunc('month', p_fecha)::date and estado = 'confirmado')
$$;

create or replace function public._empleado_actual()
returns uuid language sql stable security definer set search_path = public as $$
  select id from public.empleados where usuario_id = auth.uid() limit 1
$$;

create or replace function public._es_gestor()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.rol_actual() in ('admin', 'encargado'), false)
$$;

-- ===== marcar entrada y salida =====
create or replace function public.horas_estado()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_emp record; v_ab record;
begin
  if public.rol_actual() is null then raise exception 'Sin permiso'; end if;
  select id, nombre into v_emp from public.empleados where usuario_id = auth.uid() limit 1;
  if v_emp.id is null then return jsonb_build_object('empleado', null); end if;
  select id, fecha, entrada into v_ab from public.horas_turnos
   where empleado_id = v_emp.id and tipo = 'trabajo' and salida is null order by fecha desc, entrada desc limit 1;
  return jsonb_build_object('empleado', jsonb_build_object('id', v_emp.id, 'nombre', v_emp.nombre),
                            'abierto', case when v_ab.id is null then null else jsonb_build_object('id', v_ab.id, 'fecha', v_ab.fecha, 'entrada', to_char(v_ab.entrada, 'HH24:MI')) end);
end;
$$;
grant execute on function public.horas_estado() to authenticated;

create or replace function public.horas_fichar(p_tipo text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_emp uuid := public._empleado_actual();
  v_ahora timestamp := now() at time zone 'America/Argentina/Buenos_Aires';
  v_ab record;
begin
  if public.rol_actual() is null then raise exception 'Sin permiso'; end if;
  if v_emp is null then raise exception 'Tu usuario todavia no esta en la lista de personal. Avisale a Manu, Facu o Lautaro.'; end if;
  if p_tipo = 'entrada' then
    if exists (select 1 from public.horas_turnos where empleado_id = v_emp and tipo = 'trabajo' and salida is null) then
      raise exception 'Ya marcaste la entrada. Marca la salida primero.';
    end if;
    if public._mes_confirmado(v_ahora::date) then raise exception 'El mes ya esta cerrado'; end if;
    insert into public.horas_turnos (empleado_id, fecha, entrada, creado_por) values (v_emp, v_ahora::date, date_trunc('minute', v_ahora)::time, auth.uid());
    return jsonb_build_object('ok', true, 'hora', to_char(v_ahora, 'HH24:MI'));
  elsif p_tipo = 'salida' then
    select * into v_ab from public.horas_turnos where empleado_id = v_emp and tipo = 'trabajo' and salida is null order by fecha desc, entrada desc limit 1;
    if v_ab.id is null then raise exception 'No hay una entrada abierta. Pedile a un encargado que cargue el turno.'; end if;
    if v_ahora - (v_ab.fecha + v_ab.entrada) > interval '20 hours' then
      raise exception 'La entrada abierta es de hace mas de 20 horas. Pedile a un encargado que te corrija el turno.';
    end if;
    update public.horas_turnos set salida = date_trunc('minute', v_ahora)::time where id = v_ab.id;
    return jsonb_build_object('ok', true, 'hora', to_char(v_ahora, 'HH24:MI'));
  end if;
  raise exception 'Accion invalida';
end;
$$;
grant execute on function public.horas_fichar(text) to authenticated;

-- ===== ver turnos de un mes =====
create or replace function public.horas_mes(p_mes date, p_empleado uuid default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_emp uuid; v_ini date := date_trunc('month', p_mes)::date; v_admin boolean := public.rol_actual() = 'admin';
begin
  if public.rol_actual() is null then raise exception 'Sin permiso'; end if;
  v_emp := coalesce(p_empleado, public._empleado_actual());
  if v_emp is null then return jsonb_build_object('turnos', '[]'::jsonb, 'total', 0); end if;
  if v_emp is distinct from public._empleado_actual() and not public._es_gestor() then raise exception 'Sin permiso'; end if;
  return jsonb_build_object(
    'empleado', (select nombre from public.empleados where id = v_emp),
    'cerrado', public._mes_confirmado(v_ini),
    'total', coalesce((select sum(public._horas_turno(entrada, salida, tipo, horas_licencia)) from public.horas_turnos
                        where empleado_id = v_emp and fecha >= v_ini and fecha < v_ini + interval '1 month' and (tipo = 'trabajo' or v_admin)), 0),
    'turnos', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'fecha', t.fecha, 'entrada', to_char(t.entrada, 'HH24:MI'), 'salida', to_char(t.salida, 'HH24:MI'),
                              'horas', public._horas_turno(t.entrada, t.salida, t.tipo, t.horas_licencia), 'tipo', t.tipo, 'nota', t.nota,
                              'feriado', exists (select 1 from public.feriados f where f.fecha = t.fecha), 'abierto', (t.tipo = 'trabajo' and t.salida is null)) order by t.fecha desc, t.entrada desc nulls last)
                          from public.horas_turnos t
                         where t.empleado_id = v_emp and t.fecha >= v_ini and t.fecha < v_ini + interval '1 month' and (t.tipo = 'trabajo' or v_admin)), '[]'::jsonb));
end;
$$;
grant execute on function public.horas_mes(date, uuid) to authenticated;

-- ===== equipo (Manu, Facu, admin) =====
create or replace function public.horas_equipo(p_mes date)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_ini date := date_trunc('month', p_mes)::date; v_admin boolean := public.rol_actual() = 'admin';
begin
  if not public._es_gestor() then raise exception 'Sin permiso'; end if;
  return jsonb_build_object('cerrado', public._mes_confirmado(v_ini), 'personas', coalesce((
    select jsonb_agg(jsonb_build_object('id', e.id, 'nombre', e.nombre, 'casual', e.casual, 'activo', e.activo,
             'turnos', coalesce(h.n, 0), 'abiertos', coalesce(h.ab, 0), 'horas', round(coalesce(h.horas, 0), 2)) order by e.activo desc, e.nombre)
      from public.empleados e
      left join (select empleado_id, count(*) as n, count(*) filter (where tipo = 'trabajo' and salida is null) as ab,
                        sum(public._horas_turno(entrada, salida, tipo, horas_licencia)) filter (where tipo = 'trabajo' or v_admin) as horas
                   from public.horas_turnos where fecha >= v_ini and fecha < v_ini + interval '1 month' group by empleado_id) h on h.empleado_id = e.id
     where e.activo or h.n > 0), '[]'::jsonb));
end;
$$;
grant execute on function public.horas_equipo(date) to authenticated;

create or replace function public.horas_guardar(
  p_id uuid, p_empleado uuid, p_fecha date, p_entrada time, p_salida time, p_nota text default null,
  p_tipo text default 'trabajo', p_horas_licencia numeric default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_old date;
begin
  if not public._es_gestor() then raise exception 'Sin permiso'; end if;
  if p_tipo = 'licencia' and public.rol_actual() <> 'admin' then raise exception 'Solo el administrador carga licencias'; end if;
  if p_tipo not in ('trabajo', 'licencia') then raise exception 'Tipo invalido'; end if;
  if p_empleado is null or p_fecha is null then raise exception 'Falta la persona o la fecha'; end if;
  if p_tipo = 'trabajo' and p_entrada is null then raise exception 'Falta la hora de entrada'; end if;
  if p_tipo = 'licencia' and coalesce(p_horas_licencia, 0) <= 0 then raise exception 'Poné las horas de la licencia'; end if;
  if public._mes_confirmado(p_fecha) then raise exception 'Ese mes ya esta cerrado'; end if;
  if p_id is null then
    insert into public.horas_turnos (empleado_id, fecha, entrada, salida, tipo, horas_licencia, nota, creado_por)
      values (p_empleado, p_fecha, p_entrada, p_salida, p_tipo, case when p_tipo = 'licencia' then p_horas_licencia end, nullif(trim(coalesce(p_nota, '')), ''), auth.uid());
  else
    select fecha into v_old from public.horas_turnos where id = p_id;
    if v_old is null then raise exception 'No encontre el turno'; end if;
    if public._mes_confirmado(v_old) then raise exception 'Ese mes ya esta cerrado'; end if;
    update public.horas_turnos set empleado_id = p_empleado, fecha = p_fecha, entrada = p_entrada, salida = p_salida, tipo = p_tipo,
        horas_licencia = case when p_tipo = 'licencia' then p_horas_licencia end, nota = nullif(trim(coalesce(p_nota, '')), '')
      where id = p_id;
  end if;
  return jsonb_build_object('ok', true);
end;
$$;
grant execute on function public.horas_guardar(uuid, uuid, date, time, time, text, text, numeric) to authenticated;

create or replace function public.horas_borrar(p_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_fecha date;
begin
  if not public._es_gestor() then raise exception 'Sin permiso'; end if;
  select fecha into v_fecha from public.horas_turnos where id = p_id;
  if v_fecha is null then return jsonb_build_object('ok', true); end if;
  if public._mes_confirmado(v_fecha) then raise exception 'Ese mes ya esta cerrado'; end if;
  delete from public.horas_turnos where id = p_id;
  return jsonb_build_object('ok', true);
end;
$$;
grant execute on function public.horas_borrar(uuid) to authenticated;

-- ===== personal =====
create or replace function public.empleados_listar()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_admin boolean := public.rol_actual() = 'admin';
begin
  if not public._es_gestor() then raise exception 'Sin permiso'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'nombre', e.nombre, 'casual', e.casual, 'activo', e.activo,
            'usuario_id', e.usuario_id, 'usuario', u.nombre,
            'valor_hora', case when v_admin then (select t.valor_hora from public.empleado_tarifas t where t.empleado_id = e.id order by t.desde desc limit 1) end,
            'tarifa_desde', case when v_admin then (select t.desde from public.empleado_tarifas t where t.empleado_id = e.id order by t.desde desc limit 1) end)
          order by e.activo desc, e.nombre)
        from public.empleados e left join public.usuarios u on u.id = e.usuario_id), '[]'::jsonb);
end;
$$;
grant execute on function public.empleados_listar() to authenticated;

create or replace function public.empleado_guardar(p_id uuid, p_nombre text, p_casual boolean, p_activo boolean, p_usuario uuid default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id uuid := p_id; v_admin boolean := public.rol_actual() = 'admin';
begin
  if not public._es_gestor() then raise exception 'Sin permiso'; end if;
  if nullif(trim(coalesce(p_nombre, '')), '') is null then raise exception 'Falta el nombre'; end if;
  if v_id is null then
    insert into public.empleados (nombre, casual, activo, usuario_id) values (trim(p_nombre), coalesce(p_casual, false), coalesce(p_activo, true), case when v_admin then p_usuario end)
      returning id into v_id;
  else
    update public.empleados set nombre = trim(p_nombre), casual = coalesce(p_casual, casual), activo = coalesce(p_activo, activo),
        usuario_id = case when v_admin then p_usuario else usuario_id end
      where id = v_id;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id);
exception when unique_violation then
  raise exception 'Ya hay una persona con ese nombre o ese usuario ya esta asignado a otra persona';
end;
$$;
grant execute on function public.empleado_guardar(uuid, text, boolean, boolean, uuid) to authenticated;

create or replace function public.empleado_tarifa_guardar(p_empleado uuid, p_desde date, p_valor numeric)
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if public.rol_actual() <> 'admin' then raise exception 'Sin permiso'; end if;
  if p_valor is null or p_valor < 0 then raise exception 'Valor invalido'; end if;
  insert into public.empleado_tarifas (empleado_id, desde, valor_hora) values (p_empleado, coalesce(p_desde, public.hoy_ar()), p_valor)
    on conflict (empleado_id, desde) do update set valor_hora = excluded.valor_hora;
  return jsonb_build_object('ok', true);
end;
$$;
grant execute on function public.empleado_tarifa_guardar(uuid, date, numeric) to authenticated;

-- ===== feriados (se pagan doble) =====
create or replace function public.feriados_listar(p_anio int)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._es_gestor() then raise exception 'Sin permiso'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('fecha', fecha, 'nombre', nombre) order by fecha) from public.feriados where extract(year from fecha) = p_anio), '[]'::jsonb);
end;
$$;
grant execute on function public.feriados_listar(int) to authenticated;

create or replace function public.feriado_guardar(p_fecha date, p_nombre text)
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if public.rol_actual() <> 'admin' then raise exception 'Sin permiso'; end if;
  insert into public.feriados (fecha, nombre) values (p_fecha, coalesce(nullif(trim(coalesce(p_nombre, '')), ''), 'Feriado'))
    on conflict (fecha) do update set nombre = excluded.nombre;
  return jsonb_build_object('ok', true);
end;
$$;
grant execute on function public.feriado_guardar(date, text) to authenticated;

create or replace function public.feriado_borrar(p_fecha date)
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if public.rol_actual() <> 'admin' then raise exception 'Sin permiso'; end if;
  delete from public.feriados where fecha = p_fecha;
  return jsonb_build_object('ok', true);
end;
$$;
grant execute on function public.feriado_borrar(date) to authenticated;

-- ===== sueldos del mes (solo admin) =====
create or replace function public._sueldos_calculo(p_mes date)
returns table (empleado_id uuid, nombre text, h_normales numeric, h_feriado numeric, h_licencia numeric, valor_hora numeric,
               bruto numeric, aguinaldo numeric, bono numeric, descuentos numeric, neto numeric, transferencia numeric, efectivo numeric, nota text, abiertos int)
language sql stable security definer set search_path = public as $$
  with ini as (select date_trunc('month', p_mes)::date as d),
  h as (
    select t.empleado_id,
           sum(public._horas_turno(t.entrada, t.salida, t.tipo, t.horas_licencia)) filter (where t.tipo = 'trabajo' and not exists (select 1 from public.feriados f where f.fecha = t.fecha)) as hn,
           sum(public._horas_turno(t.entrada, t.salida, t.tipo, t.horas_licencia)) filter (where t.tipo = 'trabajo' and exists (select 1 from public.feriados f where f.fecha = t.fecha)) as hf,
           sum(public._horas_turno(t.entrada, t.salida, t.tipo, t.horas_licencia)) filter (where t.tipo = 'licencia') as hl,
           count(*) filter (where t.tipo = 'trabajo' and t.salida is null) as ab
      from public.horas_turnos t, ini where t.fecha >= ini.d and t.fecha < ini.d + interval '1 month' group by t.empleado_id
  ),
  base as (
    select e.id, e.nombre, coalesce(h.hn, 0) as hn, coalesce(h.hf, 0) as hf, coalesce(h.hl, 0) as hl, coalesce(h.ab, 0)::int as ab,
           (select t.valor_hora from public.empleado_tarifas t, ini where t.empleado_id = e.id and t.desde < ini.d + interval '1 month' order by t.desde desc limit 1) as vh,
           coalesce(a.aguinaldo, 0) as ag, coalesce(a.bono, 0) as bo, coalesce(a.descuentos, 0) as de, coalesce(a.transferencia, 0) as tr, a.nota
      from public.empleados e
      left join h on h.empleado_id = e.id
      left join public.sueldos_ajustes a on a.empleado_id = e.id and a.mes = (select d from ini)
     where h.empleado_id is not null or a.empleado_id is not null
  )
  select id, nombre, round(hn, 2), round(hf, 2), round(hl, 2), vh,
         round((hn + hf * 2 + hl) * coalesce(vh, 0)),
         ag, bo, de,
         round((hn + hf * 2 + hl) * coalesce(vh, 0)) + ag + bo - de,
         tr, round((hn + hf * 2 + hl) * coalesce(vh, 0)) + ag + bo - de - tr, nota, ab
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
              'h_licencia', c.h_licencia, 'valor_hora', c.valor_hora, 'bruto', c.bruto, 'aguinaldo', c.aguinaldo, 'bono', c.bono, 'descuentos', c.descuentos,
              'neto', c.neto, 'transferencia', c.transferencia, 'efectivo', c.efectivo, 'nota', c.nota, 'abiertos', c.abiertos) order by c.nombre)
            from public._sueldos_calculo(v_ini) c), '[]'::jsonb));
end;
$$;
grant execute on function public.sueldos_mes(date) to authenticated;

create or replace function public.sueldos_ajuste_guardar(p_mes date, p_empleado uuid, p_aguinaldo numeric, p_bono numeric, p_descuentos numeric, p_transferencia numeric, p_nota text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_ini date := date_trunc('month', p_mes)::date;
begin
  if public.rol_actual() <> 'admin' then raise exception 'Sin permiso'; end if;
  if public._mes_confirmado(v_ini) then raise exception 'Ese mes ya esta confirmado. Reabrilo para cambiar algo.'; end if;
  insert into public.sueldos_ajustes (empleado_id, mes, aguinaldo, bono, descuentos, transferencia, nota)
    values (p_empleado, v_ini, coalesce(p_aguinaldo, 0), coalesce(p_bono, 0), coalesce(p_descuentos, 0), coalesce(p_transferencia, 0), nullif(trim(coalesce(p_nota, '')), ''))
    on conflict (empleado_id, mes) do update set aguinaldo = excluded.aguinaldo, bono = excluded.bono, descuentos = excluded.descuentos,
        transferencia = excluded.transferencia, nota = excluded.nota;
  return jsonb_build_object('ok', true);
end;
$$;
grant execute on function public.sueldos_ajuste_guardar(date, uuid, numeric, numeric, numeric, numeric, text) to authenticated;

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
  delete from public.ingresos_egresos where lote_importacion = v_lote and concepto = 'PERSONAL' and origen = 'manual' and observaciones like 'Sueldos de ' || to_char(v_ini, 'MM/YYYY') || ' (%';
  update public.sueldos_meses set estado = 'abierto', confirmado_el = null, confirmado_por = null where mes = v_ini;
  return jsonb_build_object('ok', true);
end;
$$;
grant execute on function public.sueldos_reabrir_mes(date) to authenticated;

-- ===== datos iniciales =====
-- Personal: los que ya tienen usuario en la app (se vinculan por nombre) y los que anotaron horas en octubre y septiembre 2026
insert into public.empleados (nombre, usuario_id, casual, activo)
select initcap(u.nombre), u.id, false, true from public.usuarios u
 where lower(u.nombre) in ('manu', 'facu', 'basti', 'lucas')
on conflict do nothing;
insert into public.empleados (nombre, casual, activo) values ('Rocío', false, true), ('Alex', true, true), ('Lazaro', false, false), ('Alan', true, false)
on conflict do nothing;

-- Feriados que quedan del 2026 (se pueden editar en Sueldos)
insert into public.feriados (fecha, nombre) values
  ('2026-10-12', 'Día del Respeto a la Diversidad Cultural'),
  ('2026-11-23', 'Día de la Soberanía Nacional (trasladado)'),
  ('2026-12-08', 'Inmaculada Concepción de María'),
  ('2026-12-25', 'Navidad')
on conflict do nothing;

select e.nombre, e.casual, e.activo, u.nombre as usuario from public.empleados e left join public.usuarios u on u.id = e.usuario_id order by e.activo desc, e.nombre;
