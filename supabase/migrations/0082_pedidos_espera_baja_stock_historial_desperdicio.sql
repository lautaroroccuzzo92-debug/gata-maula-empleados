-- Gata Maula: tanda de mejoras pedidas por Lautaro (16/11)
--   1) PEDIDOS EN ESPERA: se marca un producto como "ya pedido"; queda en espera y sale solo de "para pedir" cuando entra por factura/remito.
--   2) SACAR UN PRODUCTO DEL STOCK: si esta en alguna receta / produccion / venta, hay que elegir por cual se reemplaza y todo se cambia solo.
--   3) HISTORIAL DE DESPERDICIOS para todos (cocina lo ve sin precios), con buscador por producto y para lo que viene de Produccion.
--   4) Lengua a la vinagreta y mostaza antigua pasan a contarse en el stock (en kg).
--   5) Frutilla: se cuenta en kilos.
-- Correr UNA vez en el SQL Editor. Es seguro correrlo mas de una vez.

-- ============================================================ 1) pedidos en espera
alter table public.stock add column if not exists pedido_en timestamptz;
alter table public.stock add column if not exists pedido_por uuid references public.usuarios(id) on delete set null;

create or replace function public.pedido_marcar(p_insumo_ids uuid[], p_pedido boolean)
returns integer
language plpgsql security definer set search_path = public as $$
declare v_n integer;
begin
  if public.rol_actual() is null then raise exception 'Sin permiso'; end if;
  update public.stock set pedido_en = case when p_pedido then now() end, pedido_por = case when p_pedido then auth.uid() end
   where insumo_id = any (p_insumo_ids);
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;
grant execute on function public.pedido_marcar(uuid[], boolean) to authenticated;

-- cuando el producto ENTRA (factura o remito) deja de estar en espera
create or replace function public._mov_ingreso_limpia_pedido() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.tipo::text = 'ingreso' then
    update public.stock set pedido_en = null, pedido_por = null where insumo_id = new.insumo_id and pedido_en is not null;
  end if;
  return new;
end;
$$;
drop trigger if exists trg_mov_ingreso_limpia_pedido on public.movimientos_stock;
create trigger trg_mov_ingreso_limpia_pedido after insert on public.movimientos_stock
  for each row execute function public._mov_ingreso_limpia_pedido();

-- ============================================================ 2) sacar un producto del stock
create table if not exists public.stock_bajas (
  id bigserial primary key,
  insumo_id uuid,
  producto text not null,
  cantidad numeric(14,3),
  reemplazo_id uuid,
  reemplazo text,
  usos jsonb,
  usuario_id uuid references public.usuarios(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.stock_bajas enable row level security;
drop policy if exists stock_bajas_select on public.stock_bajas;
create policy stock_bajas_select on public.stock_bajas for select using (public.rol_actual() in ('admin', 'encargado'));

-- donde se usa un producto (para avisar antes de sacarlo)
create or replace function public.stock_uso_producto(p_insumo_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_rec jsonb; v_vin jsonb; v_prod jsonb; v_out jsonb;
begin
  if public.rol_actual() is null then raise exception 'Sin permiso'; end if;
  select coalesce(jsonb_agg(distinct r.nombre_producto), '[]'::jsonb) into v_rec
    from public.receta_insumos ri join public.recetas r on r.id = ri.receta_id where ri.insumo_id = p_insumo_id;
  select coalesce(jsonb_agg(distinct v.producto), '[]'::jsonb) into v_vin from public.pos_vinculo v where v.insumo_id = p_insumo_id;
  select coalesce(jsonb_agg(distinct pi.nombre), '[]'::jsonb) into v_prod from public.produccion_items pi where pi.insumo_id = p_insumo_id;
  select coalesce(jsonb_agg(distinct r.nombre_producto), '[]'::jsonb) into v_out from public.recetas r where r.insumo_id = p_insumo_id;
  return jsonb_build_object('recetas', v_rec, 'ventas', v_vin, 'produccion', v_prod, 'elaborado_por_receta', v_out,
    'total', jsonb_array_length(v_rec) + jsonb_array_length(v_vin) + jsonb_array_length(v_prod) + jsonb_array_length(v_out));
end;
$$;
grant execute on function public.stock_uso_producto(uuid) to authenticated;

create or replace function public.stock_quitar_producto(p_insumo_id uuid, p_reemplazo uuid default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_nombre text; v_cant numeric; v_uso jsonb; v_total int; v_nom_r text;
begin
  if public.rol_actual() is null then raise exception 'Sin permiso'; end if;
  select trim(coalesce(i.marca || ' ', '') || i.nombre), s.cantidad_actual into v_nombre, v_cant
    from public.insumos i join public.stock s on s.insumo_id = i.id where i.id = p_insumo_id;
  if v_nombre is null then raise exception 'Ese producto no esta en el stock'; end if;

  v_uso := public.stock_uso_producto(p_insumo_id);
  v_total := (v_uso->>'total')::int;
  if v_total > 0 and p_reemplazo is null then
    raise exception 'Este producto se usa en recetas, produccion o ventas: hay que elegir por cual producto del stock se reemplaza.';
  end if;

  if p_reemplazo is not null then
    if p_reemplazo = p_insumo_id then raise exception 'El reemplazo tiene que ser otro producto'; end if;
    select trim(coalesce(i.marca || ' ', '') || i.nombre) into v_nom_r
      from public.insumos i join public.stock s on s.insumo_id = i.id where i.id = p_reemplazo;
    if v_nom_r is null then raise exception 'El producto de reemplazo tiene que estar cargado en el stock'; end if;

    -- recetas (ingredientes): pasan al producto de reemplazo
    update public.receta_insumos set insumo_id = p_reemplazo where insumo_id = p_insumo_id;
    -- si el producto era lo que elabora una receta, esa receta deja de fijar su precio
    update public.recetas set insumo_id = null where insumo_id = p_insumo_id;
    -- ventas de Postberry
    delete from public.pos_vinculo v where v.insumo_id = p_insumo_id
       and exists (select 1 from public.pos_vinculo x where x.producto = v.producto and x.insumo_id = p_reemplazo);
    update public.pos_vinculo set insumo_id = p_reemplazo where insumo_id = p_insumo_id;
    update public.pos_config set valor = p_reemplazo::text where clave = 'insumo_tabla' and valor = p_insumo_id::text;
    -- produccion y facturas futuras
    update public.produccion_items set insumo_id = p_reemplazo where insumo_id = p_insumo_id;
    update public.factura_alias set insumo_id = p_reemplazo where insumo_id = p_insumo_id;
  end if;

  insert into public.stock_bajas (insumo_id, producto, cantidad, reemplazo_id, reemplazo, usos, usuario_id)
    values (p_insumo_id, v_nombre, v_cant, p_reemplazo, v_nom_r, v_uso, auth.uid());

  delete from public.stock where insumo_id = p_insumo_id;

  if p_reemplazo is not null then perform public._recalcular_costo_recetas(p_reemplazo); end if;
  return jsonb_build_object('ok', true, 'producto', v_nombre, 'reemplazo', v_nom_r, 'usos', v_uso);
end;
$$;
grant execute on function public.stock_quitar_producto(uuid, uuid) to authenticated;

-- el "sacar del stock" de antes (sin reemplazo) ahora tambien protege las recetas y lo pueden usar todos
create or replace function public.stock_baja(p_insumo_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if public.rol_actual() is null then raise exception 'Sin permiso'; end if;
  return public.stock_quitar_producto(p_insumo_id, null);
end;
$$;
grant execute on function public.stock_baja(uuid) to authenticated;

-- ============================================================ 3) historial de desperdicios (todos los roles; el valor en $ solo admin y encargado)
create or replace function public.desperdicios_lista(
  p_desde date, p_hasta date, p_buscar text default null, p_solo_produccion boolean default false
) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_valor boolean := public.rol_actual() in ('admin', 'encargado'); v_q text := nullif(trim(coalesce(p_buscar, '')), '');
begin
  if public.rol_actual() is null then raise exception 'Sin permiso'; end if;
  if v_q is not null then v_q := '%' || public.normalizar_texto(v_q) || '%'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('fecha', x.fecha, 'producto', x.producto, 'cantidad', x.cantidad, 'unidad', x.unidad,
             'motivo', x.motivo, 'quien', x.quien, 'produccion', x.produccion, 'valor', case when v_valor then x.valor end) order by x.fecha desc, x.orden desc)
    from (
      select * from (
        -- lo que se cargo en Desperdicio y la merma de Produccion que quedo en Desperdicio
        select d.fecha, trim(coalesce(i.marca || ' ', '') || i.nombre) as producto, d.cantidad, i.unidad_medida as unidad,
               d.motivo, u.nombre as quien, (d.motivo like 'Merma de produccion%') as produccion, d.valor_calculado as valor, d.created_at as orden
          from public.desperdicio d
          join public.insumos i on i.id = d.insumo_id
          left join public.usuarios u on u.id = d.usuario_id
         where d.fecha between p_desde and p_hasta
        union all
        -- merma de lotes de produccion cuyo producto no se cuenta en el stock (no genera desperdicio con valor)
        select (l.cerrado_el at time zone 'America/Argentina/Buenos_Aires')::date, pi.nombre, l.cantidad_merma, l.unidad,
               'Merma de produccion' || coalesce(' - ' || l.motivo_merma, ''), u.nombre, true, null::numeric, l.cerrado_el
          from public.produccion_lotes l
          join public.produccion_items pi on pi.id = l.item_id
          left join public.usuarios u on u.id = l.cerrado_por
         where l.estado = 'cerrado' and l.cantidad_merma > 0 and l.desperdicio_id is null
           and (l.cerrado_el at time zone 'America/Argentina/Buenos_Aires')::date between p_desde and p_hasta
      ) t
      where (v_q is null or public.normalizar_texto(t.producto || ' ' || coalesce(t.motivo, '')) like v_q)
        and (not p_solo_produccion or t.produccion)
      order by t.fecha desc, t.orden desc
      limit 400
    ) x
  ), '[]'::jsonb);
end;
$$;
grant execute on function public.desperdicios_lista(date, date, text, boolean) to authenticated;

-- ============================================================ 4) lengua a la vinagreta y mostaza antigua se cuentan en el stock (kg)
do $$
declare v uuid;
begin
  for v in select distinct insumo_id from public.produccion_items
            where public.normalizar_texto(nombre) in ('LENGUA A LA VINAGRETA', 'MOSTAZA') and insumo_id is not null
  loop
    perform public._stock_alta(v, 'kg');
    update public.insumos set unidad_medida = 'kg' where id = v and unidad_medida is distinct from 'kg';
  end loop;
end
$$;

-- ============================================================ 5) frutilla en kilos
update public.stock set unidad = 'kg'
 where insumo_id in (select id from public.insumos where public.normalizar_texto(trim(coalesce(marca || ' ', '') || nombre)) like 'FRUTILLA%');
update public.insumos set unidad_medida = 'kg', gramos_paquete = null
 where public.normalizar_texto(trim(coalesce(marca || ' ', '') || nombre)) like 'FRUTILLA%' and (unidad_medida is distinct from 'kg' or gramos_paquete is not null);

-- ============================================================ resultado
select 'stock nuevo' as que, trim(coalesce(i.marca || ' ', '') || i.nombre) as producto, s.unidad || ' · hay ' || s.cantidad_actual as detalle
  from public.produccion_items pi join public.insumos i on i.id = pi.insumo_id join public.stock s on s.insumo_id = i.id
 where public.normalizar_texto(pi.nombre) in ('LENGUA A LA VINAGRETA', 'MOSTAZA')
union all
select 'frutilla', trim(coalesce(i.marca || ' ', '') || i.nombre), coalesce(s.unidad, 'sin unidad') || ' · unidad_medida ' || i.unidad_medida || ' · hay ' || coalesce(s.cantidad_actual::text, '-')
  from public.insumos i left join public.stock s on s.insumo_id = i.id
 where public.normalizar_texto(trim(coalesce(i.marca || ' ', '') || i.nombre)) like 'FRUTILLA%';
