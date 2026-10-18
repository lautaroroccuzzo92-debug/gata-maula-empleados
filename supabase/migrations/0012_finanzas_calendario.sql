-- Gata Maula: ingresos/egresos como en tu Excel + calendario de pagos a proveedores.
--   * cada movimiento tiene una "forma" (las columnas de tu hoja EGRESOS):
--       deuda_proveedores, egreso_banco, egreso_efectivo, otras_deudas, otros_ingresos, acred_banco, ahorro
--   * cada proveedor tiene su plazo de pago en dias
--   * calendario_pagos: la lista de pagos a proveedores (como tu hoja "Pago a proveedores");
--     cada deuda que carguen los chicos entra sola al calendario con su vencimiento
--   * la caja diaria guarda cierre del sistema, efectivo real y responsable
--   * las facturas con foto ahora cargan una fila por concepto del estado de resultados
-- Correr UNA vez en el SQL Editor, antes de los archivos de historial (0013 en adelante).

alter table public.ingresos_egresos alter column monto type numeric(14,2);

alter table public.ingresos_egresos add column if not exists forma text
  check (forma in ('otros_ingresos', 'deuda_proveedores', 'otras_deudas', 'ahorro', 'acred_banco', 'egreso_banco', 'egreso_efectivo'));
alter table public.ingresos_egresos add column if not exists lote_importacion text;

-- Lo que ya se cargo desde la app antes de este cambio
update public.ingresos_egresos set
  forma = case when estado_pago = 'pendiente' then 'deuda_proveedores'
               when medio_pago ilike '%efectivo%' then 'egreso_efectivo'
               else 'egreso_banco' end
where forma is null;

create index if not exists ingresos_egresos_concepto_idx on public.ingresos_egresos (concepto);
create index if not exists ingresos_egresos_forma_idx on public.ingresos_egresos (forma);

alter table public.proveedores add column if not exists plazo_pago_dias integer;

alter table public.caja_diaria add column if not exists cierre_sistema numeric(14,2);
alter table public.caja_diaria add column if not exists efectivo_real numeric(14,2);
alter table public.caja_diaria add column if not exists responsable text;

-- Concepto del estado de resultados que corresponde a la categoria de una factura
create or replace function public._concepto_eerr(p_categoria text)
returns text
language sql immutable as $$
  select case upper(coalesce(trim(p_categoria), ''))
    when 'FIAMBRES Y QUESOS' then 'FIAMBRES Y QUESOS'
    when 'VERMUT' then 'VERMUT'
    when 'COCINA' then 'COCINA'
    when 'PAN' then 'PAN'
    when 'INSUMOS DE LIMPIEZA' then 'INSUMOS DE LIMPIEZA'
    when 'DESCARTABLES' then 'DESCARTABLES'
    when 'VERDULERIA' then 'VERDULERIA'
    when 'VERDULERÍA' then 'VERDULERIA'
    when 'COMIDA DE PERSONAL' then 'COMIDA DE PERSONAL'
    when 'CERVEZA Y SIN ALCOHOL' then 'BEBIDA SIN ALCOHOL'
    else 'GASTOS DIARIOS NO CLASIFICADOS' end
$$;

-- ============================================================
-- Calendario de pagos a proveedores (admin)
-- ============================================================
create table if not exists public.calendario_pagos (
  id uuid primary key default gen_random_uuid(),
  fecha_factura date,
  fecha_vencimiento date not null,
  nro_factura text,
  proveedor_id uuid references public.proveedores(id),
  proveedor_texto text not null,
  concepto text,
  total numeric(14,2) not null,
  facturado text,
  pagado boolean not null default false,
  fecha_pago date,
  medio_pago text,
  nota text,
  egreso_id uuid references public.ingresos_egresos(id) on delete set null,
  origen text not null default 'app' check (origen in ('app', 'excel')),
  created_at timestamptz not null default now()
);
create index if not exists calendario_pagos_venc_idx on public.calendario_pagos (fecha_vencimiento) where not pagado;

alter table public.calendario_pagos enable row level security;
drop policy if exists calendario_pagos_select on public.calendario_pagos;
create policy calendario_pagos_select on public.calendario_pagos for select using (public.rol_actual() = 'admin');
drop policy if exists calendario_pagos_update on public.calendario_pagos;
create policy calendario_pagos_update on public.calendario_pagos for update using (public.rol_actual() = 'admin');
drop policy if exists calendario_pagos_insert on public.calendario_pagos;
create policy calendario_pagos_insert on public.calendario_pagos for insert with check (public.rol_actual() = 'admin');
drop policy if exists calendario_pagos_delete on public.calendario_pagos;
create policy calendario_pagos_delete on public.calendario_pagos for delete using (public.rol_actual() = 'admin');

-- Cada deuda con un proveedor que se carga en la app entra sola al calendario
-- (vencimiento = fecha + plazo del proveedor, 7 dias si no tiene plazo cargado).
create or replace function public.trg_deuda_a_calendario()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_plazo integer;
  v_nombre text;
begin
  if new.forma = 'deuda_proveedores' and new.lote_importacion is null then
    select plazo_pago_dias, nombre into v_plazo, v_nombre from public.proveedores where id = new.proveedor_id;
    insert into public.calendario_pagos
      (fecha_factura, fecha_vencimiento, nro_factura, proveedor_id, proveedor_texto, concepto, total, facturado, egreso_id, origen)
    values
      (new.fecha, new.fecha + coalesce(v_plazo, 7), new.factura_numero, new.proveedor_id,
       coalesce(v_nombre, new.concepto), new.concepto, new.monto, case when new.factura_numero is not null then 'SI' else 'NO' end, new.id, 'app');
  end if;
  return new;
end;
$$;
drop trigger if exists ingresos_egresos_a_calendario on public.ingresos_egresos;
create trigger ingresos_egresos_a_calendario
  after insert on public.ingresos_egresos
  for each row execute function public.trg_deuda_a_calendario();

-- Marcar un pago del calendario como pagado. Si viene de una deuda cargada en la app,
-- tambien registra el pago ("PAGO DEUDA PROVEEDORES") para que el estado de resultados lo vea.
create or replace function public.pagar_calendario(p_id uuid, p_forma text, p_fecha date)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  c record;
  v_fecha date := coalesce(p_fecha, current_date);
begin
  if public.rol_actual() <> 'admin' then
    raise exception 'Sin permiso';
  end if;
  if p_forma not in ('egreso_banco', 'egreso_efectivo') then
    raise exception 'Forma de pago invalida';
  end if;
  select * into c from public.calendario_pagos where id = p_id for update;
  if not found then raise exception 'No se encontro el pago'; end if;
  if c.pagado then raise exception 'Este pago ya figura como pagado'; end if;

  update public.calendario_pagos set pagado = true, fecha_pago = v_fecha,
    medio_pago = case when p_forma = 'egreso_banco' then 'banco' else 'efectivo' end
  where id = p_id;

  if c.egreso_id is not null then
    insert into public.ingresos_egresos
      (fecha, proveedor_id, concepto, factura_numero, monto, forma, estado_pago, medio_pago, fecha_pago, origen, usuario_id, observaciones)
    values
      (v_fecha, c.proveedor_id, 'PAGO DEUDA PROVEEDORES', c.nro_factura, c.total, p_forma, 'pagado',
       case when p_forma = 'egreso_banco' then 'banco' else 'efectivo' end, v_fecha, 'manual', auth.uid(),
       'Pago de ' || coalesce(c.concepto, '') || ' del ' || coalesce(c.fecha_factura::text, ''));
    update public.ingresos_egresos set estado_pago = 'pagado', fecha_pago = v_fecha where id = c.egreso_id;
  end if;
  return jsonb_build_object('ok', true);
end;
$$;
grant execute on function public.pagar_calendario(uuid, text, date) to authenticated;

-- ============================================================
-- Facturas con foto: ahora cargan una fila por concepto del estado de resultados
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
  v_forma text;
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

  -- Líneas de producto
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
    elsif v_categoria = 'COCINA' then
      v_grupo := 'cocina'; v_subcategoria := 'cocina';
    elsif v_categoria = 'PAN' then
      v_grupo := 'cocina'; v_subcategoria := 'panes';
    end if;

    if v_subcategoria is null or v_nombre_insumo = '' then
      -- Categoría que no se trackea como insumo/stock (limpieza, descartables, etc.)
      v_sin_stock := v_sin_stock || jsonb_build_object('nombre', v_nombre_insumo, 'categoria', v_categoria, 'total', v_producto->>'total');
      continue;
    end if;

    -- Match exacto o difuso contra insumos existentes de la misma subcategoría
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

    insert into public.stock (insumo_id, cantidad_actual, valorizacion, ultima_actualizacion)
      values (v_insumo_id, v_cantidad, v_cantidad * v_precio_neto, now())
      on conflict (insumo_id) do update set
        cantidad_actual = public.stock.cantidad_actual + excluded.cantidad_actual,
        valorizacion = (public.stock.cantidad_actual + excluded.cantidad_actual) * v_precio_neto,
        ultima_actualizacion = now();

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
      case when v_pagado then 'pagado' else 'pendiente' end,
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
      case when v_pagado then 'pagado' else 'pendiente' end,
      nullif(p_payload->>'medio_pago',''),
      case when v_pagado then v_fecha else null end,
      'factura', p_usuario_id, nullif(p_payload->>'observaciones',''), v_forma
    ) returning id into v_ingreso_egreso_id;
  end if;

  return jsonb_build_object(
    'proveedor', jsonb_build_object('id', v_proveedor_id, 'nombre', v_proveedor_nombre),
    'insumos', v_insumos_resultado,
    'lineas_sin_stock', v_sin_stock,
    'ingreso_egreso_id', v_ingreso_egreso_id
  );
end;
$$;

revoke all on function public.registrar_ingreso_factura(uuid, jsonb) from public;
grant execute on function public.registrar_ingreso_factura(uuid, jsonb) to service_role;
