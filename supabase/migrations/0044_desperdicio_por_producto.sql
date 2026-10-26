-- Gata Maula: historial de desperdicio POR PRODUCTO en un rango de fechas.
--   * por cada producto: cuanto se tiro (en kg/unidades), cuanto vale en plata, cuanto ingreso por factura en el mismo rango y el porcentaje tirado
--   * "ingreso" = solo lo que entro por factura (no cuentan altas manuales ni correcciones de stock)
--   * incluye el detalle de cada vez que se tiro (fecha, cantidad, motivo)
-- Correr UNA vez en el SQL Editor.

create or replace function public.desperdicios_por_producto(p_desde date, p_hasta date)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if public.rol_actual() not in ('admin', 'encargado') then raise exception 'Sin permiso'; end if;
  return coalesce((
    with d as (
      select insumo_id, sum(cantidad) as cant, sum(valor_calculado) as valor, count(*) as n
        from public.desperdicio
       where fecha between p_desde and p_hasta
       group by insumo_id
    ), ing as (
      select insumo_id, sum(cantidad) as cant
        from public.movimientos_stock
       where tipo = 'ingreso' and origen = 'factura'
         and (fecha at time zone 'America/Argentina/Buenos_Aires')::date between p_desde and p_hasta
       group by insumo_id
    )
    select jsonb_agg(jsonb_build_object(
      'insumo', trim(coalesce(i.marca || ' ', '') || i.nombre),
      'categoria', i.subcategoria::text,
      'unidad', i.unidad_medida,
      'cantidad', d.cant,
      'valor', round(coalesce(d.valor, 0)),
      'registros', d.n,
      'ingresado', coalesce(ing.cant, 0),
      'porcentaje', case when coalesce(ing.cant, 0) > 0 then round(d.cant / ing.cant * 100, 1) end,
      'detalle', (select jsonb_agg(jsonb_build_object('fecha', x.fecha, 'cantidad', x.cantidad, 'valor', round(coalesce(x.valor_calculado, 0)), 'motivo', x.motivo) order by x.fecha)
                    from public.desperdicio x where x.insumo_id = d.insumo_id and x.fecha between p_desde and p_hasta)
    ) order by d.valor desc nulls last)
    from d join public.insumos i on i.id = d.insumo_id left join ing on ing.insumo_id = d.insumo_id
  ), '[]'::jsonb);
end;
$$;
grant execute on function public.desperdicios_por_producto(date, date) to authenticated;
