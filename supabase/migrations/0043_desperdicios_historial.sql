-- Gata Maula: historial de desperdicios por mes.
--   * junta los totales que ya estaban cargados desde tus estados de resultados (enero a septiembre 2026) con lo que se carga en la app
--   * igual que el estado de resultados: si el mes tiene un total cargado a mano, ese manda; si no, se suma lo cargado en la app
--   * para los meses cargados en la app, muestra tambien los productos y motivos que mas pesan
-- Correr UNA vez en el SQL Editor.

create or replace function public.desperdicios_historial()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if public.rol_actual() not in ('admin', 'encargado') then raise exception 'Sin permiso'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'mes', to_char(m.mes, 'YYYY-MM'),
      'total', coalesce(man.desperdicios, app.total, 0),
      'manual', man.desperdicios,
      'app', app.total,
      'registros', coalesce(app.n, 0),
      'top_insumos', coalesce((
        select jsonb_agg(jsonb_build_object('insumo', x.nombre, 'valor', round(x.v)) order by x.v desc)
          from (select trim(coalesce(i.marca || ' ', '') || i.nombre) as nombre, sum(d.valor_calculado) as v
                  from public.desperdicio d join public.insumos i on i.id = d.insumo_id
                 where date_trunc('month', d.fecha)::date = m.mes group by 1 order by 2 desc limit 5) x), '[]'::jsonb),
      'top_motivos', coalesce((
        select jsonb_agg(jsonb_build_object('motivo', y.motivo, 'valor', round(y.v)) order by y.v desc)
          from (select lower(trim(coalesce(d.motivo, 'sin motivo'))) as motivo, sum(d.valor_calculado) as v
                  from public.desperdicio d where date_trunc('month', d.fecha)::date = m.mes group by 1 order by 2 desc limit 5) y), '[]'::jsonb)
    ) order by m.mes desc)
    from (select date_trunc('month', fecha)::date as mes from public.desperdicio
          union select mes from public.eerr_manual where desperdicios is not null) m
    left join (select date_trunc('month', fecha)::date as mes, sum(valor_calculado) as total, count(*) as n from public.desperdicio group by 1) app on app.mes = m.mes
    left join public.eerr_manual man on man.mes = m.mes and man.desperdicios is not null
  ), '[]'::jsonb);
end;
$$;
grant execute on function public.desperdicios_historial() to authenticated;
