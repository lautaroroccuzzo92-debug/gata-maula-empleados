-- Gata Maula: los insumos pasan a ser la hoja "Costos Variables" del PPTO.
--   * categorias nuevas: Kutsi y Descartables y packaging
--   * marca de cada producto, y "preparaciones" (recetas caseras como el dip
--     mediterraneo, que se usan como ingrediente de otras recetas)
--   * cuando cambia el precio de un insumo se recalculan las preparaciones que
--     lo usan y, en cascada, todas las recetas
--   * crear_insumo(): alta de un insumo nuevo desde la app
-- Correr UNA vez en el SQL Editor, antes de 0009_import_costos_variables.sql.

alter type subcategoria_insumo add value if not exists 'kutsi';
alter type subcategoria_insumo add value if not exists 'descartables';

alter table public.insumos add column if not exists marca text;
alter table public.insumos add column if not exists unidad_medida text not null default 'kg'
  check (unidad_medida in ('kg', 'unidad'));
alter table public.insumos add column if not exists es_preparacion boolean not null default false;

alter table public.recetas add column if not exists tipo text not null default 'plato'
  check (tipo in ('plato', 'preparacion'));
alter table public.recetas add column if not exists merma_pct numeric(5,2) not null default 0;
alter table public.recetas add column if not exists insumo_id uuid references public.insumos(id) on delete set null;

-- Cantidades fraccionarias (ej. 1/9 de un pan de molde).
alter table public.receta_insumos alter column cantidad type numeric(14,6);

-- Busca un insumo por categoria + nombre + marca (usado por el import).
create or replace function public._insumo_id(p_sub text, p_nombre text, p_marca text)
returns uuid
language sql stable set search_path = public as $$
  select id from public.insumos
   where subcategoria::text = p_sub
     and lower(nombre) = lower(p_nombre)
     and lower(coalesce(marca, '')) = lower(coalesce(p_marca, ''))
   order by fecha_ultima_actualizacion desc, id
   limit 1
$$;

-- Recalcula el costo de las recetas que usan p_insumo_id (o de todas si es
-- null). Si la receta es una preparacion, ademas actualiza el precio por kg de
-- su insumo, lo que dispara el recalculo de las recetas que la usan.
--   costo por kg = costo total x 1000 / (gramos totales x (1 - merma))
create or replace function public._recalcular_costo_recetas(p_insumo_id uuid)
returns integer
language plpgsql security definer set search_path = public as $$
declare
  r record;
  v_tipo text;
  v_merma numeric;
  v_insumo_prep uuid;
  v_filas integer := 0;
begin
  for r in
    select ri.receta_id,
           sum(case when ri.tipo_medida = 'unidad'
                    then ri.cantidad * i.precio_costo_kg
                    else ri.cantidad / 1000 * i.precio_costo_kg end) as costo,
           sum(case when ri.tipo_medida = 'gramos' then ri.cantidad else 0 end) as gramos
      from public.receta_insumos ri
      join public.insumos i on i.id = ri.insumo_id
     where p_insumo_id is null
        or ri.receta_id in (select receta_id from public.receta_insumos where insumo_id = p_insumo_id)
     group by ri.receta_id
  loop
    update public.recetas set costo_total_calculado = round(r.costo, 2) where id = r.receta_id;
    v_filas := v_filas + 1;
    select tipo, merma_pct, insumo_id into v_tipo, v_merma, v_insumo_prep from public.recetas where id = r.receta_id;
    if v_tipo = 'preparacion' and v_insumo_prep is not null and r.gramos > 0 and (1 - v_merma / 100) > 0 then
      update public.insumos
         set precio_costo_kg = r.costo * 1000 / (r.gramos * (1 - v_merma / 100)),
             fecha_ultima_actualizacion = now()
       where id = v_insumo_prep;
    end if;
  end loop;
  return v_filas;
end;
$$;
revoke all on function public._recalcular_costo_recetas(uuid) from public;

create or replace function public.trg_insumo_precio_cambio()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_var numeric;
begin
  -- Los imports masivos desde el SQL Editor pueden apagar el historial con:
  --   select set_config('app.sin_historial', 'on', true);
  if current_setting('app.sin_historial', true) = 'on' then
    return new;
  end if;
  if pg_trigger_depth() > 10 then
    return new; -- corta una preparacion que se use a si misma
  end if;
  if new.precio_costo_kg is distinct from old.precio_costo_kg then
    -- Las preparaciones se recalculan solas: no generan historial ni alerta.
    if not new.es_preparacion then
      if old.precio_costo_kg > 0 then
        v_var := round((new.precio_costo_kg - old.precio_costo_kg) / old.precio_costo_kg * 100, 2);
      end if;
      insert into public.historial_precios
        (insumo_id, precio_anterior, precio_nuevo, variacion_pct, origen, usuario_id, alerta)
      values
        (new.id, old.precio_costo_kg, new.precio_costo_kg, v_var,
         case when auth.uid() is null then 'factura' else 'manual' end,
         auth.uid(),
         coalesce(v_var, 0) > 7);
    end if;
    update public.stock set valorizacion = cantidad_actual * new.precio_costo_kg where insumo_id = new.id;
    perform public._recalcular_costo_recetas(new.id);
  end if;
  return new;
end;
$$;

-- Alta de un insumo nuevo desde la app (admin y encargado).
create or replace function public.crear_insumo(
  p_nombre text, p_marca text, p_subcategoria text, p_precio numeric,
  p_unidad text default 'kg', p_con_stock boolean default false
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_sub subcategoria_insumo;
  v_grupo grupo_insumo;
  v_id uuid;
  v_nombre text := trim(coalesce(p_nombre, ''));
  v_marca text := nullif(trim(coalesce(p_marca, '')), '');
begin
  if public.rol_actual() not in ('admin', 'encargado') then
    raise exception 'Sin permiso';
  end if;
  if v_nombre = '' then raise exception 'Falta la descripcion del insumo'; end if;
  if p_precio is null or p_precio < 0 then raise exception 'Precio invalido'; end if;
  if p_unidad not in ('kg', 'unidad') then raise exception 'Unidad invalida'; end if;
  v_sub := p_subcategoria::subcategoria_insumo;
  v_grupo := case when v_sub in ('vermut', 'cerveza y sin alcohol') then 'bebidas' else 'cocina' end;

  if public._insumo_id(v_sub::text, v_nombre, v_marca) is not null then
    raise exception 'Ya existe un insumo con esa descripcion y marca en esa categoria';
  end if;

  insert into public.insumos (nombre, marca, grupo, subcategoria, precio_costo_kg, unidad_medida, origen_alta)
    values (v_nombre, v_marca, v_grupo, v_sub, p_precio, p_unidad, 'manual')
    returning id into v_id;

  if p_con_stock then
    insert into public.stock (insumo_id, cantidad_actual, stock_minimo, valorizacion)
      values (v_id, 0, 0, 0)
      on conflict (insumo_id) do nothing;
  end if;
  return jsonb_build_object('id', v_id);
end;
$$;
grant execute on function public.crear_insumo(text, text, text, numeric, text, boolean) to authenticated;

-- ============================================================
-- Carga de factura: ahora busca contra "marca + descripcion" del catalogo y
-- los productos de COCINA tambien se buscan en la categoria Kutsi.
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
