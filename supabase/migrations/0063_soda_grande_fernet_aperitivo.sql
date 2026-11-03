-- Gata Maula: soda grande, aperitivo y fernet sin alcohol de Lorenzos (incluye lo de la 0062, asi que alcanza con correr esta despues de la 0061).
--   * Producto nuevo en el stock: SODA 1250 CC (la soda grande).
--   * Medida de aperitivo sin alcohol Lorenzos: 40 ml de aperitivo + 115 ml de la soda grande.
--   * Medida de fernet sin alcohol Lorenzos: 50 ml de fernet + 1 Pepsi comun entera.
--   * Cada "BOTELLA ..." de Postberry descuenta ademas 1 soda grande (la soda de 1250 ml que va con la botella).
-- Es seguro correrlo mas de una vez.

-- ============================================================ productos nuevos
insert into public.insumos (nombre, marca, grupo, subcategoria, precio_costo_kg, unidad_medida, origen_alta, ml_por_unidad)
select 'SODA 1250 CC', null, 'bebidas', 'cerveza y sin alcohol', 0, 'unidad', 'manual', 1250
 where not exists (select 1 from public.insumos where nombre = 'SODA 1250 CC');
insert into public.stock (insumo_id, cantidad_actual, stock_minimo, valorizacion, unidad)
select id, 0, 0, 0, 'unidad' from public.insumos where nombre = 'SODA 1250 CC'
on conflict (insumo_id) do nothing;
insert into public.pos_config (clave, valor) select 'insumo_soda_grande', id::text from public.insumos where nombre = 'SODA 1250 CC'
  on conflict (clave) do update set valor = excluded.valor;

-- Pepsi comun: se usa la que ya este en el stock; si no hay, se crea
do $$
declare v uuid;
begin
  select i.id into v from public.insumos i join public.stock s on s.insumo_id = i.id
   where i.subcategoria::text = 'cerveza y sin alcohol' and not i.es_preparacion
     and public.normalizar_texto(i.nombre) like '%PEPSI%' and public.normalizar_texto(i.nombre) not like '%BLACK%'
     and public.normalizar_texto(i.nombre) not like '%LIGHT%' and public.normalizar_texto(i.nombre) not like '%ZERO%'
   order by length(i.nombre), i.nombre limit 1;
  if v is null then
    insert into public.insumos (nombre, marca, grupo, subcategoria, precio_costo_kg, unidad_medida, origen_alta)
      values ('PEPSI 354CC', null, 'bebidas', 'cerveza y sin alcohol', 0, 'unidad', 'manual') returning id into v;
    insert into public.stock (insumo_id, cantidad_actual, stock_minimo, valorizacion, unidad) values (v, 0, 0, 0, 'unidad') on conflict (insumo_id) do nothing;
  end if;
  insert into public.pos_config (clave, valor) values ('insumo_pepsi', v::text) on conflict (clave) do update set valor = excluded.valor;
end
$$;

-- ============================================================ medidas
update public.insumos set ml_medida = 40, ml_por_unidad = coalesce(ml_por_unidad, 750)
 where public.normalizar_texto(trim(coalesce(marca || ' ', '') || nombre)) like '%APERITIVO%'
   and public.normalizar_texto(trim(coalesce(marca || ' ', '') || nombre)) like '%LORENZO%';
update public.insumos set ml_medida = 50, ml_por_unidad = coalesce(ml_por_unidad, 750)
 where public.normalizar_texto(trim(coalesce(marca || ' ', '') || nombre)) like '%FERNET%'
   and public.normalizar_texto(trim(coalesce(marca || ' ', '') || nombre)) like '%LORENZO%';

-- ============================================================ vinculos extra (aperitivo, fernet, botellas)
create or replace function public._pos_soda_aperitivo() returns int
language plpgsql security definer set search_path = public as $$
declare
  v_grande uuid := (select valor::uuid from public.pos_config where clave = 'insumo_soda_grande');
  v_chica uuid := (select valor::uuid from public.pos_config where clave = 'insumo_soda');
  v_pepsi uuid := (select valor::uuid from public.pos_config where clave = 'insumo_pepsi');
  n int := 0; r record;
begin
  if v_grande is not null then
    -- aperitivo sin alcohol: 115 ml de soda grande (y nada de soda por ticket)
    for r in select distinct producto from public.pos_vinculo where public.normalizar_texto(producto) like 'MEDIDA APERITIVO%' loop
      if v_chica is not null then delete from public.pos_vinculo where producto = r.producto and insumo_id = v_chica; end if;
      update public.pos_vinculo set lleva_soda = false where producto = r.producto;
      insert into public.pos_vinculo (producto, insumo_id, modo, valor, lleva_soda) values (r.producto, v_grande, 'ml', 115, false)
        on conflict (producto, insumo_id) do update set modo = 'ml', valor = 115, lleva_soda = false;
      n := n + 1;
    end loop;
    -- botellas: 1 soda grande
    for r in select distinct producto from public.pos_vinculo where public.normalizar_texto(producto) like 'BOTELLA %' and insumo_id <> v_grande loop
      insert into public.pos_vinculo (producto, insumo_id, modo, valor, lleva_soda) values (r.producto, v_grande, 'unidad', 1, false)
        on conflict (producto, insumo_id) do update set modo = 'unidad', valor = 1, lleva_soda = false;
      n := n + 1;
    end loop;
  end if;
  -- fernet sin alcohol: 1 Pepsi entera
  if v_pepsi is not null then
    for r in select distinct producto from public.pos_vinculo where public.normalizar_texto(producto) like 'MEDIDA FERNET%' and insumo_id <> v_pepsi loop
      update public.pos_vinculo set lleva_soda = false where producto = r.producto;
      insert into public.pos_vinculo (producto, insumo_id, modo, valor, lleva_soda) values (r.producto, v_pepsi, 'unidad', 1, false)
        on conflict (producto, insumo_id) do update set modo = 'unidad', valor = 1, lleva_soda = false;
      n := n + 1;
    end loop;
    -- la Pepsi que se vende suelta descuenta 1 Pepsi (si todavia no estaba vinculada)
    for r in select p.producto from (select distinct producto from public.pos_lineas) p
              where public.normalizar_texto(p.producto) = 'PEPSI 354CC'
                and not exists (select 1 from public.pos_vinculo v where v.producto = p.producto)
                and not exists (select 1 from public.pos_producto x where x.producto = p.producto and x.omitir is not null) loop
      insert into public.pos_vinculo (producto, insumo_id, modo, valor, lleva_soda) values (r.producto, v_pepsi, 'unidad', 1, false) on conflict (producto, insumo_id) do nothing;
      n := n + 1;
    end loop;
  end if;
  return n;
end;
$$;
revoke all on function public._pos_soda_aperitivo() from public;

create or replace function public.pos_autovincular() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v jsonb;
begin
  if public.rol_actual() not in ('admin', 'encargado') then raise exception 'Sin permiso'; end if;
  v := public._pos_autovincular();
  perform public._pos_soda_aperitivo();
  perform public.pos_recalcular_todo();
  return v;
end;
$$;
grant execute on function public.pos_autovincular() to authenticated;

select public._pos_autovincular() as autovinculacion;
select public._pos_soda_aperitivo() as vinculos_extra;
do $$
declare a timestamp; b timestamp;
begin
  select min(fecha), max(fecha) into a, b from public.pos_lineas;
  if a is not null then perform public._pos_aplicar(a, b); end if;
end
$$;

-- ============================================================ resultado: como quedaron aperitivo, fernet, botellas y pepsi
select p.producto, coalesce((select string_agg(i.nombre || ' [' || v.modo || ' ' || v.valor || ']', ' + ') from public.pos_vinculo v join public.insumos i on i.id = v.insumo_id where v.producto = p.producto), 'SIN VINCULAR') as descuenta
  from (select distinct producto from public.pos_lineas) p
 where public.normalizar_texto(p.producto) ~ '(APERITIVO|FERNET|^BOTELLA|PEPSI)' order by 1;
