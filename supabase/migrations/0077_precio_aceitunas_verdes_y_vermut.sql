-- Gata Maula: dos errores de precio que inflaban la receta de aceitunas condimentadas (y la picada para llevar y la racion que la usan).
--   * ACEITUNAS VERDES WARA PALLAY 3KG figuraba a $18.900 "el kilo": es el precio del balde de 3 kg. Se cuenta en kilos, asi que pasa a $6.300/kg
--     (solo si todavia esta el precio del balde, es decir mas de $10.000). Al cargar la proxima factura de este producto, revisar que el precio quede por kilo.
--   * La receta de aceitunas usaba "BARRIL VERMUT GATA MAULA" (100 g a $30 = $3). Pasa a usar el mismo vermut Gata Maula ($4.800/L) que ya usan
--     la reduccion de vermut y la cebolla caramelizada (100 g = $480, como en tu Excel).
--   * Se recalculan todos los costos. Referencia del Excel: aceitunas condimentadas $6.220/kg.
-- No genera historial de precios ni alertas. Correr UNA vez en el SQL Editor y mandar el resultado. Es seguro correrlo mas de una vez.

do $$
declare v_old uuid; v_new uuid;
begin
  perform set_config('app.sin_historial', 'on', true);

  update public.insumos set precio_costo_kg = round(precio_costo_kg / 3, 2), fecha_ultima_actualizacion = now()
   where public.normalizar_texto(trim(coalesce(marca || ' ', '') || nombre)) like 'ACEITUNAS VERDES WARA PALLAY 3KG%'
     and precio_costo_kg > 10000;

  select id into v_old from public.insumos
   where public.normalizar_texto(trim(coalesce(marca || ' ', '') || nombre)) = 'BARRIL VERMUT GATA MAULA' limit 1;
  select ri.insumo_id into v_new
    from public.recetas r join public.receta_insumos ri on ri.receta_id = r.id join public.insumos i on i.id = ri.insumo_id
   where r.tipo = 'preparacion' and public.normalizar_texto(r.nombre_producto) = 'REDUCCION DE VERMUT'
     and public.normalizar_texto(trim(coalesce(i.marca || ' ', '') || i.nombre)) like '%VERMUT%'
   order by i.precio_costo_kg desc limit 1;
  if v_old is not null and v_new is not null and v_old <> v_new then
    update public.receta_insumos set insumo_id = v_new
     where insumo_id = v_old
       and receta_id in (select id from public.recetas where tipo = 'preparacion' and public.normalizar_texto(nombre_producto) = 'ACEITUNAS CONDIMENTADAS')
       and not exists (select 1 from public.receta_insumos x where x.receta_id = receta_insumos.receta_id and x.insumo_id = v_new);
  end if;
end
$$;

select public._recalcular_costo_recetas(null) as recetas_recalculadas;

-- resultado
select x.tema, x.detalle, x.precio
  from (
    select 1 as orden, 'PRECIO DE LA MATERIA PRIMA'::text as tema, trim(coalesce(i.marca || ' ', '') || i.nombre) as detalle, round(i.precio_costo_kg) as precio
      from public.insumos i where public.normalizar_texto(trim(coalesce(i.marca || ' ', '') || i.nombre)) like 'ACEITUNAS VERDES WARA PALLAY 3KG%'
    union all
    select 2, 'PREPARACION (por kg)', r.nombre_producto, round(i.precio_costo_kg)
      from public.recetas r join public.insumos i on i.id = r.insumo_id
     where r.tipo = 'preparacion' and public.normalizar_texto(r.nombre_producto) = 'ACEITUNAS CONDIMENTADAS'
    union all
    select 3, 'REFERENCIA DE TU EXCEL (por kg)', 'aceitunas condimentadas', 6220
    union all
    select 4, 'RACION DE CARTA (120 g)', r.nombre_producto, round(r.costo_total_calculado)
      from public.recetas r where r.tipo = 'plato' and public.normalizar_texto(r.nombre_producto) like 'ACEITUNAS VERDES CONDIMENTADAS%'
    union all
    select 5, 'PICADA PARA LLEVAR (por persona)', r.nombre_producto, round(r.costo_total_calculado)
      from public.recetas r where r.tipo = 'plato' and public.normalizar_texto(r.nombre_producto) like 'PICADA PARA LLEVAR%'
  ) x
 order by x.orden;
