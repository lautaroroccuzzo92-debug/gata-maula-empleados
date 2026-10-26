-- Gata Maula: stock valorizado automatico para el estado de resultados.
--   * stock_valorizado_actual(): cantidad de cada producto en Stock x su precio de costo x 1,21 (con IVA, como tu planilla), por rubro
--     (solo mercaderia: vermut, cerveza y sin alcohol, fiambres, quesos, kutsi, cocina y panes; limpieza y descartables se muestran aparte)
--   * stock_valorizado_diario: una foto por dia (la saca sola el servidor cada noche; ademas hay un boton para sacarla a mano)
--   * stock_valorizado_eerr(): para cada mes, el stock inicial (foto de fin del mes anterior) y el final (foto de fin de mes, o el de hoy si es el mes en curso)
-- Correr UNA vez en el SQL Editor.

create table if not exists public.stock_valorizado_diario (
  dia date primary key,
  total numeric(16,2) not null,
  por_rubro jsonb not null default '{}'::jsonb,
  sin_precio int not null default 0,
  tomado_en timestamptz not null default now()
);
alter table public.stock_valorizado_diario enable row level security;
drop policy if exists stock_valorizado_diario_select on public.stock_valorizado_diario;
create policy stock_valorizado_diario_select on public.stock_valorizado_diario for select using (public.rol_actual() = 'admin');

create or replace function public._stock_valorizado_calc()
returns jsonb
language sql stable security definer set search_path = public as $$
  with x as (
    select i.subcategoria::text as rubro,
           sum(greatest(s.cantidad_actual, 0) * coalesce(i.precio_costo_kg, 0) * 1.21) as v,
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

create or replace function public.stock_valorizado_actual()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if public.rol_actual() <> 'admin' then raise exception 'Sin permiso'; end if;
  return public._stock_valorizado_calc();
end;
$$;
grant execute on function public.stock_valorizado_actual() to authenticated;

-- foto del dia (la usa el servidor cada noche)
create or replace function public.registrar_stock_valorizado()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v jsonb := public._stock_valorizado_calc();
begin
  insert into public.stock_valorizado_diario (dia, total, por_rubro, sin_precio)
    values (public.hoy_ar(), (v->>'total')::numeric, v->'por_rubro', (v->>'sin_precio')::int)
    on conflict (dia) do update set total = excluded.total, por_rubro = excluded.por_rubro, sin_precio = excluded.sin_precio, tomado_en = now();
  return v;
end;
$$;
revoke all on function public.registrar_stock_valorizado() from public;
grant execute on function public.registrar_stock_valorizado() to service_role;

-- foto del dia a mano (boton del estado de resultados)
create or replace function public.stock_valorizado_foto()
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if public.rol_actual() <> 'admin' then raise exception 'Sin permiso'; end if;
  return public.registrar_stock_valorizado();
end;
$$;
grant execute on function public.stock_valorizado_foto() to authenticated;

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
      'fin', case when m.mes = v_mes_actual then (v_hoy->>'total')::numeric
                  else (select d.total from public.stock_valorizado_diario d where d.dia >= m.mes and d.dia < (m.mes + interval '1 month')::date order by d.dia desc limit 1) end,
      'inicio', (select d.total from public.stock_valorizado_diario d where d.dia >= (m.mes - interval '1 month')::date and d.dia < m.mes order by d.dia desc limit 1),
      'fin_es_hoy', m.mes = v_mes_actual
    ) order by m.mes)
    from (select generate_series(date_trunc('month', p_desde)::date, date_trunc('month', p_hasta)::date, interval '1 month')::date as mes) m
  ), '[]'::jsonb);
end;
$$;
grant execute on function public.stock_valorizado_eerr(date, date) to authenticated;
