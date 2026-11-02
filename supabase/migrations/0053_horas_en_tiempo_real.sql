-- Gata Maula: las horas del mes se ven en tiempo real.
--   * Si la persona tiene un turno abierto (marco la entrada y todavia no la salida), sus horas cuentan hasta este momento.
--   * Vale para "Mis horas" y para "Horas del equipo". La liquidacion de sueldos NO cuenta turnos abiertos (hay que cerrarlos antes de confirmar el mes).
-- Correr UNA vez en el SQL Editor (despues de la 0049).

create or replace function public._horas_turno_vivo(p_fecha date, p_entrada time, p_salida time, p_tipo text, p_lic numeric)
returns numeric language sql stable as $$
  select case
    when p_tipo = 'trabajo' and p_salida is null and p_entrada is not null then
      least(24, greatest(0, round(extract(epoch from ((now() at time zone 'America/Argentina/Buenos_Aires') - (p_fecha + p_entrada))) / 3600.0, 4)))
    else public._horas_turno(p_entrada, p_salida, p_tipo, p_lic) end
$$;

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
    'total', coalesce((select sum(public._horas_turno_vivo(fecha, entrada, salida, tipo, horas_licencia)) from public.horas_turnos
                        where empleado_id = v_emp and fecha >= v_ini and fecha < v_ini + interval '1 month' and (tipo = 'trabajo' or v_admin)), 0),
    'turnos', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'fecha', t.fecha, 'entrada', to_char(t.entrada, 'HH24:MI'), 'salida', to_char(t.salida, 'HH24:MI'),
                              'horas', public._horas_turno_vivo(t.fecha, t.entrada, t.salida, t.tipo, t.horas_licencia), 'tipo', t.tipo, 'nota', t.nota,
                              'feriado', exists (select 1 from public.feriados f where f.fecha = t.fecha), 'abierto', (t.tipo = 'trabajo' and t.salida is null)) order by t.fecha desc, t.entrada desc nulls last)
                          from public.horas_turnos t
                         where t.empleado_id = v_emp and t.fecha >= v_ini and t.fecha < v_ini + interval '1 month' and (t.tipo = 'trabajo' or v_admin)), '[]'::jsonb));
end;
$$;
grant execute on function public.horas_mes(date, uuid) to authenticated;

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
                        sum(public._horas_turno_vivo(fecha, entrada, salida, tipo, horas_licencia)) filter (where tipo = 'trabajo' or v_admin) as horas
                   from public.horas_turnos where fecha >= v_ini and fecha < v_ini + interval '1 month' group by empleado_id) h on h.empleado_id = e.id
     where e.activo or h.n > 0), '[]'::jsonb));
end;
$$;
grant execute on function public.horas_equipo(date) to authenticated;
