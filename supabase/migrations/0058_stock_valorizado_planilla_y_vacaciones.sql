-- Gata Maula: stock valorizado igual que tu planilla (hoja TOTAL DE MERCADERIA), cierre de mes el dia 1 a las 3 de la madrugada, y vacaciones sugeridas.
--   * IVA del stock: x1,21 solo en vermut, fiambres y quesos. Bebidas, kutsi, cocina y panes valen al precio sin multiplicar (como tu planilla).
--     Cada producto puede tener su propio factor (insumos.stock_iva), por ejemplo los vermuts que en tu planilla no llevan IVA.
--   * Cierre de mes: el stock final de un mes es la foto del dia 1 del mes siguiente (a las 3 de la madrugada) y esa misma foto es el stock inicial del mes siguiente.
--     (El horario de la foto automatica se cambia en vercel.json: 06:00 UTC = 03:00 de Argentina.)
--   * Vacaciones: dias que corresponden por antiguedad (ley) y monto sugerido = valor hora x horas promedio por dia x dias.
-- Correr UNA vez en el SQL Editor.

alter table public.insumos add column if not exists stock_iva numeric(5,2);

create or replace function public._stock_valorizado_calc()
returns jsonb
language sql stable security definer set search_path = public as $$
  with x as (
    select i.subcategoria::text as rubro,
           sum(greatest(s.cantidad_actual, 0) * coalesce(i.precio_costo_kg, 0)
               * coalesce(i.stock_iva, case when i.subcategoria::text in ('vermut', 'fiambres', 'quesos') then 1.21 else 1.0 end)) as v,
           count(*) filter (where coalesce(i.precio_costo_kg, 0) = 0 and s.cantidad_actual > 0) as sp
      from public.stock s join public.insumos i on i.id = s.insumo_id
     group by 1
  )
  select jsonb_build_object(
    'total', coalesce((select round(sum(v), 2) from x where rubro not in ('limpieza', 'descartables')), 0),
    'por_rubro', coalesce((select jsonb_object_agg(rubro, round(v)) from x where rubro not in ('limpieza', 'descartables')), '{}'::jsonb),
    'aparte', coalesce((select jsonb_object_agg(rubro, round(v)) from x where rubro in ('limpieza', 'descartables')), '{}'::jsonb),
    'sin_precio', coalesce((select sum(sp) from x where rubro not in ('limpieza', 'descartables')), 0)
  )
$$;
revoke all on function public._stock_valorizado_calc() from public;

create or replace function public.stock_valorizado_eerr(p_desde date, p_hasta date)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_hoy jsonb; v_mes_actual date := date_trunc('month', public.hoy_ar())::date;
begin
  if public.rol_actual() <> 'admin' then raise exception 'Sin permiso'; end if;
  v_hoy := public._stock_valorizado_calc();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'mes', to_char(m.mes, 'YYYY-MM'),
      -- final: la foto del dia 1 del mes siguiente; si todavia no existe, la ultima del mes; si es el mes en curso, el stock de hoy
      'fin', case when m.mes = v_mes_actual then (v_hoy->>'total')::numeric
                  else coalesce((select d.total from public.stock_valorizado_diario d where d.dia = (m.mes + interval '1 month')::date),
                                (select d.total from public.stock_valorizado_diario d where d.dia >= m.mes and d.dia < (m.mes + interval '1 month')::date order by d.dia desc limit 1)) end,
      -- inicial: la foto del dia 1 del mes; si no existe, la ultima del mes anterior
      'inicio', coalesce((select d.total from public.stock_valorizado_diario d where d.dia = m.mes),
                         (select d.total from public.stock_valorizado_diario d where d.dia >= (m.mes - interval '1 month')::date and d.dia < m.mes order by d.dia desc limit 1)),
      'fin_es_hoy', m.mes = v_mes_actual
    ) order by m.mes)
    from (select generate_series(date_trunc('month', p_desde)::date, date_trunc('month', p_hasta)::date, interval '1 month')::date as mes) m
  ), '[]'::jsonb);
end;
$$;
grant execute on function public.stock_valorizado_eerr(date, date) to authenticated;

-- ===== vacaciones =====
update public.empleados set fecha_ingreso = '2022-03-07' where lower(nombre) = 'manu' and fecha_ingreso is null;

create or replace function public.sueldos_vacaciones_sugerida(p_mes date)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_ini date := date_trunc('month', p_mes)::date; v_fin_mes date := (date_trunc('month', p_mes) + interval '1 month - 1 day')::date;
        v_anio int := extract(year from p_mes)::int; v_cierre date;
begin
  if public.rol_actual() <> 'admin' then raise exception 'Sin permiso'; end if;
  v_cierre := make_date(v_anio, 12, 31);
  return coalesce((
    select jsonb_agg(jsonb_build_object('empleado_id', z.id, 'nombre', z.nombre, 'fecha_ingreso', z.fecha_ingreso, 'dias', z.dias, 'dias_base', z.dias_base,
              'proporcional', z.proporcional, 'prom_horas_dia', round(z.prom, 2), 'valor_hora', z.vh,
              'monto', case when z.dias is null or z.vh is null then null else round(z.vh * z.prom * z.dias) end) order by z.nombre)
      from (
        select e.id, e.nombre, e.fecha_ingreso,
               case when e.fecha_ingreso is null then null
                    when v_cierre <= e.fecha_ingreso + interval '5 years' then 14
                    when v_cierre <= e.fecha_ingreso + interval '10 years' then 21
                    when v_cierre <= e.fecha_ingreso + interval '20 years' then 28 else 35 end as dias_base,
               (e.fecha_ingreso is not null and e.fecha_ingreso > make_date(v_anio, 7, 2)) as proporcional,
               (select count(distinct t.fecha) from public.horas_turnos t where t.empleado_id = e.id and t.tipo = 'trabajo' and t.fecha >= make_date(v_anio, 1, 1) and t.fecha <= v_fin_mes) as dias_trabajados,
               coalesce((select sum(public._horas_turno(t.entrada, t.salida, t.tipo, t.horas_licencia)) / nullif(count(distinct t.fecha), 0)
                           from public.horas_turnos t where t.empleado_id = e.id and t.tipo = 'trabajo' and t.fecha > (v_ini - interval '5 months')::date and t.fecha <= v_fin_mes), 0) as prom,
               coalesce((select t.valor_hora from public.empleado_tarifas t where t.empleado_id = e.id and t.desde <= v_fin_mes order by t.desde desc limit 1),
                        (select t.valor_hora from public.empleado_tarifas t where t.empleado_id = e.id order by t.desde asc limit 1)) as vh
          from public.empleados e
         where exists (select 1 from public.horas_turnos t where t.empleado_id = e.id and t.fecha >= v_ini and t.fecha <= v_fin_mes)
      ) q
      cross join lateral (select q.id, q.nombre, q.fecha_ingreso, q.prom, q.vh, q.dias_base, q.proporcional,
                                 case when q.dias_base is null then null
                                      when q.proporcional then floor(q.dias_trabajados / 20.0)::int
                                      else q.dias_base end as dias) z
  ), '[]'::jsonb);
end;
$$;
grant execute on function public.sueldos_vacaciones_sugerida(date) to authenticated;

-- Control: el stock valorizado de hoy con la regla de tu planilla (tendria que parecerse a TOTAL DE MERCADERIA de tu PPTO)
select rubro, round(sum(greatest(s.cantidad_actual, 0) * coalesce(i.precio_costo_kg, 0) * coalesce(i.stock_iva, case when rubro in ('vermut', 'fiambres', 'quesos') then 1.21 else 1.0 end))) as valor
  from public.stock s join public.insumos i on i.id = s.insumo_id, lateral (select i.subcategoria::text as rubro) r
 where rubro not in ('limpieza', 'descartables') group by rubro order by rubro;
