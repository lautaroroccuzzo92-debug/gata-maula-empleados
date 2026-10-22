-- Gata Maula: correcciones de stock e insumos pedidas por Manu y Facu (rubros bebidas, vermut, fiambres, quesos y cocina).
--   * herramientas nuevas: stock_alta (empezar a controlar el stock de un insumo) y stock_baja (sacarlo del control de stock)
--   * se corrigen repetidos, nombres mal escritos y rubros, con los ids de tu lista de insumos
-- Correr UNA vez en el SQL Editor (despues de 0033).

create or replace function public.stock_alta(p_insumo_id uuid, p_unidad text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if public.rol_actual() not in ('admin', 'encargado') then raise exception 'Sin permiso'; end if;
  if not exists (select 1 from public.insumos where id = p_insumo_id) then raise exception 'Insumo no encontrado'; end if;
  insert into public.stock (insumo_id, cantidad_actual, stock_minimo, valorizacion, unidad)
    values (p_insumo_id, 0, 0, 0, case when p_unidad in ('kg', 'unidad') then p_unidad else null end)
    on conflict (insumo_id) do nothing;
  return jsonb_build_object('ok', true);
end;
$$;
grant execute on function public.stock_alta(uuid, text) to authenticated;

create or replace function public.stock_baja(p_insumo_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if public.rol_actual() not in ('admin', 'encargado') then raise exception 'Sin permiso'; end if;
  delete from public.stock where insumo_id = p_insumo_id;
  return jsonb_build_object('ok', true);
end;
$$;
grant execute on function public.stock_baja(uuid) to authenticated;

-- Versiones internas (sin chequeo de rol) para correr desde el SQL Editor; no se exponen a la app
create or replace function public._stock_alta(p_insumo_id uuid, p_unidad text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.stock (insumo_id, cantidad_actual, stock_minimo, valorizacion, unidad)
    values (p_insumo_id, 0, 0, 0, case when p_unidad in ('kg', 'unidad') then p_unidad else null end)
    on conflict (insumo_id) do nothing;
end;
$$;
revoke all on function public._stock_alta(uuid, text) from public;

create or replace function public.insumo_unir_sistema(p_conservar uuid, p_quitar uuid)
returns void language plpgsql security definer set search_path = public as $$
declare sq record; sc record; v_precio numeric;
begin
  if p_conservar = p_quitar then return; end if;
  if not exists (select 1 from public.insumos where id = p_quitar) then return; end if;
  select precio_costo_kg into v_precio from public.insumos where id = p_conservar;
  select * into sq from public.stock where insumo_id = p_quitar;
  if found then
    select * into sc from public.stock where insumo_id = p_conservar;
    if found then
      update public.stock set cantidad_actual = sc.cantidad_actual + sq.cantidad_actual,
        stock_minimo = case when coalesce(sc.stock_minimo, 0) > 0 then sc.stock_minimo else sq.stock_minimo end,
        proveedor_pedido = coalesce(sc.proveedor_pedido, sq.proveedor_pedido), dias_pedido = coalesce(sc.dias_pedido, sq.dias_pedido),
        cantidad_pedido = coalesce(sc.cantidad_pedido, sq.cantidad_pedido), unidad = coalesce(sc.unidad, sq.unidad),
        valorizacion = (sc.cantidad_actual + sq.cantidad_actual) * coalesce(v_precio, 0), ultima_actualizacion = now()
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
end;
$$;
revoke all on function public.insumo_unir_sistema(uuid, uuid) from public;

do $$
declare v_prep uuid; v_min numeric; v_prov text; v_dias text; v_cant text;
begin
  -- ===== BEBIDAS =====
  -- Aperitivo sin alcohol Bianco Lorenzo, Fernet sin alcohol Lorenzo y Peroni: empiezan a controlarse en Stock
  perform public._stock_alta('67deb167-f57b-4da7-8417-61f64c5e07d5', 'unidad'); -- APERITIVO SIN ALCOHOL BIANCO LORENZO BOTELLA 750 CC
  perform public._stock_alta('404fa5d7-b399-4739-9ffa-9509a8539375', 'unidad'); -- FERNET SIN ALCOHOL LORENZO BOTELLA 750 CC
  -- Peroni: el minimo de la planilla (CERVEZA PERONI) habia quedado en 'FILLS 90 GR'; pasa a Peroni
  if exists (select 1 from public.stock where insumo_id = 'cafc3ce9-dff6-4a26-b7a4-9a3512678f85') and not exists (select 1 from public.stock where insumo_id = '9a04e90e-cc30-490b-9aa4-df21dd3859e1') then
    update public.stock set insumo_id = '9a04e90e-cc30-490b-9aa4-df21dd3859e1' where insumo_id = 'cafc3ce9-dff6-4a26-b7a4-9a3512678f85';
  else
    perform public._stock_alta('9a04e90e-cc30-490b-9aa4-df21dd3859e1', 'unidad');
  end if;
  -- Papas: de Kutsi a Cerveza y sin alcohol
  update public.insumos set subcategoria = 'cerveza y sin alcohol', grupo = 'bebidas' where id = 'da6cfa49-e412-4c28-b7a5-68e16429ba55'; -- PAPAS DANAL NAPOLES
  update public.insumos set subcategoria = 'cerveza y sin alcohol', grupo = 'bebidas' where id = '15b30970-56f7-4327-9313-690df0683593'; -- PAPAS DANAL 
  update public.insumos set subcategoria = 'cerveza y sin alcohol', grupo = 'bebidas' where id = 'b37e84e5-d26e-4002-ae9f-b4b05f6b1c14'; -- PAPAS PAY DANAL 

  -- ===== VERMUT =====
  update public.insumos set nombre = 'LUI VERMUT 746 ROJO' where id = 'e03dc596-3f5f-4cb8-88d2-d428ab97bee3';
  update public.insumos set nombre = 'LUI VERMUT 746 DORADO' where id = '968257ee-4268-4d72-80c0-8d9993caed89';
  -- el '746 DORADO' suelto se elimina; su stock pasa a LUI VERMUT 746 DORADO
  perform public.insumo_unir_sistema('968257ee-4268-4d72-80c0-8d9993caed89', '77e737e9-67dc-4805-83cf-67335e6774f6');
  -- Sin Apuro Isabella: su stock estaba cargado sobre 'SIN APURO VERMUT SYRAH' (por eso el Syrah se veia repetido); pasa a Isabella
  if exists (select 1 from public.stock where insumo_id = 'b2b2cb0a-9270-4820-ae4b-827c0c07a092') and not exists (select 1 from public.stock where insumo_id = '8f630b93-10e4-4ed4-a6f1-981621610020') then
    update public.stock set insumo_id = '8f630b93-10e4-4ed4-a6f1-981621610020' where insumo_id = 'b2b2cb0a-9270-4820-ae4b-827c0c07a092';
  else
    perform public._stock_alta('8f630b93-10e4-4ed4-a6f1-981621610020', 'unidad');
  end if;
  update public.insumos set nombre = 'VIARAVA VERMUT BARRIO' where id = 'd6c6d33b-2423-4e24-8541-fa1e0b7b0533';
  perform public._stock_alta('d6c6d33b-2423-4e24-8541-fa1e0b7b0533', 'unidad');

  -- ===== FIAMBRES =====
  -- Crudo Tacra: se elimina
  delete from public.stock where insumo_id = 'fa8e5e28-e759-473c-ab78-9f5120492fe5';
  delete from public.movimientos_stock where insumo_id = 'fa8e5e28-e759-473c-ab78-9f5120492fe5';
  delete from public.insumos where id = 'fa8e5e28-e759-473c-ab78-9f5120492fe5' and not exists (select 1 from public.receta_insumos where insumo_id = 'fa8e5e28-e759-473c-ab78-9f5120492fe5') and not exists (select 1 from public.desperdicio where insumo_id = 'fa8e5e28-e759-473c-ab78-9f5120492fe5');
  -- Brie Santa Olalla y Tybo: pasan de Fiambres a Quesos
  update public.insumos set subcategoria = 'quesos' where id in ('62930409-f5d0-4c50-9f8f-6cb30b35e8ec', '50ef1462-5599-45cb-af23-f7aba938ff34');
  -- Jamon cocido colonial: se suma al stock
  update public.insumos set nombre = 'JAMON COCIDO COLONIAL' where id = 'a142e4ec-c907-47db-b614-78e0cb467a68';
  perform public._stock_alta('a142e4ec-c907-47db-b614-78e0cb467a68', 'kg');

  -- ===== QUESOS =====
  update public.insumos set nombre = 'QUESO AZUL VANGUARD' where id = 'a8385438-c5ce-4c50-a363-b8012027a2c8';
  -- Azul Vanguard: el minimo y proveedor de la planilla habian quedado sobre 'QUESO AZUL BAVARIA'; pasan a Vanguard
  if exists (select 1 from public.stock where insumo_id = '3fc59adb-2bac-4611-b01f-ad3165cc25f9') and not exists (select 1 from public.stock where insumo_id = 'a8385438-c5ce-4c50-a363-b8012027a2c8') then
    update public.stock set insumo_id = 'a8385438-c5ce-4c50-a363-b8012027a2c8' where insumo_id = '3fc59adb-2bac-4611-b01f-ad3165cc25f9';
  else
    perform public._stock_alta('a8385438-c5ce-4c50-a363-b8012027a2c8', 'kg');
  end if;
  -- Azul Bavaria repetido: se unen (queda 'QUESO AZUL BAVARIA' con el stock real)
  perform public.insumo_unir_sistema('3fc59adb-2bac-4611-b01f-ad3165cc25f9', 'a975f4f6-d0a5-4f7b-b57f-4bcb6abe7381');
  -- Reggianito x2: se unen
  perform public.insumo_unir_sistema('75597b35-f868-45ef-b107-4ada066c0a9b', 'befccfdc-8ad8-4ebf-bedb-c6a5a8b9a5f7');

  -- ===== COCINA =====
  -- Bella Vista y Azucar: se sacan del control de stock (el insumo sigue en Insumos y precios / recetas)
  delete from public.stock where insumo_id in ('9ea062e9-90c3-466d-b7c9-98fe8f6c4a62', '9e9ba973-737f-4ab9-afb0-05d11b4860d1');
  -- Chimichurri repetido
  perform public.insumo_unir_sistema('314abca9-02fb-4e1e-ab5e-796c28f21650', '425c112c-81bb-4ef8-8bdc-7b353b9c23df');
  -- Mostazas en grano: amarilla (une la suelta) y negra (se suma al stock)
  update public.insumos set nombre = 'MOSTAZA EN GRANO AMARILLA' where id = 'fa2878fa-c648-4a08-a71b-bc28ae1ae309';
  perform public.insumo_unir_sistema('fa2878fa-c648-4a08-a71b-bc28ae1ae309', 'a9cf6eb8-13d5-4f36-a0f3-b26af6e1cfa7');
  update public.insumos set nombre = 'MOSTAZA EN GRANO NEGRA' where id = 'e7345dcc-a82e-4207-8e00-254e5c8fa020';
  perform public._stock_alta('e7345dcc-a82e-4207-8e00-254e5c8fa020', 'kg');
  -- Pera repetida
  perform public.insumo_unir_sistema('2f36c744-b927-4947-988e-c43eee62adab', '53a1982f-889b-4ea3-b4c6-42e1e5d596da');
  -- Porotos triplicados: queda POROTOS PALLARES
  perform public.insumo_unir_sistema('90fad044-4038-4d6e-bfea-6503673593af', 'e2b394d1-6e89-45e1-b311-8e90450e36e8');
  perform public.insumo_unir_sistema('90fad044-4038-4d6e-bfea-6503673593af', '3ef9aa72-c268-4626-bea6-ceaa0b68e1c3');
  -- Pimiento y zucchini mal escritos: se unen con el nombre correcto
  perform public.insumo_unir_sistema('c362e13e-7152-480a-8dd8-284f9792e3f4', '26d720f3-6665-49e5-9e49-3c0a33ce3c3f');
  update public.insumos set nombre = 'PIMIENTO AMARILLO' where id = '19756793-24e3-4bec-9023-150de452e50e';
  perform public.insumo_unir_sistema('19756793-24e3-4bec-9023-150de452e50e', '5fb013d1-8ed6-48e5-8923-ab9424c19e4d');
  perform public.insumo_unir_sistema('b98ae54b-c526-473a-915c-5d53bdd9a31b', '4acba671-c802-41ea-9e59-f4e002e9405a');
  -- Portobellos en escabeche: se saca; se suma Escabeche de hongos (la preparacion de Recetas) con el mismo minimo
  select id into v_prep from public.insumos where es_preparacion and lower(nombre) = 'hongos en escabeche' limit 1;
  select stock_minimo, proveedor_pedido, dias_pedido, cantidad_pedido into v_min, v_prov, v_dias, v_cant from public.stock where insumo_id = '918f0867-73ce-463d-9151-11c4cc42c369';
  delete from public.stock where insumo_id = '918f0867-73ce-463d-9151-11c4cc42c369';
  if v_prep is not null then
    insert into public.stock (insumo_id, cantidad_actual, stock_minimo, valorizacion, unidad, proveedor_pedido, dias_pedido, cantidad_pedido)
      values (v_prep, 0, coalesce(v_min, 0), 0, 'kg', v_prov, v_dias, v_cant) on conflict (insumo_id) do nothing;
  else
    raise notice 'No encontre la preparacion HONGOS EN ESCABECHE: sumar Escabeche de hongos a mano';
  end if;
end
$$;

