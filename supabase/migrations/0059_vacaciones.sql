-- Gata Maula: vacaciones del personal.
--   * Cada persona ve cuantos dias de vacaciones le corresponden este año, cuantos ya se cargaron/tomo, cuantos le quedan y una cuenta regresiva
--   * Manu, Facu y el admin cargan "desde que dia hasta que dia" y ven a todo el equipo
--   * Dias que corresponden (ley de contrato de trabajo): 14 hasta 5 años de antiguedad al 31/12, 21 hasta 10, 28 hasta 20, 35 mas de 20.
--     Si la persona entro en la segunda mitad del año, le corresponde 1 dia cada 20 dias trabajados.
--   * Se cargan las fechas de ingreso que me pasaste (Facu: segunda quincena de enero 2024, Basti: 4/4/2024, Lucas: primer turno 19/2/2026, Rocio: octubre 2026).
-- Correr UNA vez en el SQL Editor (despues de la 0055).

update public.empleados set fecha_ingreso = '2024-01-16' where lower(nombre) = 'facu' and fecha_ingreso is null;
update public.empleados set fecha_ingreso = '2024-04-04' where lower(nombre) = 'basti' and fecha_ingreso is null;
update public.empleados set fecha_ingreso = '2026-02-19' where lower(nombre) = 'lucas' and fecha_ingreso is null;
update public.empleados set fecha_ingreso = '2026-10-01' where translate(lower(nombre), 'í', 'i') = 'rocio' and fecha_ingreso is null;

create table if not exists public.vacaciones (
  id uuid primary key default gen_random_uuid(),
  empleado_id uuid not null references public.empleados(id) on delete cascade,
  desde date not null,
  hasta date not null,
  nota text,
  creado_por uuid references public.usuarios(id),
  created_at timestamptz not null default now(),
  check (hasta >= desde)
);
create index if not exists vacaciones_emp_idx on public.vacaciones (empleado_id, desde);
alter table public.vacaciones enable row level security;

-- dias que le corresponden a una persona en un año
create or replace function public._vac_dias(p_empleado uuid, p_anio int)
returns int
language plpgsql stable security definer set search_path = public as $$
declare e record; v_cierre date := make_date(p_anio, 12, 31); v_base int; v_trab int;
begin
  select fecha_ingreso into e from public.empleados where id = p_empleado;
  if e.fecha_ingreso is null then return null; end if;
  if e.fecha_ingreso > v_cierre then return 0; end if;
  v_base := case when v_cierre <= e.fecha_ingreso + interval '5 years' then 14
                 when v_cierre <= e.fecha_ingreso + interval '10 years' then 21
                 when v_cierre <= e.fecha_ingreso + interval '20 years' then 28 else 35 end;
  if e.fecha_ingreso > make_date(p_anio, 7, 2) then
    select count(distinct fecha) into v_trab from public.horas_turnos
     where empleado_id = p_empleado and tipo = 'trabajo' and fecha >= make_date(p_anio, 1, 1) and fecha <= v_cierre;
    return floor(coalesce(v_trab, 0) / 20.0)::int;
  end if;
  return v_base;
end;
$$;
revoke all on function public._vac_dias(uuid, int) from public;

create or replace function public._vac_resumen(p_empleado uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_hoy date := public.hoy_ar(); v_anio int := extract(year from public.hoy_ar())::int; v_corr int; v_usados int; v_tomados int;
        v_ahora timestamp := now() at time zone 'America/Argentina/Buenos_Aires';
begin
  v_corr := public._vac_dias(p_empleado, v_anio);
  select coalesce(sum(hasta - desde + 1), 0)::int, coalesce(sum(least(hasta, v_hoy - 1) - desde + 1) filter (where desde < v_hoy), 0)::int
    into v_usados, v_tomados from public.vacaciones where empleado_id = p_empleado and extract(year from desde) = v_anio;
  return jsonb_build_object(
    'empleado_id', p_empleado,
    'nombre', (select nombre from public.empleados where id = p_empleado),
    'anio', v_anio,
    'fecha_ingreso', (select fecha_ingreso from public.empleados where id = p_empleado),
    'corresponden', v_corr, 'cargados', v_usados, 'tomados', v_tomados,
    'disponibles', case when v_corr is null then null else v_corr - v_usados end,
    -- la vacacion en curso o la proxima
    'proxima', (select jsonb_build_object('id', v.id, 'desde', v.desde, 'hasta', v.hasta, 'dias', v.hasta - v.desde + 1, 'nota', v.nota, 'en_curso', v.desde <= v_hoy)
                  from public.vacaciones v where v.empleado_id = p_empleado and v.hasta >= v_hoy order by v.desde limit 1),
    'lista', coalesce((select jsonb_agg(jsonb_build_object('id', v.id, 'desde', v.desde, 'hasta', v.hasta, 'dias', v.hasta - v.desde + 1, 'nota', v.nota) order by v.desde desc)
                         from public.vacaciones v where v.empleado_id = p_empleado and extract(year from v.desde) >= v_anio - 1), '[]'::jsonb));
end;
$$;
revoke all on function public._vac_resumen(uuid) from public;

-- lo mio
create or replace function public.vacaciones_mias()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_emp uuid := public._empleado_actual();
begin
  if public.rol_actual() is null then raise exception 'Sin permiso'; end if;
  if v_emp is null then return jsonb_build_object('empleado_id', null); end if;
  return public._vac_resumen(v_emp);
end;
$$;
grant execute on function public.vacaciones_mias() to authenticated;

-- todo el equipo (Manu, Facu, admin)
create or replace function public.vacaciones_equipo()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._es_gestor() then raise exception 'Sin permiso'; end if;
  return coalesce((select jsonb_agg(public._vac_resumen(e.id) order by e.nombre) from public.empleados e where e.activo and not e.casual), '[]'::jsonb);
end;
$$;
grant execute on function public.vacaciones_equipo() to authenticated;

create or replace function public.vacaciones_guardar(p_id uuid, p_empleado uuid, p_desde date, p_hasta date, p_nota text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public._es_gestor() then raise exception 'Sin permiso'; end if;
  if p_empleado is null or p_desde is null or p_hasta is null then raise exception 'Faltan datos'; end if;
  if p_hasta < p_desde then raise exception 'El ultimo dia no puede ser antes del primero'; end if;
  if exists (select 1 from public.vacaciones v where v.empleado_id = p_empleado and v.id is distinct from p_id and v.desde <= p_hasta and v.hasta >= p_desde) then
    raise exception 'Esa persona ya tiene vacaciones cargadas que se pisan con esas fechas';
  end if;
  if p_id is null then
    insert into public.vacaciones (empleado_id, desde, hasta, nota, creado_por) values (p_empleado, p_desde, p_hasta, nullif(trim(coalesce(p_nota, '')), ''), auth.uid());
  else
    update public.vacaciones set empleado_id = p_empleado, desde = p_desde, hasta = p_hasta, nota = nullif(trim(coalesce(p_nota, '')), '') where id = p_id;
  end if;
  return jsonb_build_object('ok', true);
end;
$$;
grant execute on function public.vacaciones_guardar(uuid, uuid, date, date, text) to authenticated;

create or replace function public.vacaciones_borrar(p_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public._es_gestor() then raise exception 'Sin permiso'; end if;
  delete from public.vacaciones where id = p_id;
  return jsonb_build_object('ok', true);
end;
$$;
grant execute on function public.vacaciones_borrar(uuid) to authenticated;

select e.nombre, e.fecha_ingreso, public._vac_dias(e.id, extract(year from public.hoy_ar())::int) as dias_este_anio
  from public.empleados e where e.activo order by e.nombre;
