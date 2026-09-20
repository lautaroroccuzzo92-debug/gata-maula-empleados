-- Gata Maula — Fase 1: esquema Supabase (reemplaza Google Sheets + Apps Script)
-- Aplicar con: supabase db push  (o pegar en el SQL editor del proyecto)

create extension if not exists pgcrypto;   -- gen_random_uuid()
create extension if not exists unaccent;   -- matching de nombres sin acentos

-- ============================================================
-- ENUMS
-- ============================================================

create type rol_usuario as enum ('admin', 'encargado', 'cocina');

-- Categoría amplia tal cual la produce hoy el prompt de analyze.js (CATEGORIAS
-- del cliente). Se mantiene sin cambios en Fase 1 porque analyze.js no se toca.
create type categoria_compra as enum (
  'FIAMBRES Y QUESOS', 'VERMUT', 'COCINA', 'INSUMOS DE LIMPIEZA', 'PAN',
  'DESCARTABLES', 'VERDULERÍA', 'COMIDA DE PERSONAL', 'OTROS'
);

-- Subcategoría angosta del prompt del usuario, solo para ítems que se
-- promueven a insumo de receta (no toda compra se convierte en insumo).
create type grupo_insumo as enum ('bebidas', 'cocina');
create type subcategoria_insumo as enum (
  'vermut', 'cerveza y sin alcohol', 'fiambres', 'quesos', 'cocina', 'panes'
);

create type origen_dato as enum ('factura', 'manual');
create type tipo_movimiento_stock as enum ('ingreso', 'egreso_venta', 'desperdicio');
create type estado_pago_tipo as enum ('pagado', 'pendiente');

-- ============================================================
-- TABLAS
-- ============================================================

-- 1:1 con auth.users — sin password_hash propio, Supabase Auth ya lo maneja.
create table public.usuarios (
  id uuid primary key references auth.users(id) on delete cascade,
  nombre text not null,
  rol rol_usuario not null,
  activo boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.proveedores (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  categoria_default categoria_compra,
  created_at timestamptz not null default now()
);
create unique index proveedores_nombre_lower_idx on public.proveedores (lower(nombre));

create table public.insumos (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  grupo grupo_insumo not null,
  subcategoria subcategoria_insumo not null,
  proveedor_id uuid references public.proveedores(id),
  precio_costo_kg numeric(12,2) not null default 0,
  precio_venta_publico numeric(12,2),
  origen_alta origen_dato not null default 'manual',
  fecha_ultima_actualizacion timestamptz not null default now()
);
create index insumos_subcategoria_idx on public.insumos (subcategoria);

create table public.margenes_subcategoria (
  id uuid primary key default gen_random_uuid(),
  subcategoria subcategoria_insumo not null unique,
  porcentaje_margen numeric(5,2) not null default 60
);
insert into public.margenes_subcategoria (subcategoria, porcentaje_margen)
values ('vermut',60),('cerveza y sin alcohol',60),('fiambres',60),('quesos',60),('cocina',60),('panes',60);

create table public.recetas (
  id uuid primary key default gen_random_uuid(),
  nombre_producto text not null,
  categoria_carta text not null,
  preparacion text,
  costo_total_calculado numeric(12,2),
  margen_objetivo numeric(5,2) not null default 65,
  precio_venta_sugerido numeric(12,2),
  created_at timestamptz not null default now()
);

create table public.receta_insumos (
  id uuid primary key default gen_random_uuid(),
  receta_id uuid not null references public.recetas(id) on delete cascade,
  insumo_id uuid not null references public.insumos(id),
  cantidad_gramos numeric(12,2) not null
);

create table public.stock (
  id uuid primary key default gen_random_uuid(),
  insumo_id uuid not null references public.insumos(id) unique,
  cantidad_actual numeric(12,3) not null default 0,
  stock_minimo numeric(12,3) not null default 0,
  valorizacion numeric(12,2) not null default 0,
  ultima_actualizacion timestamptz not null default now()
);

create table public.movimientos_stock (
  id uuid primary key default gen_random_uuid(),
  insumo_id uuid not null references public.insumos(id),
  tipo tipo_movimiento_stock not null,
  cantidad numeric(12,3) not null,
  origen origen_dato not null,
  usuario_id uuid not null references public.usuarios(id),
  fecha timestamptz not null default now()
);
create index movimientos_stock_insumo_idx on public.movimientos_stock (insumo_id, fecha desc);

create table public.desperdicio (
  id uuid primary key default gen_random_uuid(),
  fecha date not null default current_date,
  insumo_id uuid not null references public.insumos(id),
  motivo text not null,
  cantidad numeric(12,3) not null,
  valor_calculado numeric(12,2),
  usuario_id uuid not null references public.usuarios(id),
  created_at timestamptz not null default now()
);

create table public.ingresos_egresos (
  id uuid primary key default gen_random_uuid(),
  fecha date not null,
  proveedor_id uuid references public.proveedores(id),
  concepto text not null,
  factura_numero text,
  remito_numero text,
  monto numeric(12,2) not null,
  tiene_iva boolean not null default false,
  iva_pct numeric(5,2),
  estado_pago estado_pago_tipo not null default 'pendiente',
  medio_pago text,
  fecha_pago date,
  origen origen_dato not null,
  usuario_id uuid not null references public.usuarios(id),
  insumo_relacionado_id uuid references public.insumos(id),
  observaciones text,
  created_at timestamptz not null default now()
);
create index ingresos_egresos_fecha_idx on public.ingresos_egresos (fecha desc);

create table public.caja_diaria (
  id uuid primary key default gen_random_uuid(),
  fecha date not null unique,
  tarjeta_credito numeric(12,2) not null default 0,
  tarjeta_debito numeric(12,2) not null default 0,
  transferencia numeric(12,2) not null default 0,
  qr_posnet numeric(12,2) not null default 0,
  qr_mercado_pago numeric(12,2) not null default 0,
  efectivo numeric(12,2) not null default 0,
  venta_total numeric(12,2) generated always as
    (tarjeta_credito + tarjeta_debito + transferencia + qr_posnet + qr_mercado_pago + efectivo) stored,
  usuario_id uuid not null references public.usuarios(id),
  created_at timestamptz not null default now()
);

-- Placeholder de esquema para la Fase 2 (EERR automático). Vacía en Fase 1.
create table public.estado_resultados_mensual (
  id uuid primary key default gen_random_uuid(),
  mes date not null unique,
  total_ventas numeric(12,2),
  costo_mercaderia numeric(12,2),
  costo_laboral numeric(12,2),
  gastos_fijos numeric(12,2),
  resultado_final numeric(12,2),
  punto_equilibrio numeric(12,2),
  calculado_en timestamptz
);

-- ============================================================
-- HELPERS DE MATCHING (portados de normalizarTexto/similitudPalabras
-- del cliente — fallback documentado hasta tener el Apps Script real)
-- ============================================================

create or replace function public.normalizar_texto(txt text) returns text
language sql immutable as $$
  select upper(unaccent(trim(coalesce(txt, ''))))
$$;

create or replace function public.similitud_palabras(a text, b text) returns numeric
language plpgsql immutable as $$
declare
  wa text[];
  wb text[];
  comunes int;
begin
  if coalesce(a, '') = '' or coalesce(b, '') = '' then
    return 0;
  end if;
  wa := regexp_split_to_array(trim(a), '\s+');
  wb := regexp_split_to_array(trim(b), '\s+');
  select count(*) into comunes from unnest(wa) w where w = any(wb);
  return comunes::numeric / greatest(array_length(wa,1), array_length(wb,1));
end;
$$;

-- ============================================================
-- ROL DEL USUARIO ACTUAL (para políticas RLS)
-- ============================================================

create or replace function public.rol_actual() returns rol_usuario
language sql stable security definer set search_path = public as $$
  select rol from public.usuarios where id = auth.uid()
$$;

-- ============================================================
-- RLS
-- ============================================================

alter table public.usuarios enable row level security;
alter table public.proveedores enable row level security;
alter table public.insumos enable row level security;
alter table public.margenes_subcategoria enable row level security;
alter table public.recetas enable row level security;
alter table public.receta_insumos enable row level security;
alter table public.stock enable row level security;
alter table public.movimientos_stock enable row level security;
alter table public.desperdicio enable row level security;
alter table public.ingresos_egresos enable row level security;
alter table public.caja_diaria enable row level security;
alter table public.estado_resultados_mensual enable row level security;

-- usuarios
create policy usuarios_select on public.usuarios for select
  using (id = auth.uid() or public.rol_actual() = 'admin');
create policy usuarios_update_admin on public.usuarios for update
  using (public.rol_actual() = 'admin');

-- proveedores (lectura: los 3 roles; escritura: admin+encargado)
create policy proveedores_select on public.proveedores for select
  using (auth.role() = 'authenticated');
create policy proveedores_insert on public.proveedores for insert
  with check (public.rol_actual() in ('admin','encargado'));
create policy proveedores_update on public.proveedores for update
  using (public.rol_actual() in ('admin','encargado'));

-- insumos (lectura: los 3 roles; escritura: admin+encargado)
create policy insumos_select on public.insumos for select
  using (auth.role() = 'authenticated');
create policy insumos_insert on public.insumos for insert
  with check (public.rol_actual() in ('admin','encargado'));
create policy insumos_update on public.insumos for update
  using (public.rol_actual() in ('admin','encargado'));

-- margenes_subcategoria (lectura: admin+encargado; escritura: admin)
create policy margenes_select on public.margenes_subcategoria for select
  using (public.rol_actual() in ('admin','encargado'));
create policy margenes_update_admin on public.margenes_subcategoria for update
  using (public.rol_actual() = 'admin');

-- recetas / receta_insumos (admin+encargado, cocina no las necesita por spec)
create policy recetas_select on public.recetas for select
  using (public.rol_actual() in ('admin','encargado'));
create policy recetas_insert on public.recetas for insert
  with check (public.rol_actual() in ('admin','encargado'));
create policy recetas_update on public.recetas for update
  using (public.rol_actual() in ('admin','encargado'));
create policy recetas_delete on public.recetas for delete
  using (public.rol_actual() in ('admin','encargado'));

create policy receta_insumos_select on public.receta_insumos for select
  using (public.rol_actual() in ('admin','encargado'));
create policy receta_insumos_insert on public.receta_insumos for insert
  with check (public.rol_actual() in ('admin','encargado'));
create policy receta_insumos_update on public.receta_insumos for update
  using (public.rol_actual() in ('admin','encargado'));
create policy receta_insumos_delete on public.receta_insumos for delete
  using (public.rol_actual() in ('admin','encargado'));

-- stock (lectura: los 3 roles; corrección manual de mínimos: admin)
-- Los ingresos/egresos de cantidad_actual sólo ocurren vía las funciones
-- RPC de abajo (SECURITY DEFINER, corren como dueño de la tabla y no
-- necesitan policy de insert/update propia).
create policy stock_select on public.stock for select
  using (auth.role() = 'authenticated');
create policy stock_update_admin on public.stock for update
  using (public.rol_actual() = 'admin');

-- movimientos_stock (lectura: los 3 roles; escritura sólo vía RPC)
create policy movimientos_stock_select on public.movimientos_stock for select
  using (auth.role() = 'authenticated');

-- desperdicio (lectura: los 3 roles; escritura sólo vía RPC registrar_desperdicio)
create policy desperdicio_select on public.desperdicio for select
  using (auth.role() = 'authenticated');

-- ingresos_egresos (admin+encargado únicamente, cocina no tiene acceso)
create policy ingresos_egresos_select on public.ingresos_egresos for select
  using (public.rol_actual() in ('admin','encargado'));
create policy ingresos_egresos_insert on public.ingresos_egresos for insert
  with check (public.rol_actual() in ('admin','encargado'));
create policy ingresos_egresos_update on public.ingresos_egresos for update
  using (public.rol_actual() in ('admin','encargado'));

-- caja_diaria (admin+encargado únicamente)
create policy caja_diaria_select on public.caja_diaria for select
  using (public.rol_actual() in ('admin','encargado'));
create policy caja_diaria_insert on public.caja_diaria for insert
  with check (public.rol_actual() in ('admin','encargado'));
create policy caja_diaria_update on public.caja_diaria for update
  using (public.rol_actual() in ('admin','encargado'));

-- estado_resultados_mensual (lectura admin; escritura sólo Fase 2, sin policy de insert/update)
create policy eerr_mensual_select on public.estado_resultados_mensual for select
  using (public.rol_actual() = 'admin');

-- ============================================================
-- RPC: registrar_ingreso_factura
-- Invocada SOLO desde api/registrar-ingreso.js (service_role), que ya
-- verificó el JWT del usuario y le pasa su id explícitamente. Reemplaza
-- la atomicidad que antes daba el webhook único de Apps Script.
--
-- Mapeo categoria_compra -> insumo (sólo estas 4 producen insumo/stock;
-- limpieza/descartables/verdulería/comida de personal/otros quedan sólo
-- como línea de ingresos_egresos, sin impacto de stock/receta):
--   FIAMBRES Y QUESOS -> subcategoria 'quesos' si el nombre contiene
--                        "queso", si no 'fiambres'; grupo 'cocina'
--   VERMUT            -> subcategoria 'vermut'; grupo 'bebidas'
--   COCINA            -> subcategoria 'cocina'; grupo 'cocina'
--   PAN               -> subcategoria 'panes'; grupo 'cocina'
--
-- precio_costo_kg se guarda NETO de IVA (fórmula de respaldo documentada:
-- precio_con_iva / (1 + iva_pct/100); si no hay iva_pct discriminado, se
-- guarda el precio tal cual, igual que hacía PPTO). Esto es un placeholder
-- hasta portar la fórmula real del Apps Script.
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
      where subcategoria = v_subcategoria and lower(nombre) = lower(v_nombre_insumo)
      limit 1;

    if v_insumo_existente.id is null then
      select id, nombre, public.similitud_palabras(public.normalizar_texto(nombre), public.normalizar_texto(v_nombre_insumo)) as score
        into v_candidato
        from public.insumos where subcategoria = v_subcategoria
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
    'ingreso_egreso_id', v_ingreso_egreso_id
  );
end;
$$;

revoke all on function public.registrar_ingreso_factura(uuid, jsonb) from public;
grant execute on function public.registrar_ingreso_factura(uuid, jsonb) to service_role;

-- ============================================================
-- RPC: registrar_desperdicio
-- Invocada directamente desde el navegador (anon key + sesión del
-- usuario) — usa auth.uid() internamente, no confía en un parámetro.
-- ============================================================

create or replace function public.registrar_desperdicio(
  p_insumo_id uuid, p_cantidad numeric, p_motivo text, p_fecha date default current_date
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_usuario_id uuid := auth.uid();
  v_precio numeric;
  v_valor numeric;
  v_id uuid;
begin
  if v_usuario_id is null then
    raise exception 'No autenticado';
  end if;
  if public.rol_actual() not in ('admin','encargado','cocina') then
    raise exception 'Sin permiso';
  end if;
  if p_cantidad is null or p_cantidad <= 0 then
    raise exception 'Cantidad inválida';
  end if;

  select precio_costo_kg into v_precio from public.insumos where id = p_insumo_id;
  if v_precio is null then
    raise exception 'Insumo no encontrado';
  end if;
  v_valor := round(p_cantidad * v_precio, 2);

  insert into public.desperdicio (fecha, insumo_id, motivo, cantidad, valor_calculado, usuario_id)
    values (p_fecha, p_insumo_id, p_motivo, p_cantidad, v_valor, v_usuario_id)
    returning id into v_id;

  insert into public.movimientos_stock (insumo_id, tipo, cantidad, origen, usuario_id)
    values (p_insumo_id, 'desperdicio', p_cantidad, 'manual', v_usuario_id);

  update public.stock set
    cantidad_actual = greatest(0, cantidad_actual - p_cantidad),
    valorizacion = greatest(0, cantidad_actual - p_cantidad) * v_precio,
    ultima_actualizacion = now()
    where insumo_id = p_insumo_id;

  return jsonb_build_object('id', v_id, 'valor_calculado', v_valor);
end;
$$;

grant execute on function public.registrar_desperdicio(uuid, numeric, text, date) to authenticated;

-- ============================================================
-- RPC: confirmar_match_insumo
-- Fusiona un insumo creado por error (ej. duplicado por typo) dentro de
-- otro ya existente, reasignando todo lo que lo referencia. Reemplaza el
-- flujo manual "confirmarMatchPpto" del Apps Script viejo — simplificado
-- para Fase 1, a revisar cuando llegue la lógica real.
-- Invocada SOLO desde api/confirmar-match-insumo.js (service_role).
-- ============================================================

create or replace function public.confirmar_match_insumo(p_insumo_origen_id uuid, p_insumo_destino_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if p_insumo_origen_id = p_insumo_destino_id then
    raise exception 'El insumo origen y destino no pueden ser el mismo';
  end if;

  update public.movimientos_stock set insumo_id = p_insumo_destino_id where insumo_id = p_insumo_origen_id;
  update public.desperdicio set insumo_id = p_insumo_destino_id where insumo_id = p_insumo_origen_id;
  update public.receta_insumos set insumo_id = p_insumo_destino_id where insumo_id = p_insumo_origen_id;
  update public.ingresos_egresos set insumo_relacionado_id = p_insumo_destino_id where insumo_relacionado_id = p_insumo_origen_id;

  update public.stock d set
    cantidad_actual = d.cantidad_actual + coalesce((select cantidad_actual from public.stock where insumo_id = p_insumo_origen_id), 0)
    where d.insumo_id = p_insumo_destino_id;
  delete from public.stock where insumo_id = p_insumo_origen_id;
  delete from public.insumos where id = p_insumo_origen_id;

  return jsonb_build_object('success', true, 'insumo_id', p_insumo_destino_id);
end;
$$;

revoke all on function public.confirmar_match_insumo(uuid, uuid) from public;
grant execute on function public.confirmar_match_insumo(uuid, uuid) to service_role;
