-- Gata Maula: limpieza de duplicados que dejaron las recetas por porcion.
--   * Racion de lengua: Postberry "LENGUA RACION" pasa a usar la receta que ya existia ("Lengua a la Vinagreta": 120 g de la preparacion
--     lengua a la vinagreta, con su costo real) y se borra mi duplicado "RACION DE LENGUA (120 g)", que usaba un producto equivocado ($17.250/kg).
--   * Racion de aceitunas condimentadas: "ACEITUNAS CONDIMENTADAS RACION" pasa a la receta existente "Aceitunas Verdes Condimentadas"
--     (120 g de la misma preparacion) y se borra mi duplicado "RACION DE ACEITUNAS CONDIMENTADAS (120 g)".
--   * Crottin: las dos copias de SANTA OLALLA CROTTIN (una en el stock y otra solo en la lista de precios) se unen en la del stock.
-- Al final se recalculan los costos y el descuento de lo ya cargado, y se muestra el resultado.
-- Correr UNA vez en el SQL Editor. Es seguro correrlo mas de una vez.

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

drop table if exists _res75;
create temp table _res75 (orden serial, tema text, detalle text);

do $$
declare v_exist uuid; v_dup uuid; v_con uuid; v_quit uuid; n int;
begin
  -- lengua
  select id into v_exist from public.recetas where tipo = 'plato' and public.normalizar_texto(nombre_producto) = 'LENGUA A LA VINAGRETA' order by created_at limit 1;
  select id into v_dup from public.recetas where tipo = 'plato' and public.normalizar_texto(nombre_producto) like 'RACION DE LENGUA%' order by created_at limit 1;
  if v_exist is null then
    insert into _res75 (tema, detalle) values ('LENGUA', 'no encontre la racion "Lengua a la Vinagreta" que ya existia: no se toco nada');
  elsif v_dup is null then
    insert into _res75 (tema, detalle) values ('LENGUA', 'ya no estaba mi duplicado');
  else
    update public.pos_receta set receta_id = v_exist where receta_id = v_dup;
    delete from public.recetas where id = v_dup;
    insert into _res75 (tema, detalle) values ('LENGUA', 'LENGUA RACION usa la receta existente y se borro el duplicado');
  end if;

  -- aceitunas condimentadas (racion)
  select id into v_exist from public.recetas where tipo = 'plato' and public.normalizar_texto(nombre_producto) like 'ACEITUNAS VERDES CONDIMENTADAS%' order by created_at limit 1;
  select id into v_dup from public.recetas where tipo = 'plato' and public.normalizar_texto(nombre_producto) like 'RACION DE ACEITUNAS CONDIMENTADAS%' order by created_at limit 1;
  if v_exist is null then
    insert into _res75 (tema, detalle) values ('ACEITUNAS', 'no encontre la receta "Aceitunas Verdes Condimentadas": no se toco nada');
  elsif v_dup is null then
    insert into _res75 (tema, detalle) values ('ACEITUNAS', 'ya no estaba mi duplicado');
  else
    update public.pos_receta set receta_id = v_exist where receta_id = v_dup;
    delete from public.recetas where id = v_dup;
    insert into _res75 (tema, detalle) values ('ACEITUNAS', 'ACEITUNAS CONDIMENTADAS RACION usa la receta existente y se borro el duplicado');
  end if;

  -- crottin repetido
  select count(*) into n from public.insumos where public.normalizar_texto(trim(coalesce(marca || ' ', '') || nombre)) = 'SANTA OLALLA CROTTIN';
  if n = 2 then
    select i.id into v_con from public.insumos i join public.stock s on s.insumo_id = i.id
     where public.normalizar_texto(trim(coalesce(i.marca || ' ', '') || i.nombre)) = 'SANTA OLALLA CROTTIN' limit 1;
    select i.id into v_quit from public.insumos i left join public.stock s on s.insumo_id = i.id
     where public.normalizar_texto(trim(coalesce(i.marca || ' ', '') || i.nombre)) = 'SANTA OLALLA CROTTIN' and s.insumo_id is null limit 1;
    if v_con is not null and v_quit is not null then
      perform pg_temp._unir(v_con, v_quit);
      insert into _res75 (tema, detalle) values ('CROTTIN', 'UNIDAS las dos copias en la que esta en el stock');
    else
      insert into _res75 (tema, detalle) values ('CROTTIN', 'las dos copias estan las dos en el stock o ninguna: no se unio');
    end if;
  else
    insert into _res75 (tema, detalle) values ('CROTTIN', 'hay ' || n || ' copia(s): nada que unir');
  end if;
end
$$;

select public._recalcular_costo_recetas(null) as recetas_recalculadas;
do $$
declare a timestamp; b timestamp;
begin
  select min(fecha), max(fecha) into a, b from public.pos_lineas;
  if a is not null then perform public._pos_aplicar(a, b); end if;
end
$$;

-- resultado
select x.tema, x.detalle
  from (
    select orden, tema, detalle from _res75
    union all
    select 100 + row_number() over (order by r.nombre_producto), 'RECETA', r.nombre_producto || ' · costo $' || round(r.costo_total_calculado)
      from public.recetas r
     where public.normalizar_texto(r.nombre_producto) like any (array['LENGUA A LA VINAGRETA', 'ACEITUNAS VERDES CONDIMENTADAS%', 'RACION DE LENGUA%', 'RACION DE ACEITUNAS%'])
       and r.tipo = 'plato'
    union all
    select 200 + row_number() over (order by pr.producto), 'VINCULO', pr.producto || ' -> ' || r.nombre_producto
      from public.pos_receta pr join public.recetas r on r.id = pr.receta_id
     where pr.producto in ('LENGUA RACION', 'ACEITUNAS CONDIMENTADAS RACION', 'ACEITUNAS VERDES RACION')
  ) x
 order by x.orden;
