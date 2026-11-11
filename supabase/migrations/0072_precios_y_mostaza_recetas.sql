-- Gata Maula: corrige los precios en cero de productos del stock que usan las recetas nuevas, y usa la mostaza antigua en los sandwiches.
--   * Las preparaciones que se cuentan en el stock (crema de palta, cherry confitados, aderezo de verduras, relish, aceitunas condimentadas,
--     escabeche de porotos, mayo chimi, cebolla caramelizada, tapenade, uvas con azucar) toman el precio por kg de su receta de produccion
--     (el que ya calcula la app); si no la encuentra, usa el costo por kg de tu Excel PPTO.
--   * Manteca saborizada = precio de la manteca; bondiola = $15.721/kg (Don Lino, el de la picada para llevar); crottin Santa Olalla = $34.762,11/kg (Costeo Carta).
--   * Solo se toca el precio de los que hoy estan en cero. No se genera historial ni alertas de aumento.
--   * El sandwich de pastron y el de bondiola pasan de MOSTAZA a MOSTAZA ANTIGUA (la casera).
-- Correr UNA vez en el SQL Editor y mandar el resultado. Es seguro correrlo mas de una vez.

create or replace function pg_temp._ins(p_pats text[]) returns uuid
language plpgsql as $$
declare p text; v uuid;
begin
  foreach p in array p_pats loop
    select i.id into v
      from public.insumos i left join public.stock st on st.insumo_id = i.id
     where public.normalizar_texto(trim(coalesce(i.marca || ' ', '') || i.nombre)) like p
     order by (st.insumo_id is not null) desc, length(i.nombre), i.id
     limit 1;
    if v is not null then return v; end if;
  end loop;
  return null;
end
$$;

do $$
declare
  r record; v_id uuid; v_precio numeric; p text;
begin
  perform set_config('app.sin_historial', 'on', true);
  for r in select * from (values
      ('CREMA PALTA',         array['CREMA PALTA'],            array['%CREMA DE PALTA%'],                         12863.24),
      ('CHERRY CONFITADOS',   array['CHERRY CONFITADOS'],      array['%TOMATES CHERRY%','%CHERRYS ASADOS%'],      10008.47),
      ('UVAS CON AZUCAR',     array['UVAS CON AZUCAR'],        array['%UVAS CITRICAS%','%UVAS MACERADAS%'],        2840.27),
      ('ADEREZO VERDURAS',    array['ADEREZO VERDURAS'],       array['%ADEREZO VERDURAS ASADAS%'],                 6391.77),
      ('RELISH',              array['RELISH'],                 array['%RELISH DE PEPINILLO%','%RELISH DE PEPINO%'],2451.74),
      ('ACEITUNAS CONDIMENTADAS', array['ACEITUNAS CONDIMENTADAS'], array['%ACEITUNAS CONDIMENTADAS%'],           6220.32),
      ('ESCABECHE DE POROTOS',array['ESCABECHE DE POROTOS'],  array['%POROTOS AL ESCABECHE%','%POROTOS EN ESCABECHE%'], 3611.01),
      ('MAYO CHIMI',          array['MAYO CHIMI'],             array['%LACTONESA%CHIMICHURRI%'],                   2796.78),
      ('CEBOLLA CARAMELIZADA',array['CEBOLLA CARAMELIZDA','%CEBOLLA CARAMELIZ%'], array['%CEBOLLA CARAMELIZADA%'], 2133.06),
      ('TAPENADE',            array['TAPENADE'],               array['%TAPENADE DE ACEITUNAS%'],                  10406.59),
      ('MANTECA SABORIZADA',  array['MANTECA SABORIZADA'],     array['%MANTECA TONADITA%'],                       11100),
      ('BONDIOLA',            array['BONDIOLA'],               array[]::text[],                                   15721),
      ('CROTTIN SANTA OLALLA',array['%OLALLA%CROTTIN%','%CROTTIN%'], array[]::text[],                             34762.11)
    ) as t(nombre, stock_pats, src_pats, excel)
  loop
    v_id := pg_temp._ins(r.stock_pats);
    if v_id is null then continue; end if;
    v_precio := null;
    foreach p in array r.src_pats loop
      select i.precio_costo_kg into v_precio
        from public.insumos i
       where public.normalizar_texto(trim(coalesce(i.marca || ' ', '') || i.nombre)) like p
         and i.id <> v_id and coalesce(i.precio_costo_kg, 0) > 0
       order by (i.es_preparacion) desc, length(i.nombre), i.id limit 1;
      exit when v_precio is not null;
    end loop;
    v_precio := coalesce(v_precio, r.excel);
    update public.insumos set precio_costo_kg = round(v_precio, 2), fecha_ultima_actualizacion = now()
     where id = v_id and coalesce(precio_costo_kg, 0) = 0;
  end loop;
end
$$;

-- mostaza antigua (casera) en el sandwich de pastron y en el de bondiola
do $$
declare v_old uuid := pg_temp._ins(array['MOSTAZA']); v_new uuid := pg_temp._ins(array['%MOSTAZA ANTIGUA%']);
begin
  if v_old is not null and v_new is not null and v_old <> v_new then
    update public.receta_insumos ri set insumo_id = v_new
     where ri.insumo_id = v_old
       and ri.receta_id in (select id from public.recetas
                             where public.normalizar_texto(nombre_producto) like any (array['PASTRON, RELISH%', 'SANDWICH BONDIOLA, BRIE%']))
       and not exists (select 1 from public.receta_insumos x where x.receta_id = ri.receta_id and x.insumo_id = v_new);
  end if;
end
$$;

select public._recalcular_costo_recetas(null) as recetas_recalculadas;

-- resultado: costo de las recetas nuevas y cuantos ingredientes siguen sin precio (tiene que ser 0)
select r.nombre_producto as receta, round(r.costo_total_calculado) as costo,
       (select count(*) from public.receta_insumos ri join public.insumos i on i.id = ri.insumo_id
         where ri.receta_id = r.id and coalesce(i.precio_costo_kg, 0) = 0) as ingredientes_sin_precio,
       (select string_agg(trim(coalesce(i.marca || ' ', '') || i.nombre), ', ')
          from public.receta_insumos ri join public.insumos i on i.id = ri.insumo_id
         where ri.receta_id = r.id and coalesce(i.precio_costo_kg, 0) = 0) as cuales
  from public.recetas r
 where public.normalizar_texto(r.nombre_producto) like any (array[
     'PICADA PARA LLEVAR%','CONO SOLO%','PICADA VERMUTERA','ANTIPASTI','LA EXQUISITA','PLATO AHUMADO','LA CABRITA',
     'CONO DE FIAMBRES%','RACION %','PASTRON, RELISH%','PORTOBELLOS%','LOMO A LAS FINAS%','COCIDO, TYBO%','CRUDO, PARMESANO%',
     'SANDWICH ASADITO%','SANDWICH MORTADELLA%','SANDWICH ESPECIAL EMBUCHADO','SANDWICH SALAME%','SANDWICH BONDIOLA, BRIE%','SANDWICH VEGGIE%'])
 order by 1;
