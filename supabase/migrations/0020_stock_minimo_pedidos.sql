-- Gata Maula: stock minimo y lista de pedidos por proveedor.
--   * cada item de stock guarda: unidad (kg o unidad), proveedor al que se pide, dias de pedido y cantidad habitual a pedir
--   * configurar_pedido_stock(): cambia el minimo y los datos de pedido (admin y encargado)
-- Correr UNA vez en el SQL Editor, y despues 0021_stock_minimos.sql (carga los minimos de tus planillas).

alter table public.stock add column if not exists unidad text check (unidad in ('kg', 'unidad'));
alter table public.stock add column if not exists dias_pedido text;
alter table public.stock add column if not exists proveedor_pedido text;
alter table public.stock add column if not exists cantidad_pedido text;

create or replace function public.configurar_pedido_stock(
  p_insumo_id uuid, p_minimo numeric, p_proveedor text, p_dias text, p_cantidad text, p_unidad text default null
)
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if public.rol_actual() not in ('admin', 'encargado') then
    raise exception 'Sin permiso';
  end if;
  if p_minimo is null or p_minimo < 0 then
    raise exception 'El minimo tiene que ser 0 o mas';
  end if;
  if p_unidad is not null and p_unidad not in ('kg', 'unidad') then
    raise exception 'Unidad invalida';
  end if;
  update public.stock set
    stock_minimo = p_minimo,
    proveedor_pedido = nullif(trim(coalesce(p_proveedor, '')), ''),
    dias_pedido = nullif(trim(coalesce(p_dias, '')), ''),
    cantidad_pedido = nullif(trim(coalesce(p_cantidad, '')), ''),
    unidad = coalesce(p_unidad, unidad)
  where insumo_id = p_insumo_id;
  if not found then
    raise exception 'Ese insumo no tiene stock cargado';
  end if;
  return jsonb_build_object('ok', true);
end;
$$;
grant execute on function public.configurar_pedido_stock(uuid, numeric, text, text, text, text) to authenticated;
