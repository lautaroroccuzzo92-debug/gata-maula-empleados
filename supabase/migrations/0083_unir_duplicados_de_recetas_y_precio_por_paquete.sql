-- Gata Maula: un solo producto por ingrediente (los de las recetas pasan a ser los del stock) y precio correcto de los productos que vienen por paquete.
--   1) Se unen estos pares (queda el producto que se cuenta en el stock; el precio es el que se indica):
--        ACEITE DE OLIVA 20LTS -> ACEITE DE OLIVA ($10.000) | PIMIENTA NEGRA GRANO -> PIMIENTA NEGRA EN GRANO ($18.480) | TOMATES CHERRY -> TOMATES CHERRYS ($9.000, el del stock)
--        AZUCAR -> AZUCAR LEDESMA ($1.335) | WRAPS GRANDES -> MACHOTE WRAP GRANDE ($550) | MANTECA -> MANTECA TONADITA
--        NAPOLES COCIDO DON ANTONINO y CALCHAQUI JAMON COCIDO -> NAPOLES JAMON COCIDO COLONIAL | CHAMPIGNON GRANDE -> CHAMPI ($33.000)
--        TOMATES DISECADOS -> TOMATES DESHIDRATADOS | CEBOLLA EN POLVO -> CEBOLLA POLVO | AJO EN POLVO -> AJO POLVO | ALBAHACA -> ALBAHACA FRESCA
--        MIEL -> MIEL (KG) | GELATINA SIN SABOR -> GELATIN SIN SABOR | LECHUGA REPOLLADA -> ZECOR LECHUGA REPOLLADA | MORTADELLA PISTACHIO GRASETTO -> NAPOLES MORTADELA CON PISTACHOS GRASETTO
--        ACEITE DE GIRASOL BARBIERI 10LTS -> ACEITE GIRASOL | HONGOS DE PINO -> HONGOS DESHIDRATADOS | VINAGRE DE ALCOHOL MENOYO 10LTS -> VINAGRE ($1.116) | LECHE ENTERA LARGA VIDA -> LECHE (UNIDAD - CAJA)
--      Las recetas que usaban el producto que se borra pasan a usar el que queda.
--   2) ROMERO: un solo producto, que se cuenta en PAQUETES (de 70 g); el precio por kilo sigue siendo $21.470 y las recetas siguen en gramos
--      (cada receta descuenta la fraccion de paquete que corresponde).
--   3) Facturas: si el producto viene por paquete (tiene "gramos del paquete") y la factura trae unidades, el precio por kilo se calcula bien
--      (antes se guardaba el precio del paquete como si fuera por kilo).
-- ANTES de correrla: bajar una copia de seguridad (Ajustes > Copia de seguridad), porque unir borra el producto sobrante.
-- Correr UNA vez en el SQL Editor y mandar el resultado. Es seguro correrlo mas de una vez.

create or replace function pg_temp._unir(p_conservar uuid, p_quitar uuid) returns void
language plpgsql as $$
begin
  update public.recetas set insumo_id = p_conservar where insumo_id = p_quitar;
  update public.factura_items set insumo_id = p_conservar where insumo_id = p_quitar;
  delete from public.pos_vinculo v where v.insumo_id = p_quitar
     and exists (select 1 from public.pos_vinculo x where x.producto = v.producto and x.insumo_id = p_conservar);
  update public.pos_vinculo set insumo_id = p_conservar where insumo_id = p_quitar;
  update public.pos_consumo set insumo_id = p_conservar where insumo_id = p_quitar;
  perform public.insumo_unir_sistema(p_conservar, p_quitar);
end
$$;

drop table if exists _res83;
create temp table _res83 (orden serial, seccion text, producto text, detalle text);

-- ============================================================ 1) pares de productos repetidos
do $$
declare
  r record; v_con uuid; v_quit uuid;
begin
  perform set_config('app.sin_historial', 'on', true);
  for r in select * from (values
      ('ACEITE DE OLIVA',                          'ACEITE DE OLIVA 20LTS',                       10000::numeric),
      ('PIMIENTA NEGRA EN GRANO',                  'PIMIENTA NEGRA GRANO',                        18480),
      ('TOMATES CHERRYS',                          'TOMATES CHERRY',                              null),
      ('AZUCAR LEDESMA',                           'AZUCAR',                                      1335),
      ('MACHOTE WRAP GRANDE',                      'WRAPS GRANDES',                               550),
      ('MANTECA TONADITA',                         'MANTECA',                                     null),
      ('NAPOLES JAMON COCIDO COLONIAL',            'NAPOLES COCIDO DON ANTONINO',                 null),
      ('NAPOLES JAMON COCIDO COLONIAL',            'CALCHAQUI JAMON COCIDO',                      null),
      ('CHAMPI',                                   'CHAMPIGNON GRANDE',                           33000),
      ('TOMATES DESHIDRATADOS',                    'TOMATES DISECADOS',                           null),
      ('CEBOLLA POLVO',                            'CEBOLLA EN POLVO',                            null),
      ('AJO POLVO',                                'AJO EN POLVO',                                null),
      ('ALBAHACA FRESCA',                          'ALBAHACA',                                    null),
      ('MIEL (KG)',                                'MIEL',                                        null),
      ('GELATIN SIN SABOR',                        'GELATINA SIN SABOR',                          null),
      ('ZECOR LECHUGA REPOLLADA',                  'LECHUGA REPOLLADA',                           null),
      ('NAPOLES MORTADELA CON PISTACHOS GRASETTO', 'NAPOLES MORTADELLA CON PISTACHIO GRASETTO',   null),
      ('ACEITE GIRASOL',                           'ACEITE DE GIRASOL BARBIERI 10LTS',            null),
      ('HONGOS DESHIDRATADOS',                     'HONGOS DE PINO',                              null),
      ('VINAGRE',                                  'VINAGRE DE ALCOHOL MENOYO 10LTS',             1116),
      ('LECHE (UNIDAD - CAJA)',                    'LECHE ENTERA LARGA VIDA',                     null),
      ('ROMERO PAQUETES',                          'ROMERO',                                      null)
    ) as t(conservar, quitar, precio)
  loop
    select i.id into v_con from public.insumos i left join public.stock s on s.insumo_id = i.id
     where public.normalizar_texto(trim(coalesce(i.marca || ' ', '') || i.nombre)) = r.conservar
     order by (s.insumo_id is not null) desc, i.id limit 1;
    select i.id into v_quit from public.insumos i
     where public.normalizar_texto(trim(coalesce(i.marca || ' ', '') || i.nombre)) = r.quitar and i.id is distinct from v_con
     order by i.id limit 1;
    if v_con is null then
      insert into _res83 (seccion, producto, detalle) values ('UNION', r.quitar, 'NO ENCONTRE "' || r.conservar || '": no se unio');
    elsif v_quit is null then
      insert into _res83 (seccion, producto, detalle) values ('UNION', r.quitar, 'no hay otra copia: nada que unir (o ya estaba unido)');
    else
      perform pg_temp._unir(v_con, v_quit);
      insert into _res83 (seccion, producto, detalle) values ('UNION', r.quitar, 'UNIDO con ' || r.conservar);
    end if;
    if v_con is not null and r.precio is not null then
      update public.insumos set precio_costo_kg = r.precio, fecha_ultima_actualizacion = now() where id = v_con;
    end if;
  end loop;
end
$$;

-- ============================================================ 2) romero: se cuenta en paquetes de 70 g (precio por kilo $21.470 = $1.503 el paquete)
do $$
declare v uuid; s record;
begin
  select i.id into v from public.insumos i join public.stock st on st.insumo_id = i.id
   where public.normalizar_texto(trim(coalesce(i.marca || ' ', '') || i.nombre)) = 'ROMERO PAQUETES' limit 1;
  if v is null then
    insert into _res83 (seccion, producto, detalle) values ('ROMERO', 'ROMERO PAQUETES', 'NO ENCONTRE el romero del stock');
  else
    select * into s from public.stock where insumo_id = v;
    update public.insumos set gramos_paquete = 70, precio_costo_kg = 21470, fecha_ultima_actualizacion = now() where id = v;
    -- si lo contado estaba en kilos, pasa a paquetes (55 g = 0,79 paquete)
    update public.stock set unidad = 'unidad',
           cantidad_actual = case when coalesce(s.unidad, 'kg') = 'kg' then round(s.cantidad_actual * 1000 / 70, 3) else s.cantidad_actual end,
           stock_minimo = case when coalesce(s.unidad, 'kg') = 'kg' then round(s.stock_minimo * 1000 / 70, 3) else s.stock_minimo end
     where insumo_id = v;
    update public.stock set valorizacion = cantidad_actual * 21470 * 0.07 where insumo_id = v;
    insert into _res83 (seccion, producto, detalle) values ('ROMERO', 'ROMERO PAQUETES', 'se cuenta en paquetes de 70 g · $21470 el kilo · las recetas descuentan fraccion de paquete');
  end if;
end
$$;

-- ============================================================ 3) facturas: precio por kilo correcto en productos por paquete
create or replace function public.registrar_ingreso_factura(p_usuario_id uuid, p_payload jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_proveedor_nombre text := trim(p_payload->>'proveedor');
  v_iva_pct numeric := nullif(p_payload->>'iva_pct','')::numeric;
  v_fecha date := coalesce((p_payload->>'fecha')::date, current_date);
  v_pagado boolean := coalesce((p_payload->>'pagado')::boolean, false);
  v_total_factura numeric := coalesce((p_payload->>'total_factura')::numeric, 0);
  v_comprobante uuid := gen_random_uuid();
  v_fact_num text := nullif(p_payload->>'numero_factura','');
  v_rem_num text := nullif(p_payload->>'numero_remito','');
  v_proveedor_id uuid;
  v_producto jsonb;
  v_categoria text;
  v_nombre_insumo text;
  v_subcategoria subcategoria_insumo;
  v_grupo grupo_insumo;
  v_cantidad numeric;
  v_unidad_txt text;
  v_total_linea numeric;
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
  v_tiene_stock boolean;
  v_sumar boolean;
  v_reemplaza uuid;
  v_reemplazos int := 0;
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
    v_unidad_txt := case when nullif(v_producto->>'kg_litros', '') is not null then 'kg/l'
                         when nullif(v_producto->>'unidades', '') is not null then 'unid' else null end;
    v_total_linea := nullif(v_producto->>'total', '')::numeric;

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
      insert into public.factura_items (comprobante_id, fecha, proveedor_id, factura_numero, remito_numero, insumo_id, descripcion, categoria, cantidad, unidad, precio_unitario, total)
        values (v_comprobante, v_fecha, v_proveedor_id, v_fact_num, v_rem_num, null, coalesce(nullif(v_nombre_insumo, ''), 'Sin descripción'), v_categoria,
                v_cantidad, v_unidad_txt, v_precio_unit, coalesce(v_total_linea, round(v_cantidad * v_precio_unit, 2)));
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
        precio_costo_kg = case when coalesce(gramos_paquete, 0) > 0 and v_unidad_txt = 'unid'
                               then round(v_precio_neto * 1000 / gramos_paquete, 2) else v_precio_neto end,
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

    -- Si este producto reemplaza a un insumo que ya se usaba en recetas, las recetas pasan al nuevo
    v_reemplaza := nullif(v_producto->>'reemplaza_insumo_id', '')::uuid;
    if v_reemplaza is not null and v_reemplaza <> v_insumo_id then
      update public.receta_insumos set insumo_id = v_insumo_id where insumo_id = v_reemplaza;
      perform public._recalcular_costo_recetas(v_insumo_id);
      v_reemplazos := v_reemplazos + 1;
    end if;

    -- Stock: si el insumo ya esta en el stock, siempre suma; si no, solo cuando la persona eligio sumarlo
    select exists (select 1 from public.stock where insumo_id = v_insumo_id) into v_tiene_stock;
    v_sumar := coalesce((v_producto->>'sumar_stock')::boolean, true);
    if v_tiene_stock or v_sumar then
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
    end if;

    v_insumos_resultado := v_insumos_resultado || jsonb_build_object(
      'id', v_insumo_id, 'nombre', v_nombre_insumo, 'precio_costo_kg', v_precio_neto, 'cantidad', v_cantidad
    );

    insert into public.factura_items (comprobante_id, fecha, proveedor_id, factura_numero, remito_numero, insumo_id, descripcion, categoria, cantidad, unidad, precio_unitario, total)
      values (v_comprobante, v_fecha, v_proveedor_id, v_fact_num, v_rem_num, v_insumo_id, v_nombre_insumo, v_categoria,
              v_cantidad, v_unidad_txt, v_precio_unit, coalesce(v_total_linea, round(v_cantidad * v_precio_unit, 2)));
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
      tiene_iva, iva_pct, estado_pago, medio_pago, fecha_pago, origen, usuario_id, observaciones, forma, comprobante_id
    ) values (
      v_fecha, v_proveedor_id, v_conc.concepto,
      v_fact_num, v_rem_num,
      v_monto_fila, v_iva_pct is not null, v_iva_pct,
      v_estado,
      nullif(p_payload->>'medio_pago',''),
      case when v_pagado then v_fecha else null end,
      'factura', p_usuario_id, nullif(p_payload->>'observaciones',''), v_forma, v_comprobante
    ) returning id into v_ingreso_egreso_id;
    v_filas_ie := v_filas_ie + 1;
  end loop;

  if v_filas_ie = 0 then
    insert into public.ingresos_egresos (
      fecha, proveedor_id, concepto, factura_numero, remito_numero, monto,
      tiene_iva, iva_pct, estado_pago, medio_pago, fecha_pago, origen, usuario_id, observaciones, forma, comprobante_id
    ) values (
      v_fecha, v_proveedor_id, 'GASTOS DIARIOS NO CLASIFICADOS',
      v_fact_num, v_rem_num,
      v_total_factura, v_iva_pct is not null, v_iva_pct,
      v_estado,
      nullif(p_payload->>'medio_pago',''),
      case when v_pagado then v_fecha else null end,
      'factura', p_usuario_id, nullif(p_payload->>'observaciones',''), v_forma, v_comprobante
    ) returning id into v_ingreso_egreso_id;
  end if;

  return jsonb_build_object(
    'proveedor', jsonb_build_object('id', v_proveedor_id, 'nombre', v_proveedor_nombre),
    'insumos', v_insumos_resultado,
    'lineas_sin_stock', v_sin_stock,
    'sin_minimo', v_sin_minimo,
    'reemplazos', v_reemplazos,
    'ingreso_egreso_id', v_ingreso_egreso_id,
    'comprobante_id', v_comprobante
  );
end;
$$;

revoke all on function public.registrar_ingreso_factura(uuid, jsonb) from public;
grant execute on function public.registrar_ingreso_factura(uuid, jsonb) to service_role;

-- ============================================================ recalcular y resultado
select public._recalcular_costo_recetas(null) as recetas_recalculadas;

select x.seccion, x.producto, x.detalle
  from (
    select orden, seccion, producto, detalle from _res83
    union all
    select 1000 + row_number() over (order by trim(coalesce(i.marca || ' ', '') || i.nombre)), 'POR PAQUETE (revisar el precio por kilo)',
           trim(coalesce(i.marca || ' ', '') || i.nombre),
           i.gramos_paquete || ' g el paquete · $' || round(i.precio_costo_kg, 0) || ' el kilo · $' || round(i.precio_costo_kg * i.gramos_paquete / 1000, 0) || ' el paquete'
      from public.insumos i where coalesce(i.gramos_paquete, 0) > 0
  ) x
 order by x.orden;
