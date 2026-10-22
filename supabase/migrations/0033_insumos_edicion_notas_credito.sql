-- Gata Maula: edicion de insumos (renombrar, cambiar de rubro, unir repetidos, eliminar) y notas de credito de proveedores.
--   * insumo_uso / insumo_editar / insumo_unir / insumo_eliminar
--   * facturas_proveedor / registrar_nota_credito: la nota de credito resta del gasto (mismo concepto que la factura) y
--       - si la factura estaba pendiente, baja lo que se le debe al proveedor (calendario de pagos)
--       - si la factura ya estaba paga, queda como saldo a favor con ese proveedor (un renglon negativo en el calendario de pagos)
-- Correr UNA vez en el SQL Editor.

-- ================================================================ INSUMOS
create or replace function public.insumo_uso(p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if public.rol_actual() not in ('admin', 'encargado') then raise exception 'Sin permiso'; end if;
  return jsonb_build_object(
    'recetas', coalesce((select jsonb_agg(distinct r.nombre_producto) from public.receta_insumos ri join public.recetas r on r.id = ri.receta_id where ri.insumo_id = p_id), '[]'::jsonb),
    'stock', (select jsonb_build_object('cantidad', cantidad_actual, 'minimo', stock_minimo) from public.stock where insumo_id = p_id),
    'desperdicios', (select count(*) from public.desperdicio where insumo_id = p_id),
    'movimientos', (select count(*) from public.movimientos_stock where insumo_id = p_id)
  );
end;
$$;
grant execute on function public.insumo_uso(uuid) to authenticated;

create or replace function public.insumo_editar(p_id uuid, p_nombre text, p_marca text, p_subcategoria text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_sub subcategoria_insumo; v_grupo grupo_insumo;
begin
  if public.rol_actual() not in ('admin', 'encargado') then raise exception 'Sin permiso'; end if;
  if trim(coalesce(p_nombre, '')) = '' then raise exception 'Falta la descripcion del insumo'; end if;
  if exists (select 1 from public.insumos where id = p_id and es_preparacion) then raise exception 'Las preparaciones caseras se editan desde Recetas'; end if;
  v_sub := p_subcategoria::subcategoria_insumo;
  v_grupo := case when v_sub in ('vermut', 'cerveza y sin alcohol') then 'bebidas' else 'cocina' end;
  update public.insumos set nombre = trim(p_nombre), marca = nullif(trim(coalesce(p_marca, '')), ''), subcategoria = v_sub, grupo = v_grupo
    where id = p_id;
  if not found then raise exception 'Insumo no encontrado'; end if;
  return jsonb_build_object('ok', true);
end;
$$;
grant execute on function public.insumo_editar(uuid, text, text, text) to authenticated;

-- Une un insumo repetido con el bueno: todo lo que apuntaba al repetido pasa al que se conserva.
create or replace function public.insumo_unir(p_conservar uuid, p_quitar uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare sq record; sc record; v_precio numeric;
begin
  if public.rol_actual() <> 'admin' then raise exception 'Sin permiso'; end if;
  if p_conservar = p_quitar then raise exception 'Elegi dos insumos distintos'; end if;
  if not exists (select 1 from public.insumos where id = p_conservar and not es_preparacion) or not exists (select 1 from public.insumos where id = p_quitar and not es_preparacion) then
    raise exception 'Los dos tienen que ser insumos (no preparaciones)';
  end if;
  select precio_costo_kg into v_precio from public.insumos where id = p_conservar;

  select * into sq from public.stock where insumo_id = p_quitar;
  if found then
    select * into sc from public.stock where insumo_id = p_conservar;
    if found then
      update public.stock set
        cantidad_actual = sc.cantidad_actual + sq.cantidad_actual,
        stock_minimo = case when coalesce(sc.stock_minimo, 0) > 0 then sc.stock_minimo else sq.stock_minimo end,
        proveedor_pedido = coalesce(sc.proveedor_pedido, sq.proveedor_pedido),
        dias_pedido = coalesce(sc.dias_pedido, sq.dias_pedido),
        cantidad_pedido = coalesce(sc.cantidad_pedido, sq.cantidad_pedido),
        unidad = coalesce(sc.unidad, sq.unidad),
        valorizacion = (sc.cantidad_actual + sq.cantidad_actual) * v_precio,
        ultima_actualizacion = now()
        where insumo_id = p_conservar;
      delete from public.stock where insumo_id = p_quitar;
    else
      update public.stock set insumo_id = p_conservar where insumo_id = p_quitar;
    end if;
  end if;

  update public.movimientos_stock set insumo_id = p_conservar where insumo_id = p_quitar;
  update public.desperdicio set insumo_id = p_conservar where insumo_id = p_quitar;
  update public.ingresos_egresos set insumo_relacionado_id = p_conservar where insumo_relacionado_id = p_quitar;
  update public.receta_insumos set insumo_id = p_conservar where insumo_id = p_quitar;
  update public.historial_precios set insumo_id = p_conservar where insumo_id = p_quitar;
  update public.factura_alias set insumo_id = p_conservar where insumo_id = p_quitar;
  update public.produccion_items set insumo_id = p_conservar where insumo_id = p_quitar;
  delete from public.insumos where id = p_quitar;

  perform public._recalcular_costo_recetas(p_conservar);
  return jsonb_build_object('ok', true);
end;
$$;
grant execute on function public.insumo_unir(uuid, uuid) to authenticated;

-- Elimina un insumo que no se usa en recetas ni tiene desperdicios cargados
create or replace function public.insumo_eliminar(p_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_recetas text;
begin
  if public.rol_actual() <> 'admin' then raise exception 'Sin permiso'; end if;
  if exists (select 1 from public.insumos where id = p_id and es_preparacion) then raise exception 'Las preparaciones caseras se eliminan desde Recetas'; end if;
  select string_agg(distinct r.nombre_producto, ', ') into v_recetas from public.receta_insumos ri join public.recetas r on r.id = ri.receta_id where ri.insumo_id = p_id;
  if v_recetas is not null then raise exception 'No se puede eliminar: se usa en las recetas: %. Sacalo de esas recetas o unilo con otro insumo.', v_recetas; end if;
  if exists (select 1 from public.desperdicio where insumo_id = p_id) then
    raise exception 'No se puede eliminar: tiene desperdicios cargados. Unilo con otro insumo en lugar de eliminarlo.';
  end if;
  delete from public.stock where insumo_id = p_id;
  delete from public.movimientos_stock where insumo_id = p_id;
  update public.ingresos_egresos set insumo_relacionado_id = null where insumo_relacionado_id = p_id;
  delete from public.insumos where id = p_id;
  if not found then raise exception 'Insumo no encontrado'; end if;
  return jsonb_build_object('ok', true);
end;
$$;
grant execute on function public.insumo_eliminar(uuid) to authenticated;

-- ================================================================ NOTAS DE CREDITO
alter table public.ingresos_egresos add column if not exists nc_de_factura text;
create index if not exists ingresos_egresos_nc_idx on public.ingresos_egresos (proveedor_id, nc_de_factura);

-- Facturas de un proveedor, con lo que ya se acredito y lo que queda
create or replace function public.facturas_proveedor(p_proveedor_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if public.rol_actual() not in ('admin', 'encargado') then raise exception 'Sin permiso'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'nro', f.nro, 'fecha', f.fecha, 'total', f.total, 'pagada', f.pagada, 'conceptos', f.conceptos,
      'acreditado', coalesce((select -sum(n.monto) from public.ingresos_egresos n where n.proveedor_id = p_proveedor_id and n.nc_de_factura = f.nro), 0)
    ) order by f.fecha desc)
    from (
      select factura_numero as nro, min(fecha) as fecha, sum(monto) as total,
             bool_and(estado_pago = 'pagado') as pagada, string_agg(distinct concepto, ', ') as conceptos
        from public.ingresos_egresos
       where proveedor_id = p_proveedor_id and factura_numero is not null and nc_de_factura is null
         and concepto <> 'PAGO DEUDA PROVEEDORES' and monto > 0 and forma in ('deuda_proveedores', 'egreso_banco', 'egreso_efectivo')
       group by factura_numero
       order by min(fecha) desc
       limit 80
    ) f
  ), '[]'::jsonb);
end;
$$;
grant execute on function public.facturas_proveedor(uuid) to authenticated;

create or replace function public.registrar_nota_credito(
  p_proveedor_id uuid, p_fecha date, p_monto numeric, p_nro_nc text, p_factura_nro text, p_obs text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  r record;
  v_total numeric; v_acred numeric; v_restante numeric; v_nombre text;
  v_acum numeric := 0; v_share numeric; v_n int; v_i int := 0;
  v_baja_deuda numeric := 0; v_a_favor numeric := 0; v_primer_id uuid; v_nuevo_id uuid;
  v_obs text;
begin
  if public.rol_actual() not in ('admin', 'encargado') then raise exception 'Sin permiso'; end if;
  if p_monto is null or p_monto <= 0 then raise exception 'El monto de la nota de credito tiene que ser mayor a 0'; end if;
  if trim(coalesce(p_factura_nro, '')) = '' then raise exception 'Elegi la factura a la que corresponde'; end if;
  select nombre into v_nombre from public.proveedores where id = p_proveedor_id;
  if v_nombre is null then raise exception 'Proveedor no encontrado'; end if;

  select coalesce(sum(monto), 0), count(*) into v_total, v_n from public.ingresos_egresos
   where proveedor_id = p_proveedor_id and factura_numero = p_factura_nro and nc_de_factura is null
     and concepto <> 'PAGO DEUDA PROVEEDORES' and monto > 0 and forma in ('deuda_proveedores', 'egreso_banco', 'egreso_efectivo');
  if v_n = 0 then raise exception 'No encontre la factura % de ese proveedor', p_factura_nro; end if;
  select coalesce(-sum(monto), 0) into v_acred from public.ingresos_egresos where proveedor_id = p_proveedor_id and nc_de_factura = p_factura_nro;
  v_restante := v_total - v_acred;
  if p_monto > v_restante + 0.01 then
    raise exception 'La nota de credito ($%) supera lo que queda de la factura ($%)', round(p_monto, 2), round(v_restante, 2);
  end if;

  v_obs := 'Nota de credito ' || coalesce(nullif(trim(p_nro_nc), ''), 's/n') || ' sobre factura ' || p_factura_nro || coalesce(' - ' || nullif(trim(p_obs), ''), '');

  for r in
    select id, concepto, monto, forma, estado_pago from public.ingresos_egresos
     where proveedor_id = p_proveedor_id and factura_numero = p_factura_nro and nc_de_factura is null
       and concepto <> 'PAGO DEUDA PROVEEDORES' and monto > 0 and forma in ('deuda_proveedores', 'egreso_banco', 'egreso_efectivo')
     order by monto desc
  loop
    v_i := v_i + 1;
    v_share := case when v_i = v_n then round(p_monto - v_acum, 2) else round(p_monto * r.monto / v_total, 2) end;
    v_acum := v_acum + v_share;
    if v_share <= 0 then continue; end if;

    if r.forma = 'deuda_proveedores' and r.estado_pago = 'pendiente' then
      -- la factura sigue sin pagar: baja la deuda
      insert into public.ingresos_egresos (fecha, proveedor_id, concepto, factura_numero, monto, forma, estado_pago, medio_pago, fecha_pago, origen, usuario_id, observaciones, lote_importacion, nc_de_factura)
        values (coalesce(p_fecha, public.hoy_ar()), p_proveedor_id, r.concepto, nullif(trim(p_nro_nc), ''), -v_share, 'deuda_proveedores', 'pagado'::estado_pago_tipo, 'nota de credito', coalesce(p_fecha, public.hoy_ar()),
                'manual', auth.uid(), v_obs, to_char(coalesce(p_fecha, public.hoy_ar()), 'YYYY-MM'), p_factura_nro)
        returning id into v_nuevo_id;
      update public.calendario_pagos set total = total - v_share where egreso_id = r.id and not pagado;
      update public.calendario_pagos set pagado = true, fecha_pago = coalesce(p_fecha, public.hoy_ar()), medio_pago = 'nota de credito'
        where egreso_id = r.id and not pagado and total <= 0.005;
      v_baja_deuda := v_baja_deuda + v_share;
    else
      -- la factura ya estaba paga: queda saldo a favor con el proveedor
      insert into public.ingresos_egresos (fecha, proveedor_id, concepto, factura_numero, monto, forma, estado_pago, origen, usuario_id, observaciones, lote_importacion, nc_de_factura)
        values (coalesce(p_fecha, public.hoy_ar()), p_proveedor_id, r.concepto, nullif(trim(p_nro_nc), ''), -v_share, 'deuda_proveedores', 'pendiente'::estado_pago_tipo,
                'manual', auth.uid(), v_obs, to_char(coalesce(p_fecha, public.hoy_ar()), 'YYYY-MM'), p_factura_nro)
        returning id into v_nuevo_id;
      v_a_favor := v_a_favor + v_share;
    end if;
    if v_primer_id is null then v_primer_id := v_nuevo_id; end if;
  end loop;

  if v_a_favor > 0 then
    insert into public.calendario_pagos (fecha_factura, fecha_vencimiento, nro_factura, proveedor_id, proveedor_texto, concepto, total, facturado, egreso_id, origen, nota)
      values (coalesce(p_fecha, public.hoy_ar()), coalesce(p_fecha, public.hoy_ar()), nullif(trim(p_nro_nc), ''), p_proveedor_id, v_nombre,
              'NOTA DE CREDITO (saldo a favor)', -round(v_a_favor, 2), 'SI', v_primer_id, 'app', 'Se descuenta de la proxima factura de ' || v_nombre);
  end if;

  return jsonb_build_object('ok', true, 'baja_deuda', round(v_baja_deuda, 2), 'saldo_a_favor', round(v_a_favor, 2));
end;
$$;
grant execute on function public.registrar_nota_credito(uuid, date, numeric, text, text, text) to authenticated;
