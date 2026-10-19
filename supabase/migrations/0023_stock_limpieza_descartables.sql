-- Gata Maula: stock de LIMPIEZA y DESCARTABLES (de tus planillas) + carga de factura que avisa de productos sin minimo.
--   * crea los insumos de limpieza y descartables con stock en 0 (a contar en la app), con proveedor, dias de pedido,
--     cantidad a pedir y stock minimo (descartables) segun la planilla. Limpieza no tenia minimo: se carga con el boton engranaje.
--     Ojo: los descartables con minimo van a aparecer en Pedidos hasta que cuentes el stock real en la pantalla Stock.
--   * la carga de factura ahora: suma limpieza, descartables y cerveza al stock, copia el proveedor de la factura como
--     proveedor del pedido en productos nuevos, y devuelve la lista de productos sin minimo.
-- Correr DESPUES de 0022_categoria_limpieza.sql. Se puede volver a correr (pisa proveedor, dias, cantidad y minimo; no toca el stock).

do $$
declare t record; k uuid;
begin
  for t in select * from (values
    ('limpieza','ALCOHOL EN GEL X 5 LTS',null,'MARTES X DRIVE','MARILLIM',null),
    ('limpieza','ARRANQUE CHICO 300G',null,'MARTES X DRIVE','MARILLIM',null),
    ('limpieza','BOLSA CONSORCIO 45X60',null,'MARTES X DRIVE','MARILLIM','1'),
    ('limpieza','BOLSA CONSORCIO90X120',null,'MARTES X DRIVE','MARILLIM','1'),
    ('limpieza','BOLSA CONSORCO 60X90',null,'MARTES X DRIVE','MARILLIM','1'),
    ('limpieza','CABO C/ROSCA MADERA',null,'MARTES X DRIVE','MARILLIM','1'),
    ('limpieza','CAMISETA 40X50',null,'MARTES X DRIVE','MARILLIM','1'),
    ('limpieza','CANASTA P/INODORO',null,'MARTES X DRIVE','MARILLIM',null),
    ('limpieza','CIF CREMA X750GRS',null,'MARTES X DRIVE','MARILLIM','1'),
    ('limpieza','DESENGRANSANTE X 5 LTS',null,'MARTES X DRIVE','MARILLIM',null),
    ('limpieza','DETERGENTE X 5LTS',null,'MARTES X DRIVE','MARILLIM','1'),
    ('limpieza','ESCOBILLON RECTO',null,'MARTES X DRIVE','MARILLIM',null),
    ('limpieza','ESPONJAS DE ACERO',null,'MARTES X DRIVE','MARILLIM','1'),
    ('limpieza','ESPONJAS ECO FLEXOL',null,'MARTES X DRIVE','MARILLIM',null),
    ('limpieza','FILM PVC 45CMX600',null,'MARTES X DRIVE','MARILLIM',null),
    ('limpieza','FOLEX- LAMINA',null,'MARTES X DRIVE','MARILLIM','1'),
    ('limpieza','GUANTE NITRILO NEGRO',null,'MARTES X DRIVE','MARILLIM','1 TALLE L'),
    ('limpieza','JABON LIQUIDO P/MANOS 5LTS',null,'MARTES X DRIVE','MARILLIM',null),
    ('limpieza','LAVANDINA X 5LTS',null,'MARTES X DRIVE','MARILLIM','1'),
    ('limpieza','LIMPIA VIDRIOS X5LTS',null,'MARTES X DRIVE','MARILLIM',null),
    ('limpieza','MOPA RESPUESTO',null,'MARTES X DRIVE','MARILLIM',null),
    ('limpieza','PAPEL HIG EXTRA BLANCO',null,'MARTES X DRIVE','MARILLIM',null),
    ('limpieza','PERFUMINA X 5LTS',null,'MARTES X DRIVE','MARILLIM',null),
    ('limpieza','POTE PP 250CC',null,'MARTES X DRIVE','MARILLIM',null),
    ('limpieza','REJILLA PABILLO 220GR',null,'MARTES X DRIVE','MARILLIM','4'),
    ('limpieza','ROLLO LIMPIEZA 400MTSX2',null,'MARTES X DRIVE','MARILLIM','1'),
    ('limpieza','SECADOR DOBLE GOMA',null,'MARTES X DRIVE','MARILLIM',null),
    ('limpieza','SERVILLETA BAR',null,'MARTES X DRIVE','MARILLIM',null),
    ('limpieza','SOLUCION ALCHOLICA X5 LTS',null,'MARTES X DRIVE','MARILLIM',null),
    ('limpieza','TAPA 88 PP',null,'MARTES X DRIVE','MARILLIM','50'),
    ('limpieza','TOALLAS INTERCALADAS',null,'MARTES X DRIVE','MARILLIM',null),
    ('descartables','BOBINA',2,'CUALQUIER DIA X LA TARDE','ELOHIM',null),
    ('descartables','BOLSAS ENVADADORA',2,'CUALQUIER DIA A COORDINAR','CERVENY SAS',null),
    ('descartables','BOLSAS MADERA',20,'MARTES/VIERNES/MIERCOLES/SABADO','TEHILER',null),
    ('descartables','BOLSAS VERMU',20,'MARTES/VIERNES/MIERCOLES/SABADO','TEHILER',null),
    ('descartables','CAJAS',10,'MARTES/VIERNES/MIERCOLES/SABADO','TEHILER',null),
    ('descartables','CAJAS REGALO',20,'MARTES/VIERNES/MIERCOLES/SABADO','TEHILER',null),
    ('descartables','CINTA SCOTCH',1,null,null,null),
    ('descartables','FRASCOS PLASTICO',null,'CUALQUIER DIA X LA TARDE','ELOHIM',null),
    ('descartables','FRASCOS PLASTICOS 250',null,'CUALQUIER DIA X LA TARDE','ELOHIM',null),
    ('descartables','ROLLOS COMANDERAS',2,'SE PASA A COMPRAR','CASA SCHETTINI',null),
    ('descartables','ROLLOS MERCADO PAGO',10,null,'MERCADO PAGO',null),
    ('descartables','ROLLOS POSNET',2,'CUALQUIER DIA X LA TARDE','ELOHIM',null)
  ) as v(sub, nombre, minimo, dias, prov, cant) loop
    k := public._insumo_id(t.sub, t.nombre, null);
    if k is null then
      insert into public.insumos (nombre, marca, grupo, subcategoria, precio_costo_kg, unidad_medida, origen_alta)
        values (t.nombre, null, 'cocina', t.sub::subcategoria_insumo, 0, 'unidad', 'manual')
        returning id into k;
    end if;
    insert into public.stock (insumo_id, cantidad_actual, stock_minimo, valorizacion, unidad, dias_pedido, proveedor_pedido, cantidad_pedido)
      values (k, 0, coalesce(t.minimo, 0), 0, 'unidad', t.dias, t.prov, t.cant)
      on conflict (insumo_id) do update set
        stock_minimo = excluded.stock_minimo, unidad = excluded.unidad, dias_pedido = excluded.dias_pedido,
        proveedor_pedido = excluded.proveedor_pedido, cantidad_pedido = excluded.cantidad_pedido;
  end loop;
end
$$;

-- ============================================================
-- Carga de factura: limpieza / descartables / cerveza tambien van al stock; en productos nuevos el proveedor
-- de la factura queda como proveedor del pedido; avisa de los productos que quedaron sin minimo.
-- ============================================================
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
begin
  if v_proveedor_nombre = '' then
    raise exception 'Falta el nombre del proveedor';
  end if;

  insert into public.proveedores (nombre)
  values (v_proveedor_nombre)
  on conflict (lower(nombre)) do nothing;

  select id into v_proveedor_id from public.proveedores where lower(nombre) = lower(v_proveedor_nombre);

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
      v_sin_stock := v_sin_stock || jsonb_build_object('nombre', v_nombre_insumo, 'categoria', v_categoria, 'total', v_producto->>'total');
      continue;
    end if;

    v_insumo_existente := null;
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

  insert into public.ingresos_egresos (
    fecha, proveedor_id, concepto, factura_numero, remito_numero, monto,
    tiene_iva, iva_pct, estado_pago, medio_pago, fecha_pago, origen, usuario_id, observaciones
  ) values (
    v_fecha, v_proveedor_id,
    coalesce(nullif(p_payload->>'observaciones',''), (p_payload->>'tipo') || ' - ' || v_proveedor_nombre),
    nullif(p_payload->>'numero_factura',''), nullif(p_payload->>'numero_remito',''),
    v_total_factura, v_iva_pct is not null, v_iva_pct,
    case when v_pagado then 'pagado' else 'pendiente' end,
    nullif(p_payload->>'medio_pago',''),
    case when v_pagado then v_fecha else null end,
    'factura', p_usuario_id, nullif(p_payload->>'observaciones','')
  ) returning id into v_ingreso_egreso_id;

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
