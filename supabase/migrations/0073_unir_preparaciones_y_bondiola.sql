-- Gata Maula: un solo producto por ingrediente, el mismo en la receta y en el stock, para que al cambiar un precio se actualicen las recetas.
--   1) BONDIOLA (generica, 0 kg en stock) se une con IL NONNO ALPINO BONDIOLA: las recetas que usaban la generica (sandwich de bondiola, picada
--      para llevar, cono) pasan a la de Il Nonno ($19.754/kg), que es la que se cuenta en el stock.
--   2) Las preparaciones que se cuentan en el stock (crema de palta, cherry confitados, aderezo de verduras, relish, mayo chimi, cebolla caramelizada,
--      tapenade, uvas con azucar, escabeche de porotos, aceitunas condimentadas, pate de hongos, tomate rallado, pepinillos) se unen con su
--      receta de produccion: queda UN producto (el del stock). Su precio por kg sale solo de su receta de produccion y se recalcula cuando cambia
--      un ingrediente. Se conservan el stock y los movimientos. Pasan a figurar como "preparaciones" (precio calculado, sin alertas de aumento).
--      Solo se une si la preparacion se cuenta en kg; si se cuenta en unidades, NO se une y queda avisado.
--   3) Se recalculan todos los costos y se muestra una auditoria de los ingredientes de las recetas nuevas: sin precio, sin stock o con posibles repetidos.
-- ANTES de correrla: bajar una copia de seguridad (Ajustes > Copia de seguridad), porque unir borra el producto sobrante.
-- Correr UNA vez en el SQL Editor y mandar el resultado. Es seguro correrla mas de una vez.

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

-- une dos productos: todo lo del que se quita pasa al que se conserva (incluye lo que la union de la app no cubre)
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

drop table if exists _res;
create temp table _res (orden serial, seccion text, producto text, detalle text, precio numeric);

-- ============================================================ 1) bondiola
do $$
declare v_con uuid; v_quit uuid;
begin
  v_con := pg_temp._ins(array['IL NONNO ALPINO BONDIOLA']);
  select i.id into v_quit from public.insumos i join public.stock st on st.insumo_id = i.id
   where public.normalizar_texto(trim(coalesce(i.marca || ' ', '') || i.nombre)) = 'BONDIOLA' limit 1;
  if v_con is null then
    insert into _res (seccion, producto, detalle) values ('BONDIOLA', 'IL NONNO ALPINO BONDIOLA', 'NO ENCONTRADO: no se unio nada');
  elsif v_quit is null then
    insert into _res (seccion, producto, detalle) values ('BONDIOLA', 'BONDIOLA', 'ya no esta la bondiola generica en el stock: nada que unir');
  elsif v_con = v_quit then
    insert into _res (seccion, producto, detalle) values ('BONDIOLA', 'BONDIOLA', 'es el mismo producto: nada que unir');
  else
    perform pg_temp._unir(v_con, v_quit);
    insert into _res (seccion, producto, detalle) values ('BONDIOLA', 'IL NONNO ALPINO BONDIOLA', 'UNIDA: la bondiola generica paso a Il Nonno Alpino');
  end if;
end
$$;

-- ============================================================ 2) preparaciones que se cuentan en el stock
do $$
declare
  r record; p text; v_rec uuid; v_prep uuid; v_stock uuid; v_uni_ins text; v_uni_st text; v_nombre text;
begin
  for r in select * from (values
      ('CREMA DE PALTA',                'CREMA DE PALTA%',                array['CREMA PALTA']),
      ('TOMATES CHERRY (confitados)',   'TOMATES CHERRY%',                array['CHERRY CONFITADOS']),
      ('ADEREZO DE VERDURAS ASADAS',    'ADEREZO%VERDURAS%',              array['ADEREZO VERDURAS']),
      ('RELISH DE PEPINILLO',           'RELISH%',                        array['RELISH']),
      ('LACTONESA DE CHIMICHURRI',      'LACTONESA%',                     array['MAYO CHIMI']),
      ('CEBOLLA CARAMELIZADA',          'CEBOLLA CARAMELIZADA%',          array['CEBOLLA CARAMELIZDA','%CEBOLLA CARAMELIZ%']),
      ('TAPENADE DE ACEITUNAS NEGRAS',  'TAPENADE%',                      array['TAPENADE']),
      ('UVAS CITRICAS (con azucar)',    'UVAS%',                          array['UVAS CON AZUCAR']),
      ('POROTOS AL ESCABECHE',          'POROTOS%ESCABECHE%',             array['ESCABECHE DE POROTOS']),
      ('ACEITUNAS CONDIMENTADAS',       'ACEITUNAS CONDIMENTADAS%',       array['ACEITUNAS CONDIMENTADAS']),
      ('PATE DE HONGOS',                '%PATE DE HONGOS%',               array['%PATE DE HONGOS%']),
      ('TOMATE RALLADO',                'TOMATE RALLADO%',                array['%TOMATE RALLADO%']),
      ('PEPINILLOS (receta)',           '%PEPINILLOS%',                   array['PEPINILLOS'])
    ) as t(titulo, receta_pat, stock_pats)
  loop
    v_rec := null; v_prep := null; v_stock := null;
    select id, insumo_id into v_rec, v_prep from public.recetas
     where tipo = 'preparacion' and public.normalizar_texto(nombre_producto) like r.receta_pat
     order by created_at limit 1;
    if v_rec is null then
      insert into _res (seccion, producto, detalle) values ('PREPARACION', r.titulo, 'NO SE ENCONTRO LA RECETA DE PRODUCCION: no se unio');
      continue;
    end if;
    foreach p in array r.stock_pats loop
      select i.id into v_stock from public.insumos i join public.stock st on st.insumo_id = i.id
       where public.normalizar_texto(trim(coalesce(i.marca || ' ', '') || i.nombre)) like p and i.id is distinct from v_prep
       order by length(i.nombre), i.id limit 1;
      exit when v_stock is not null;
    end loop;
    if v_stock is null then
      insert into _res (seccion, producto, detalle) values ('PREPARACION', r.titulo, 'no esta en el stock (o ya es el mismo producto): nada que unir');
      continue;
    end if;
    select i.unidad_medida, coalesce(st.unidad, 'kg'), trim(coalesce(i.marca || ' ', '') || i.nombre) into v_uni_ins, v_uni_st, v_nombre
      from public.insumos i join public.stock st on st.insumo_id = i.id where i.id = v_stock;
    if v_uni_ins <> 'kg' or v_uni_st <> 'kg' then
      insert into _res (seccion, producto, detalle) values ('PREPARACION', v_nombre, 'SE CUENTA EN UNIDADES (' || v_uni_st || '): NO SE UNIO');
      continue;
    end if;
    if v_prep is null then
      update public.recetas set insumo_id = v_stock where id = v_rec;
    elsif v_prep <> v_stock then
      perform pg_temp._unir(v_stock, v_prep);
    end if;
    update public.insumos set es_preparacion = true, unidad_medida = 'kg' where id = v_stock;
    insert into _res (seccion, producto, detalle) values ('PREPARACION', v_nombre, 'UNIDA con su receta de produccion (' || r.titulo || ')');
  end loop;
end
$$;

-- ============================================================ 3) recalcular costos de todas las recetas
select public._recalcular_costo_recetas(null) as recetas_recalculadas;

-- ============================================================ resultado: lo que se unio + auditoria de los ingredientes de las recetas nuevas
select x.seccion, x.producto, x.detalle, round(x.precio) as precio
  from (
    select orden, seccion, producto, detalle, precio from _res
    union all
    select 1000 + row_number() over (order by a.producto), a.seccion, a.producto, a.detalle, a.precio
      from (
        select 'AUDITORIA'::text as seccion,
               trim(coalesce(i.marca || ' ', '') || i.nombre) as producto,
               concat_ws(' · ',
                 case when coalesce(i.precio_costo_kg, 0) = 0 then 'SIN PRECIO' end,
                 case when s.insumo_id is null and not i.es_preparacion then 'NO ESTA EN EL STOCK' end,
                 (select 'posibles repetidos: ' || string_agg(q.t, ' | ')
                    from (select trim(coalesce(o.marca || ' ', '') || o.nombre) || ' [$' || round(coalesce(o.precio_costo_kg, 0)) || case when so.insumo_id is not null then ', en stock' else '' end || ']' as t
                            from public.insumos o left join public.stock so on so.insumo_id = o.id
                           where o.id <> i.id
                             and (public.similitud_palabras(public.normalizar_texto(trim(coalesce(i.marca || ' ', '') || i.nombre)), public.normalizar_texto(trim(coalesce(o.marca || ' ', '') || o.nombre))) >= 0.99
                               or public.similitud_palabras(public.normalizar_texto(trim(coalesce(o.marca || ' ', '') || o.nombre)), public.normalizar_texto(trim(coalesce(i.marca || ' ', '') || i.nombre))) >= 0.99)
                           limit 4) q)
               ) as detalle,
               i.precio_costo_kg as precio
          from public.insumos i left join public.stock s on s.insumo_id = i.id
         where i.id in (select ri.insumo_id from public.receta_insumos ri join public.recetas r on r.id = ri.receta_id
                         where public.normalizar_texto(r.nombre_producto) like any (array[
                           'PICADA PARA LLEVAR%','CONO SOLO%','PICADA VERMUTERA','ANTIPASTI','LA EXQUISITA','PLATO AHUMADO','LA CABRITA',
                           'CONO DE FIAMBRES%','RACION %','PASTRON, RELISH%','PORTOBELLOS%','LOMO A LAS FINAS%','COCIDO, TYBO%','CRUDO, PARMESANO%',
                           'SANDWICH ASADITO%','SANDWICH MORTADELLA%','SANDWICH ESPECIAL EMBUCHADO','SANDWICH SALAME%','SANDWICH BONDIOLA, BRIE%','SANDWICH VEGGIE%']))
      ) a
     where a.detalle <> ''
  ) x
 order by x.orden
 limit 100;
