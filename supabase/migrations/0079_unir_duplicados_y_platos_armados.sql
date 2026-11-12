-- Gata Maula: un solo producto por ingrediente (el que se cuenta en el stock) y platos armados contados en unidades con el costo de su receta.
--   1) Se unen estos pares. Queda el producto que se cuenta (o el que ya tiene precio y stock), se conserva el stock y lo contado, y si el que queda
--      tiene precio $0 toma el del otro:
--        FRUTILLAS -> FRUTILLA | NUECES -> NUEZ | ALBARQUINAS ACEITUNAS EN RODAJAS y ACEITUNAS NEGRAS -> ACEITUNAS NEGRAS EN RODAJAS |
--        UVAS VERDES -> UVAS | AJO -> AJO CAEBZAS | SODA DEL CIELO X 500 CC -> SODA SIFON 500 CC
--      Las recetas que usaban el producto que se borra pasan a usar el que queda.
--   2) PIMIENTOS ASADOS y REDUCCION VERMUT (del stock) se unen con sus preparaciones MORRONES ASADOS y REDUCCION DE VERMUT: el precio por kg
--      sale de la receta de produccion y se actualiza solo.
--   3) PICADA VERMUTERA, ANTIPASTI, CONO FYQ, EXQUISITA y PLATO AHUMADO (platos ya armados) pasan a contarse en UNIDADES y su costo por unidad es
--      el costo de su receta, que se recalcula solo cuando cambia un ingrediente.
--   4) El calculo de costos tambien actualiza el costo por unidad de esos platos armados.
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

-- el calculo de costos tambien fija el costo por unidad de un plato armado (receta de tipo plato vinculada a un producto del stock)
create or replace function public._recalcular_costo_recetas(p_insumo_id uuid)
returns integer
language plpgsql security definer set search_path = public as $$
declare
  r record;
  v_tipo text; v_merma numeric; v_insumo_prep uuid; v_nuevo numeric;
  v_filas integer := 0; v_n integer; v_pasada integer := 0; v_cambio boolean;
begin
  loop
    v_pasada := v_pasada + 1;
    v_cambio := false;
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
      v_nuevo := null;
      if v_tipo = 'preparacion' and v_insumo_prep is not null and r.gramos > 0 and (1 - v_merma / 100) > 0 then
        v_nuevo := round(r.costo * 1000 / (r.gramos * (1 - v_merma / 100)), 6);
      elsif v_tipo = 'plato' and v_insumo_prep is not null then
        v_nuevo := round(r.costo, 6);
      end if;
      if v_nuevo is not null then
        update public.insumos set precio_costo_kg = v_nuevo, fecha_ultima_actualizacion = now()
         where id = v_insumo_prep and precio_costo_kg is distinct from v_nuevo;
        get diagnostics v_n = row_count;
        if v_n > 0 then v_cambio := true; end if;
      end if;
    end loop;
    exit when p_insumo_id is not null or not v_cambio or v_pasada >= 4;
  end loop;
  return v_filas;
end;
$$;
revoke all on function public._recalcular_costo_recetas(uuid) from public;

drop table if exists _res79;
create temp table _res79 (orden serial, seccion text, producto text, detalle text);

-- ============================================================ 1) pares de productos repetidos
do $$
declare
  r record; v_con uuid; v_quit uuid; v_pcon numeric; v_pquit numeric;
begin
  perform set_config('app.sin_historial', 'on', true);
  for r in select * from (values
      ('FRUTILLA',                    array['FRUTILLA'],                      array['FRUTILLAS']),
      ('NUEZ',                        array['NUEZ'],                          array['NUECES']),
      ('ACEITUNAS NEGRAS EN RODAJAS', array['ACEITUNAS NEGRAS EN RODAJAS'],  array['ALBARQUINAS ACEITUNAS EN RODAJAS']),
      ('ACEITUNAS NEGRAS (0 kg)',     array['ACEITUNAS NEGRAS EN RODAJAS'],  array['ACEITUNAS NEGRAS']),
      ('UVAS',                        array['UVAS'],                          array['UVAS VERDES']),
      ('AJO',                         array['AJO CAEBZAS'],                   array['AJO']),
      ('SODA SIFON 500 CC',           array['SODA SIFON 500 CC'],            array['SODA DEL CIELO X 500 CC'])
    ) as t(titulo, conservar, quitar)
  loop
    select i.id, i.precio_costo_kg into v_con, v_pcon from public.insumos i left join public.stock s on s.insumo_id = i.id
     where public.normalizar_texto(trim(coalesce(i.marca || ' ', '') || i.nombre)) = any (r.conservar)
     order by (s.insumo_id is not null) desc, i.id limit 1;
    select i.id, i.precio_costo_kg into v_quit, v_pquit from public.insumos i
     where public.normalizar_texto(trim(coalesce(i.marca || ' ', '') || i.nombre)) = any (r.quitar) and i.id is distinct from v_con
     order by i.id limit 1;
    if v_con is null then
      insert into _res79 (seccion, producto, detalle) values ('UNION', r.titulo, 'NO ENCONTRE el producto que se conserva: no se unio');
    elsif v_quit is null then
      insert into _res79 (seccion, producto, detalle) values ('UNION', r.titulo, 'no hay otra copia: nada que unir');
    else
      if coalesce(v_pcon, 0) = 0 and coalesce(v_pquit, 0) > 0 then
        update public.insumos set precio_costo_kg = v_pquit, fecha_ultima_actualizacion = now() where id = v_con;
      end if;
      perform pg_temp._unir(v_con, v_quit);
      insert into _res79 (seccion, producto, detalle) values ('UNION', r.titulo, 'UNIDOS (queda un solo producto)');
    end if;
  end loop;
end
$$;

-- ============================================================ 2) del stock con su preparacion (precio por kg segun su receta)
do $$
declare
  r record; v_rec uuid; v_prep uuid; v_stock uuid; v_nombre text;
begin
  for r in select * from (values
      ('PIMIENTOS ASADOS (morrones asados)',  'MORRONES ASADOS%',     'PIMIENTOS ASADOS'),
      ('REDUCCION VERMUT (reduccion de vermut)', 'REDUCCION DE VERMUT%', 'REDUCCION VERMUT')
    ) as t(titulo, receta_pat, stock_label)
  loop
    v_rec := null; v_prep := null; v_stock := null;
    select id, insumo_id into v_rec, v_prep from public.recetas
     where tipo = 'preparacion' and public.normalizar_texto(nombre_producto) like r.receta_pat order by created_at limit 1;
    select i.id, trim(coalesce(i.marca || ' ', '') || i.nombre) into v_stock, v_nombre from public.insumos i join public.stock s on s.insumo_id = i.id
     where public.normalizar_texto(trim(coalesce(i.marca || ' ', '') || i.nombre)) = r.stock_label and i.id is distinct from v_prep limit 1;
    if v_rec is null then
      insert into _res79 (seccion, producto, detalle) values ('PREPARACION', r.titulo, 'NO ENCONTRE LA RECETA DE PRODUCCION: no se unio');
    elsif v_stock is null then
      insert into _res79 (seccion, producto, detalle) values ('PREPARACION', r.titulo, 'no esta en el stock (o ya es el mismo producto): nada que unir');
    else
      if v_prep is null then
        update public.recetas set insumo_id = v_stock where id = v_rec;
      elsif v_prep <> v_stock then
        perform pg_temp._unir(v_stock, v_prep);
      end if;
      update public.insumos set es_preparacion = true, unidad_medida = 'kg' where id = v_stock;
      insert into _res79 (seccion, producto, detalle) values ('PREPARACION', v_nombre, 'UNIDA con su receta de produccion');
    end if;
  end loop;
end
$$;

-- ============================================================ 3) platos armados: se cuentan en unidades, costo = costo de su receta
do $$
declare
  r record; v_rec uuid; v_stock uuid; v_nombre text;
begin
  for r in select * from (values
      ('PICADA VERMUTERA',  'PICADA VERMUTERA',          'PICADA VERMUTERA'),
      ('ANTIPASTI',         'ANTIPASTI',                 'ANTIPASTI'),
      ('CONO FYQ',          'CONO DE FIAMBRES Y QUESOS', 'CONO FYQ'),
      ('EXQUISITA',         'LA EXQUISITA',              'EXQUISITA'),
      ('PLATO AHUMADO',     'PLATO AHUMADO',             'PLATO AHUMADO')
    ) as t(titulo, receta_nombre, stock_label)
  loop
    v_rec := null; v_stock := null;
    select id into v_rec from public.recetas where tipo = 'plato' and public.normalizar_texto(nombre_producto) = r.receta_nombre order by created_at limit 1;
    select i.id, trim(coalesce(i.marca || ' ', '') || i.nombre) into v_stock, v_nombre from public.insumos i join public.stock s on s.insumo_id = i.id
     where public.normalizar_texto(trim(coalesce(i.marca || ' ', '') || i.nombre)) = r.stock_label limit 1;
    if v_rec is null then
      insert into _res79 (seccion, producto, detalle) values ('PLATO ARMADO', r.titulo, 'NO ENCONTRE LA RECETA ' || r.receta_nombre);
    elsif v_stock is null then
      insert into _res79 (seccion, producto, detalle) values ('PLATO ARMADO', r.titulo, 'NO ESTA EN EL STOCK');
    else
      update public.recetas set insumo_id = v_stock where id = v_rec;
      update public.insumos set es_preparacion = true, unidad_medida = 'unidad' where id = v_stock;
      update public.stock set unidad = 'unidad' where insumo_id = v_stock;
      insert into _res79 (seccion, producto, detalle) values ('PLATO ARMADO', v_nombre, 'en unidades, con el costo de la receta');
    end if;
  end loop;
end
$$;

select public._recalcular_costo_recetas(null) as recetas_recalculadas;

-- ============================================================ resultado
select x.seccion, x.producto, x.detalle
  from (
    select orden, seccion, producto, detalle from _res79
    union all
    select 1000 + row_number() over (order by i.nombre), 'COMO QUEDARON', trim(coalesce(i.marca || ' ', '') || i.nombre),
           'stock ' || s.cantidad_actual || ' ' || coalesce(s.unidad, i.unidad_medida) || ' · precio $' || round(i.precio_costo_kg)
      from public.stock s join public.insumos i on i.id = s.insumo_id
     where public.normalizar_texto(trim(coalesce(i.marca || ' ', '') || i.nombre)) in
       ('FRUTILLA', 'NUEZ', 'ACEITUNAS NEGRAS EN RODAJAS', 'UVAS', 'AJO CAEBZAS', 'SODA SIFON 500 CC', 'PIMIENTOS ASADOS', 'REDUCCION VERMUT',
        'PICADA VERMUTERA', 'ANTIPASTI', 'CONO FYQ', 'EXQUISITA', 'PLATO AHUMADO')
  ) x
 order by x.orden;
