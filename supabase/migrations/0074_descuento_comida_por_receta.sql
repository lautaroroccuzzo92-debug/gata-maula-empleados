-- Gata Maula: la comida que se vende en Postberry descuenta del stock por receta.
--   * pos_receta: une cada producto de Postberry con su receta. modo 'venta' = descuenta al venderse (sandwiches, picada para llevar,
--     conos, raciones); modo 'lote' = se elabora por lote (picada vermutera, antipasti, dips, plato ahumado, La Exquisita, La Cabrita):
--     al venderse NO descuenta ingredientes (los descuenta la carga del lote, que viene en la siguiente tanda).
--   * Cada venta descuenta los ingredientes de su receta SOLO si el ingrediente se lleva en el stock (panes, fiambres, quesos y las preparaciones
--     que se cuentan). Lo que no esta en el stock (pesto, caja, packaging...) se ignora. Igual que con el vermut, descuenta recien desde
--     el conteo de cada producto.
--   * Picada para llevar: la cantidad vendida son las personas; la tabla de madera sale 1 cada 3 personas por ticket.
--   * Se suman al stock (en cero) las frutillas, que la receta de La Exquisita usa y no estaban.
--   * La pantalla "Descuento de stock" muestra "Descuenta por receta: ..." en estos productos.
-- Correr UNA vez en el SQL Editor y mandar el resultado. Es seguro correrlo mas de una vez.

create table if not exists public.pos_receta (
  producto text primary key,
  receta_id uuid not null references public.recetas(id) on delete cascade,
  modo text not null default 'venta' check (modo in ('venta', 'lote')),
  nota text
);
alter table public.pos_receta enable row level security;
drop policy if exists pos_receta_select on public.pos_receta;
create policy pos_receta_select on public.pos_receta for select using (public.rol_actual() in ('admin', 'encargado'));

-- tabla de madera: 1 cada 3 personas por ticket
insert into public.pos_config (clave, valor)
select 'insumo_tabla', id::text from public.insumos where public.normalizar_texto(nombre) = 'TABLA DE MADERA' order by id limit 1
on conflict (clave) do update set valor = excluded.valor;
insert into public.pos_config (clave, valor) values ('personas_por_tabla', '3') on conflict (clave) do nothing;

-- frutillas al stock
insert into public.stock (insumo_id, cantidad_actual, stock_minimo, valorizacion, unidad)
select i.id, 0, 0, 0, case when i.unidad_medida = 'unidad' then 'unidad' else 'kg' end from public.insumos i
 where public.normalizar_texto(trim(coalesce(i.marca || ' ', '') || i.nombre)) = 'FRUTILLAS'
on conflict (insumo_id) do nothing;

-- ============================================================ producto de Postberry -> receta
drop table if exists _map_rep;
create temp table _map_rep (orden serial, producto text, receta text, modo text, estado text);

do $$
declare r record; v_rec uuid; v_prod text; v_recnom text;
begin
  for r in select * from (values
      ('SANDWICH ASADITO ARGENTINO FOCACCIA',                            'SANDWICH ASADITO ARGENTINO%',       'venta'),
      ('SANDWICH MORTADELLA PISTACHIO, BURRATINA ALCAUCIL Y CAJU',       'SANDWICH MORTADELLA PISTACHIO%',    'venta'),
      ('SANDWICH LOMO FINAS HIERBAS',                                    'LOMO A LAS FINAS%',                 'venta'),
      ('SANDWICH DE PASTRON, RELISH DE PEPINILLOS Y MOSTAZA',            'PASTRON, RELISH%',                  'venta'),
      ('SANDWICH BONDIOLA, BRIE Y MOSTAZA',                              'SANDWICH BONDIOLA, BRIE%',          'venta'),
      ('SANDWICH SALAME Y PATEGRAS',                                     'SANDWICH SALAME%',                  'venta'),
      ('SANDWICH ESPECIAL EMBUCHADO',                                    'SANDWICH ESPECIAL EMBUCHADO%',      'venta'),
      ('SANDWICH ESPECIAL JAMON CRUDO',                                  'CRUDO, PARMESANO%',                 'venta'),
      ('SANDWICH HONGOS, BRIE, MIEL Y RUCULA',                           'PORTOBELLOS%',                      'venta'),
      ('SANDWICH VEGGIE FOCACCIA',                                       'SANDWICH VEGGIE%',                  'venta'),
      ('SANDWICH COCIDO , CREMA DE PALTA',                               'COCIDO, TYBO%',                     'venta'),
      ('PICADA PARA LLEVAR X1 PERSONA',                                  'PICADA PARA LLEVAR%',               'venta'),
      ('CONO DE FIAMBRES Y QUESOS',                                      'CONO DE FIAMBRES%',                 'venta'),
      ('CONO SOLO DE QUESOS',                                            'CONO SOLO%',                        'venta'),
      ('LENGUA RACION',                                                  'RACION DE LENGUA%',                 'venta'),
      ('HONGOS RACION',                                                  'RACION DE HONGOS%',                 'venta'),
      ('PEPINILLOS RACION',                                              'RACION DE PEPINILLOS%',             'venta'),
      ('ACEITUNAS CONDIMENTADAS RACION',                                 'RACION DE ACEITUNAS CONDIMENTADAS%','venta'),
      ('ACEITUNAS VERDES RACION',                                        'ACEITUNAS VERDES CONDIMENTADAS%',   'venta'),
      ('MIX DE ACEITUNAS RELLENAS RACION',                               'MIX DE ACEITUNAS RELLENAS%',        'venta'),
      ('TRIPLE CONSERVA',                                                'TRIPLE CONSERVA%',                  'venta'),
      ('PICADA VERMUTERA',                                               'PICADA VERMUTERA',                  'lote'),
      ('ANTIPASTI',                                                      'ANTIPASTI',                         'lote'),
      ('DIP MEDITERRANEO',                                               'RACION DIP MEDITERRANEO%',          'lote'),
      ('DIP DE CAMEMBERT',                                               'DIP DE CAMEMBERT%',                 'lote'),
      ('PLATO AHUMADO',                                                  'PLATO AHUMADO',                     'lote'),
      ('LA EXQUISITA',                                                   'LA EXQUISITA',                      'lote'),
      ('LA CABRITA',                                                     'LA CABRITA',                        'lote')
    ) as t(producto, receta_pat, modo)
  loop
    v_prod := null; v_rec := null; v_recnom := null;
    select l.producto into v_prod from (select distinct producto from public.pos_lineas) l
     where regexp_replace(public.normalizar_texto(l.producto), '\s+', ' ', 'g') = regexp_replace(public.normalizar_texto(r.producto), '\s+', ' ', 'g')
     limit 1;
    select id, nombre_producto into v_rec, v_recnom from public.recetas
     where tipo = 'plato' and public.normalizar_texto(nombre_producto) like r.receta_pat order by created_at limit 1;
    if v_prod is null then
      insert into _map_rep (producto, receta, modo, estado) values (r.producto, v_recnom, r.modo, 'ese producto no tiene ventas cargadas en Postberry (no se vincula)');
      continue;
    end if;
    if v_rec is null then
      insert into _map_rep (producto, receta, modo, estado) values (v_prod, null, r.modo, 'NO ENCONTRE LA RECETA');
      continue;
    end if;
    insert into public.pos_receta (producto, receta_id, modo) values (v_prod, v_rec, r.modo)
      on conflict (producto) do update set receta_id = excluded.receta_id, modo = excluded.modo;
    delete from public.pos_producto where producto = v_prod and omitir is not null;
    delete from public.pos_vinculo where producto = v_prod;   -- para no descontar dos veces
    insert into _map_rep (producto, receta, modo, estado) values (v_prod, v_recnom, r.modo, 'VINCULADO');
  end loop;
  -- sandwich fuera de carta
  insert into public.pos_producto (producto, familia, omitir, nota)
  select l.producto, max(l.familia), 'comida', 'Fuera de carta'
    from public.pos_lineas l where public.normalizar_texto(l.producto) = 'SANDWICH BARRIO FINO' group by l.producto
  on conflict (producto) do update set omitir = excluded.omitir, nota = excluded.nota;
end
$$;

-- ============================================================ calculo del consumo (bebidas y vermut como antes + recetas)
create or replace function public._pos_aplicar(p_desde timestamp, p_hasta timestamp)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_merma numeric := coalesce((select valor::numeric from public.pos_config where clave = 'merma_medida_pct'), 0);
  v_msoda numeric := greatest(coalesce((select valor::numeric from public.pos_config where clave = 'medidas_por_soda'), 3), 1);
  v_soda uuid := (select valor::uuid from public.pos_config where clave = 'insumo_soda');
  v_tabla uuid := (select valor::uuid from public.pos_config where clave = 'insumo_tabla');
  v_ppt numeric := greatest(coalesce((select valor::numeric from public.pos_config where clave = 'personas_por_tabla'), 3), 1);
  v_filas int; v_desc int;
begin
  update public.stock s set cantidad_actual = s.cantidad_actual + x.t,
         valorizacion = greatest(s.cantidad_actual + x.t, 0) * coalesce(i.precio_costo_kg, 0), ultima_actualizacion = now()
    from (select insumo_id, sum(cantidad) as t from public.pos_consumo where fecha between p_desde and p_hasta and descontado group by insumo_id) x
    join public.insumos i on i.id = x.insumo_id
   where s.insumo_id = x.insumo_id;
  delete from public.pos_consumo where fecha between p_desde and p_hasta;

  insert into public.pos_consumo (venta_id, fecha, dia, producto, insumo_id, cantidad, descontado)
  select g.venta_id, g.fecha, (g.fecha - interval '6 hours')::date, g.producto, g.insumo_id, g.cantidad,
         coalesce(st.conteo_en is not null and g.fecha > (st.conteo_en at time zone 'America/Argentina/Buenos_Aires'), false)
    from (
      -- bebidas y vermut (vinculos por producto)
      select l.venta_id, l.fecha, l.producto, v.insumo_id,
             l.cantidad * case v.modo
               when 'unidad' then v.valor
               when 'ml' then v.valor / i.ml_por_unidad
               else v.valor * (i.ml_medida * (1 + v_merma / 100)) / i.ml_por_unidad end as cantidad
        from public.pos_lineas l
        join public.pos_vinculo v on v.producto = l.producto
        join public.insumos i on i.id = v.insumo_id
       where not l.anulado and l.fecha between p_desde and p_hasta and coalesce(l.cantidad, 0) <> 0
         and (v.modo = 'unidad' or coalesce(i.ml_por_unidad, 0) > 0)
         and (v.modo <> 'medida' or coalesce(i.ml_medida, 0) > 0)
      union all
      -- soda: 1 cada 3 medidas del mismo ticket
      select t.venta_id, t.fecha, 'SODA (1 cada ' || v_msoda::int || ' medidas)', v_soda, ceil(t.med / v_msoda)
        from (select l.venta_id, min(l.fecha) as fecha, sum(l.cantidad * v.valor) as med
                from public.pos_lineas l join public.pos_vinculo v on v.producto = l.producto
               where v.lleva_soda and not l.anulado and l.fecha between p_desde and p_hasta
               group by l.venta_id) t
       where v_soda is not null and t.med > 0
      union all
      -- comida: ingredientes de la receta (solo los que se llevan en el stock); la tabla de madera va aparte
      select x.venta_id, x.fecha, x.producto, x.insumo_id, x.cant_venta * x.cant_receta / x.divisor
        from (
          select l.venta_id, l.fecha, l.producto, ri.insumo_id, l.cantidad as cant_venta, ri.cantidad as cant_receta,
                 case when ri.tipo_medida::text = 'unidad' then (case when st2.unidad = 'kg' then null else 1 end)
                      when coalesce(st2.unidad, i2.unidad_medida) = 'kg' then 1000
                      when coalesce(st2.unidad, i2.unidad_medida) = 'unidad' and coalesce(i2.gramos_paquete, 0) > 0 then i2.gramos_paquete
                      else null end as divisor
            from public.pos_lineas l
            join public.pos_receta pr on pr.producto = l.producto and pr.modo = 'venta'
            join public.receta_insumos ri on ri.receta_id = pr.receta_id
            join public.insumos i2 on i2.id = ri.insumo_id
            join public.stock st2 on st2.insumo_id = ri.insumo_id
           where not l.anulado and l.fecha between p_desde and p_hasta and coalesce(l.cantidad, 0) <> 0
             and ri.insumo_id is distinct from v_tabla
        ) x
       where x.divisor is not null
      union all
      -- tabla de madera de la picada para llevar: 1 cada 3 personas por ticket
      select t.venta_id, t.fecha, 'TABLA (1 cada ' || v_ppt::int || ' personas)', v_tabla, ceil(t.personas / v_ppt)
        from (select l.venta_id, min(l.fecha) as fecha, sum(l.cantidad) as personas
                from public.pos_lineas l
                join public.pos_receta pr on pr.producto = l.producto and pr.modo = 'venta'
                join public.receta_insumos ri on ri.receta_id = pr.receta_id and ri.insumo_id = v_tabla
               where not l.anulado and l.fecha between p_desde and p_hasta
               group by l.venta_id) t
       where v_tabla is not null and t.personas > 0
    ) g
    left join public.stock st on st.insumo_id = g.insumo_id;
  get diagnostics v_filas = row_count;

  update public.stock s set cantidad_actual = s.cantidad_actual - x.t,
         valorizacion = greatest(s.cantidad_actual - x.t, 0) * coalesce(i.precio_costo_kg, 0), ultima_actualizacion = now()
    from (select insumo_id, sum(cantidad) as t from public.pos_consumo where fecha between p_desde and p_hasta and descontado group by insumo_id) x
    join public.insumos i on i.id = x.insumo_id
   where s.insumo_id = x.insumo_id;
  select count(*) into v_desc from public.pos_consumo where fecha between p_desde and p_hasta and descontado;
  return jsonb_build_object('consumos', v_filas, 'descontados', v_desc);
end;
$$;
revoke all on function public._pos_aplicar(timestamp, timestamp) from public;

-- ============================================================ pantalla de descuento: tambien muestra las recetas
create or replace function public.pos_productos_vinculos() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if public.rol_actual() not in ('admin', 'encargado') then raise exception 'Sin permiso'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'producto', p.producto, 'familia', p.familia, 'unidades', p.u, 'omitir', pp.omitir, 'nota', pp.nota,
      'receta', (select r.nombre_producto from public.pos_receta x join public.recetas r on r.id = x.receta_id where x.producto = p.producto),
      'receta_modo', (select x.modo from public.pos_receta x where x.producto = p.producto),
      'vinculos', coalesce((select jsonb_agg(jsonb_build_object('insumo_id', v.insumo_id, 'modo', v.modo, 'valor', v.valor, 'lleva_soda', v.lleva_soda,
                                'insumo', trim(coalesce(i.marca || ' ', '') || i.nombre)) order by v.id)
                              from public.pos_vinculo v join public.insumos i on i.id = v.insumo_id where v.producto = p.producto), '[]'::jsonb))
      order by p.u desc)
    from (select producto, max(familia) as familia, sum(cantidad) as u from public.pos_lineas where not anulado group by producto) p
    left join public.pos_producto pp on pp.producto = p.producto), '[]'::jsonb);
end;
$$;
grant execute on function public.pos_productos_vinculos() to authenticated;

create or replace function public.pos_estado_descuento() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if public.rol_actual() not in ('admin', 'encargado') then raise exception 'Sin permiso'; end if;
  return jsonb_build_object(
    'ventas_hasta', (select max(fecha) from public.pos_lineas),
    'consumo_hasta', (select max(fecha) from public.pos_consumo),
    'sin_vincular', coalesce((select jsonb_agg(jsonb_build_object('producto', p.producto, 'familia', p.familia, 'unidades', p.u) order by p.u desc)
                                from (select producto, max(familia) as familia, sum(cantidad) as u from public.pos_lineas where not anulado group by producto) p
                               where not exists (select 1 from public.pos_vinculo v where v.producto = p.producto)
                                 and not exists (select 1 from public.pos_receta r where r.producto = p.producto)
                                 and not exists (select 1 from public.pos_producto x where x.producto = p.producto and x.omitir is not null)), '[]'::jsonb),
    'sin_conteo', coalesce((select jsonb_agg(jsonb_build_object('id', z.id, 'nombre', z.nombre) order by z.nombre)
                              from (select distinct i.id, trim(coalesce(i.marca || ' ', '') || i.nombre) as nombre
                                      from public.pos_consumo c join public.insumos i on i.id = c.insumo_id
                                      left join public.stock s on s.insumo_id = c.insumo_id
                                     where s.conteo_en is null or s.insumo_id is null) z), '[]'::jsonb),
    'sin_ml', coalesce((select jsonb_agg(jsonb_build_object('id', z.id, 'nombre', z.nombre) order by z.nombre)
                          from (select distinct i.id, trim(coalesce(i.marca || ' ', '') || i.nombre) as nombre
                                  from public.pos_vinculo v join public.insumos i on i.id = v.insumo_id
                                 where (v.modo in ('ml', 'medida') and coalesce(i.ml_por_unidad, 0) <= 0) or (v.modo = 'medida' and coalesce(i.ml_medida, 0) <= 0)) z), '[]'::jsonb)
  );
end;
$$;
grant execute on function public.pos_estado_descuento() to authenticated;

-- ============================================================ recalcular todo lo ya cargado
do $$
declare a timestamp; b timestamp;
begin
  select min(fecha), max(fecha) into a, b from public.pos_lineas;
  if a is not null then perform public._pos_aplicar(a, b); end if;
end
$$;

-- ============================================================ resultado
select x.seccion, x.a, x.b, x.c
  from (
    select orden, 'VINCULO'::text as seccion, producto as a, coalesce(receta, '') as b, modo || ' · ' || estado as c from _map_rep
    union all
    -- ingredientes de las recetas "al vender" que NO se llevan en el stock: no descuentan
    select 1000 + row_number() over (order by z.nombre), 'NO DESCUENTA (no esta en el stock)', z.nombre, z.recetas, ''
      from (select trim(coalesce(i.marca || ' ', '') || i.nombre) as nombre, string_agg(distinct r.nombre_producto, ' | ') as recetas
              from public.pos_receta pr join public.recetas r on r.id = pr.receta_id
              join public.receta_insumos ri on ri.receta_id = r.id join public.insumos i on i.id = ri.insumo_id
              left join public.stock st on st.insumo_id = i.id
             where pr.modo = 'venta' and st.insumo_id is null group by 1) z
    union all
    -- ingredientes en el stock que no se pudieron convertir (unidad distinta a la de la receta): NO descuentan
    select 2000 + row_number() over (order by z.nombre), 'SIN CONVERSION (revisar unidad)', z.nombre, z.recetas, z.motivo
      from (select trim(coalesce(i.marca || ' ', '') || i.nombre) as nombre, string_agg(distinct r.nombre_producto, ' | ') as recetas,
                   'receta en ' || ri.tipo_medida::text || ' · el stock se cuenta en ' || coalesce(st.unidad, i.unidad_medida) as motivo
              from public.pos_receta pr join public.recetas r on r.id = pr.receta_id
              join public.receta_insumos ri on ri.receta_id = r.id join public.insumos i on i.id = ri.insumo_id
              join public.stock st on st.insumo_id = i.id
             where pr.modo = 'venta' and i.id is distinct from (select valor::uuid from public.pos_config where clave = 'insumo_tabla')
               and ((ri.tipo_medida::text = 'unidad' and st.unidad = 'kg')
                 or (ri.tipo_medida::text = 'gramos' and coalesce(st.unidad, i.unidad_medida) = 'unidad' and coalesce(i.gramos_paquete, 0) <= 0)
                 or (ri.tipo_medida::text = 'gramos' and coalesce(st.unidad, i.unidad_medida) not in ('kg', 'unidad')))
             group by 1, 3) z
  ) x
 order by x.orden;
