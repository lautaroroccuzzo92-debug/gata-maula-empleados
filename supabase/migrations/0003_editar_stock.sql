-- Gata Maula: permitir corregir el stock a mano (conteo físico) desde la app.
-- Corre esto en el SQL Editor de Supabase.

-- Nuevo tipo de movimiento para diferenciarlo de ingreso/egreso_venta/desperdicio.
alter type tipo_movimiento_stock add value if not exists 'ajuste';

-- RPC: ajustar_stock_conteo
-- Invocada directamente desde el navegador (anon key + sesión del usuario),
-- igual que registrar_desperdicio — usa auth.uid() internamente. Pone la
-- cantidad_actual en el valor exacto que cargó el usuario (no suma/resta) y
-- deja un registro en movimientos_stock con el usuario y la fecha.
create or replace function public.ajustar_stock_conteo(p_insumo_id uuid, p_cantidad_nueva numeric)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_usuario_id uuid := auth.uid();
  v_precio numeric;
  v_cantidad_actual numeric;
  v_diferencia numeric;
begin
  if v_usuario_id is null then
    raise exception 'No autenticado';
  end if;
  if public.rol_actual() not in ('admin','encargado','cocina') then
    raise exception 'Sin permiso';
  end if;
  if p_cantidad_nueva is null or p_cantidad_nueva < 0 then
    raise exception 'Cantidad inválida';
  end if;

  select precio_costo_kg into v_precio from public.insumos where id = p_insumo_id;
  if v_precio is null then
    raise exception 'Insumo no encontrado';
  end if;

  select cantidad_actual into v_cantidad_actual from public.stock where insumo_id = p_insumo_id;
  if v_cantidad_actual is null then
    v_cantidad_actual := 0;
  end if;
  v_diferencia := p_cantidad_nueva - v_cantidad_actual;

  if v_diferencia <> 0 then
    insert into public.movimientos_stock (insumo_id, tipo, cantidad, origen, usuario_id)
      values (p_insumo_id, 'ajuste', v_diferencia, 'manual', v_usuario_id);
  end if;

  update public.stock set
    cantidad_actual = p_cantidad_nueva,
    valorizacion = p_cantidad_nueva * v_precio,
    ultima_actualizacion = now()
    where insumo_id = p_insumo_id;

  return jsonb_build_object('success', true, 'cantidad_actual', p_cantidad_nueva, 'diferencia', v_diferencia);
end;
$$;

grant execute on function public.ajustar_stock_conteo(uuid, numeric) to authenticated;
