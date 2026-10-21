-- Gata Maula: en la carga de facturas por foto, elegir a que insumo corresponde cada producto.
--   * factura_alias recuerda "este texto de este proveedor = este insumo" para que la proxima vez se asocie solo
--   * registrar_ingreso_factura acepta por cada producto: insumo_id (el elegido), crear_nuevo (true = insumo nuevo)
--     y clave_alias (lo que hay que recordar). Si no vienen, busca como antes.
-- Correr UNA vez en el SQL Editor (despues de 0028).

create table if not exists public.factura_alias (
  id uuid primary key default gen_random_uuid(),
  clave text not null unique,
  insumo_id uuid not null references public.insumos(id) on delete cascade,
  usuario_id uuid references public.usuarios(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.factura_alias enable row level security;
drop policy if exists factura_alias_select on public.factura_alias;
create policy factura_alias_select on public.factura_alias for select using (public.rol_actual() in ('admin', 'encargado'));

create or replace function public.registrar_ingreso_factura(p_usuario_id uuid, p_payload jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_proveedor_nombre text := trim(p_payload->>'proveedor');
  v_iva_pct numeric := nullif(p_payload->>'iva_pct','')::numeric;
  v_fecha date := coalesce((p_payload->>'fecha')::date, current_date);
  v_pagado boolean := coalesce((p_payload->>'pagado')::boolean, false);
  v_total_factura numeric := coalesce((p_payload->>'total_factura')::numeric, 0);
  v_proveedor_id uuid;
  v_producto jsonb;
  v_categoria text;
  v_nombre_insumo text;
  v_subcategoria subcategoria_insumo;
  v_grupo grupo_insumo;
  v_cantidad numeric;
  v_precio_unit numeric;
  v_precio_neto numeric;
  v_insumo_id uuid;
  v_insumo_existente record;
  v_candidato record;
  v_ingreso_egreso_id uuid;
  v_insumos_resultado jsonb := '[]'::jsonb;
  v_sin_stock jsonb := '[]'::jsonb;
  v_sin_minimo jsonb := '[]'::jsonb;
  v_minimo numeric;
  v_insumo_elegido uuid;
  v_crear boolean;
  v_clave text;
  v_forma text;
  v_estado estado_pago_tipo := (case when v_pagado then 'pagado' else 'pendiente' end)::estado_pago_tipo;
  v_conc record;
  v_suma_lineas numeric := 0;
  v_filas_ie integer := 0;
  v_monto_fila numeric;
begin
  if v_proveedor_nombre = '' then
    raise exception 'Falta el nombre del proveedor';
  end if;

  -- Proveedor: alta idempotente por nombre (case-insensitive)
  insert into public.proveedores (nombre)
  values (v_proveedor_nombre)
  on conflict (lower(nombre)) do nothing;

  select id into v_proveedor_id from public.proveedores where lower(nombre) = lower(v_proveedor_nombre);

  -- Lineas de producto
  for v_producto in select * from jsonb_array_elements(coalesce(p_payload->'productos', '[]'::jsonb))
  loop
    v_categoria := v_producto->>'categoria';
    v_nombre_insumo := trim(coalesce(v_producto->>'marca','') || ' ' || coalesce(v_producto->>'descripcion',''));
    v_cantidad := coalesce((v_producto->>'kg_litros')::numeric, (v_producto->>'unidades')::numeric, 0);
    v_precio_unit := coalesce((v_producto->>'precio_unitario')::numeric, 0);
    v_precio_neto := case when v_iva_pct is not null and v_iva_pct > 0
                          then round(v_precio_unit / (1 + v_iva_pct/100), 2)
                          else v_precio_unit end;

    v_subcategoria := null;
    v_grupo := null;
    if v_categoria = 'FIAMBRES Y QUESOS' then
      v_grupo := 'cocina';
      v_subcategoria := case when v_nombre_insumo ilike '%queso%' then 'quesos' else 'fiambres' end;
    elsif v_categoria = 'VERMUT' then
      v_grupo := 'bebidas'; v_subcategoria := 'vermut';
    elsif v_categoria in ('CERVEZA Y SIN ALCOHOL', 'BEBIDAS') then
      v_grupo := 'bebidas'; v_subcategoria := 'cerveza y sin alcohol';
    elsif v_categoria = 'COCINA' then
      v_grupo := 'cocina'; v_subcategoria := 'cocina';
    elsif v_categoria = 'PAN' then
      v_grupo := 'cocina'; v_subcategoria := 'panes';
    elsif v_categoria = 'INSUMOS DE LIMPIEZA' then
      v_grupo := 'cocina'; v_subcategoria := 'limpieza';
    elsif v_categoria = 'DESCARTABLES' then
      v_grupo := 'cocina'; v_subcategoria := 'descartables';
    end if;

    if v_subcategoria is null or v_nombre_insumo = '' then
      -- Categoria que no se trackea como insumo/stock (verduleria, comida de personal, etc.)
      v_sin_stock := v_sin_stock || jsonb_build_object('nombre', v_nombre_insumo, 'categoria', v_categoria, 'total', v_producto->>'total');
      continue;
    end if;

    -- El insumo lo elige la persona en la pantalla de revision (insumo_id) o pide crear uno nuevo (crear_nuevo).
    -- Si la app no lo manda, se busca como antes: exacto o parecido dentro de la misma subcategoria.
    v_insumo_elegido := nullif(v_producto->>'insumo_id', '')::uuid;
    v_crear := coalesce((v_producto->>'crear_nuevo')::boolean, false);
    v_clave := nullif(trim(coalesce(v_producto->>'clave_alias', '')), '');
    v_insumo_existente := null;

    if v_insumo_elegido is not null then
      select id, nombre into v_insumo_existente from public.insumos where id = v_insumo_elegido and not es_preparacion;
      if v_insumo_existente.id is null then
        raise exception 'El insumo elegido para "%" ya no existe', v_nombre_insumo;
      end if;
    elsif not v_crear then
      select id, nombre into v_insumo_existente from public.insumos
        where not es_preparacion
          and subcategoria::text = any(case when v_subcategoria::text = 'cocina' then array['cocina','kutsi'] else array[v_subcategoria::text] end)
          and lower(trim(coalesce(marca, '') || ' ' || nombre)) = lower(v_nombre_insumo)
        limit 1;

      if v_insumo_existente.id is null then
        select id, nombre, public.similitud_palabras(public.normalizar_texto(trim(coalesce(marca, '') || ' ' || nombre)), public.normalizar_texto(v_nombre_insumo)) as score
          into v_candidato
          from public.insumos
          where not es_preparacion
            and subcategoria::text = any(case when v_subcategoria::text = 'cocina' then array['cocina','kutsi'] else array[v_subcategoria::text] end)
          order by score desc limit 1;
        if v_candidato.id is not null and v_candidato.score >= 0.5 then
          v_insumo_existente := v_candidato;
        end if;
      end if;
    end if;

    if v_insumo_existente.id is not null then
      v_insumo_id := v_insumo_existente.id;
      update public.insumos set
        precio_costo_kg = v_precio_neto,
        proveedor_id = coalesce(proveedor_id, v_proveedor_id),
        fecha_ultima_actualizacion = now()
        where id = v_insumo_id;
    else
      insert into public.insumos (nombre, grupo, subcategoria, proveedor_id, precio_costo_kg, origen_alta)
        values (v_nombre_insumo, v_grupo, v_subcategoria, v_proveedor_id, v_precio_neto, 'factura')
        returning id into v_insumo_id;
    end if;

    -- Recordar la equivalencia (texto de ese proveedor en la factura -> insumo) para las proximas facturas
    if v_clave is not null and (v_insumo_elegido is not null or v_crear) then
      insert into public.factura_alias (clave, insumo_id, usuario_id)
        values (v_clave, v_insumo_id, p_usuario_id)
        on conflict (clave) do update set insumo_id = excluded.insumo_id, usuario_id = excluded.usuario_id;
    end if;

    insert into public.movimientos_stock (insumo_id, tipo, cantidad, origen, usuario_id)
      values (v_insumo_id, 'ingreso', v_cantidad, 'factura', p_usuario_id);

    insert into public.stock (insumo_id, cantidad_actual, valorizacion, ultima_actualizacion, proveedor_pedido)
      values (v_insumo_id, v_cantidad, v_cantidad * v_precio_neto, now(), v_proveedor_nombre)
      on conflict (insumo_id) do update set
        cantidad_actual = public.stock.cantidad_actual + excluded.cantidad_actual,
        valorizacion = (public.stock.cantidad_actual + excluded.cantidad_actual) * v_precio_neto,
        proveedor_pedido = coalesce(public.stock.proveedor_pedido, excluded.proveedor_pedido),
        ultima_actualizacion = now();

    select stock_minimo into v_minimo from public.stock where insumo_id = v_insumo_id;
    if coalesce(v_minimo, 0) <= 0 then
      v_sin_minimo := v_sin_minimo || jsonb_build_object('id', v_insumo_id, 'nombre', v_nombre_insumo);
    end if;

    v_insumos_resultado := v_insumos_resultado || jsonb_build_object(
      'id', v_insumo_id, 'nombre', v_nombre_insumo, 'precio_costo_kg', v_precio_neto, 'cantidad', v_cantidad
    );
  end loop;

  -- Forma del movimiento (las columnas de la hoja EGRESOS): pagado en efectivo, pagado por banco o deuda con el proveedor.
  v_forma := case when v_pagado then
                    (case when coalesce(p_payload->>'medio_pago', '') ilike '%efectivo%' then 'egreso_efectivo' else 'egreso_banco' end)
                  else 'deuda_proveedores' end;

  -- Una fila por concepto del estado de resultados (categoria de cada linea), repartiendo el total de la factura.
  select coalesce(sum(coalesce((p->>'total')::numeric, 0)), 0) into v_suma_lineas
    from jsonb_array_elements(coalesce(p_payload->'productos', '[]'::jsonb)) p;

  for v_conc in
    select public._concepto_eerr(p->>'categoria') as concepto,
           sum(coalesce((p->>'total')::numeric, 0)) as total
      from jsonb_array_elements(coalesce(p_payload->'productos', '[]'::jsonb)) p
     group by 1
    having sum(coalesce((p->>'total')::numeric, 0)) > 0
  loop
    v_monto_fila := case when v_total_factura > 0 and v_suma_lineas > 0
                         then round(v_conc.total * v_total_factura / v_suma_lineas, 2)
                         else v_conc.total end;
    insert into public.ingresos_egresos (
      fecha, proveedor_id, concepto, factura_numero, remito_numero, monto,
      tiene_iva, iva_pct, estado_pago, medio_pago, fecha_pago, origen, usuario_id, observaciones, forma
    ) values (
      v_fecha, v_proveedor_id, v_conc.concepto,
      nullif(p_payload->>'numero_factura',''), nullif(p_payload->>'numero_remito',''),
      v_monto_fila, v_iva_pct is not null, v_iva_pct,
      v_estado,
      nullif(p_payload->>'medio_pago',''),
      case when v_pagado then v_fecha else null end,
      'factura', p_usuario_id, nullif(p_payload->>'observaciones',''), v_forma
    ) returning id into v_ingreso_egreso_id;
    v_filas_ie := v_filas_ie + 1;
  end loop;

  if v_filas_ie = 0 then
    insert into public.ingresos_egresos (
      fecha, proveedor_id, concepto, factura_numero, remito_numero, monto,
      tiene_iva, iva_pct, estado_pago, medio_pago, fecha_pago, origen, usuario_id, observaciones, forma
    ) values (
      v_fecha, v_proveedor_id, 'GASTOS DIARIOS NO CLASIFICADOS',
      nullif(p_payload->>'numero_factura',''), nullif(p_payload->>'numero_remito',''),
      v_total_factura, v_iva_pct is not null, v_iva_pct,
      v_estado,
      nullif(p_payload->>'medio_pago',''),
      case when v_pagado then v_fecha else null end,
      'factura', p_usuario_id, nullif(p_payload->>'observaciones',''), v_forma
    ) returning id into v_ingreso_egreso_id;
  end if;

  return jsonb_build_object(
    'proveedor', jsonb_build_object('id', v_proveedor_id, 'nombre', v_proveedor_nombre),
    'insumos', v_insumos_resultado,
    'lineas_sin_stock', v_sin_stock,
    'sin_minimo', v_sin_minimo,
    'ingreso_egreso_id', v_ingreso_egreso_id
  );
end;
$$;

revoke all on function public.registrar_ingreso_factura(uuid, jsonb) from public;
grant execute on function public.registrar_ingreso_factura(uuid, jsonb) to service_role;
