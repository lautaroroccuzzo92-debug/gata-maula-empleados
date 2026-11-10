-- Gata Maula: vincula los productos de Postberry que habian quedado sin vincular y crea H2O NARANJA.
--   * Federal, Giovannoni, La Fuerza (rojo/bianco), Lui 746, Mala Maria Torino, Viarava Patente
--   * Agua mineral, Fermentum, Hoppy Tea, Paso de los Toros Tonica (lata), H2O Naranja (producto nuevo)
--   * Las botellas "+ soda" descuentan ademas 1 SODA 1250 CC
--   * Giovannoni: la medida es de 98 ml (la 0061 no la habia reconocido por el nombre)
-- Quedan sin vincular: "APERITIVO SIN ALCOHOL LORENZO 750 CC" (no dice si es tinto o bianco).
-- Correr en el SQL Editor despues de la 0064. Es seguro correrlo mas de una vez.

-- ============================================================ producto nuevo: H2O NARANJA
insert into public.insumos (nombre, marca, grupo, subcategoria, precio_costo_kg, unidad_medida, origen_alta)
select 'H2O SABORIZADA NARANJA', null, 'bebidas', 'cerveza y sin alcohol', 0, 'unidad', 'manual'
 where not exists (select 1 from public.insumos where nombre = 'H2O SABORIZADA NARANJA');
insert into public.stock (insumo_id, cantidad_actual, stock_minimo, valorizacion, unidad)
select id, 0, 0, 0, 'unidad' from public.insumos where nombre = 'H2O SABORIZADA NARANJA'
on conflict (insumo_id) do nothing;

-- ============================================================ medida de Giovannoni (98 ml)
update public.insumos set ml_medida = 98
 where public.normalizar_texto(nombre) like '%GIOVANNONI%' and subcategoria::text = 'vermut';

-- ============================================================ vinculos
do $$
declare
  r record;
  v_grande uuid := (select valor::uuid from public.pos_config where clave = 'insumo_soda_grande');
begin
  for r in
    select p.producto, i.id as insumo_id, m.modo, m.valor, m.lleva_soda, m.soda_grande
      from (values
        -- medidas (el vaso)
        ('MEDIDA LA FUERZA BIANCO', 'LA FUERZA VERMUT BLANCO', 'medida', 1, true, false),
        ('MEDIDA LA FUERZA ROJO', 'LA FUERZA VERMUT ROSSO', 'medida', 1, true, false),
        ('MEDIDA LUI VERMU 746', 'LUI VERMUT 746 ROJO', 'medida', 1, true, false),
        ('MEDIDA MALA MARIA ESTILO TORINO', 'MALA MARIA VERMUT ESTILO ITALIANO', 'medida', 1, true, false),
        ('MEDIDA FEDERAL ROSSATO', 'VERMUT FEDERAL ROSADO', 'medida', 1, true, false),
        ('MEDIDA FEDERAL ROSSO', 'VERMUT FEDERAL', 'medida', 1, true, false),
        ('MEDIDA GIOVANONI BIANCO', 'GIOVANNONI SECO750ML', 'medida', 1, true, false),
        ('MEDIDA VIARAVA PATENTE', 'VIARAVA VERMUT BARRIO', 'medida', 1, true, false),
        -- botellas para llevar
        ('LA FUERZA VERMUT ROJO', 'LA FUERZA VERMUT ROSSO', 'unidad', 1, false, false),
        ('LUI VERMU 746', 'LUI VERMUT 746 ROJO', 'unidad', 1, false, false),
        ('FEDERAL ROSSATO', 'VERMUT FEDERAL ROSADO', 'unidad', 1, false, false),
        ('FEDERAL ROSSO VERMUT', 'VERMUT FEDERAL', 'unidad', 1, false, false),
        ('VIARAVA PATENTE VERMUT', 'VIARAVA VERMUT BARRIO', 'unidad', 1, false, false),
        -- botellas para tomar en el local (botella + soda grande)
        ('LA FUERZA ROJO + SIFON SODA + CITRICO', 'LA FUERZA VERMUT ROSSO', 'unidad', 1, false, true),
        ('LUI VERMUT 746 + SIFON DE SODAS + CITRICOS', 'LUI VERMUT 746 ROJO', 'unidad', 1, false, true),
        ('FEDERAL ROSSO + SIFON SODA + CITRICO', 'VERMUT FEDERAL', 'unidad', 1, false, true),
        ('BOTELLA VIARAVA PATENTE + SODA + HIELO', 'VIARAVA VERMUT BARRIO', 'unidad', 1, false, true),
        -- bebidas (1 a 1)
        ('AGUA MINERAL 500CC', 'NESTLE AGUA MINERAL', 'unidad', 1, false, false),
        ('CERVEZA FERMENTUM', 'FERMENTUM', 'unidad', 1, false, false),
        ('HOPPY TE LUPULADO LORENZOS', 'HOPPY TEA', 'unidad', 1, false, false),
        ('PASO DE LOS TOROS TONICA', 'PASO DE LOS TOROS LATA', 'unidad', 1, false, false),
        ('H2O NARANJA', 'H2O SABORIZADA NARANJA', 'unidad', 1, false, false)
      ) as m(producto, insumo, modo, valor, lleva_soda, soda_grande)
      join (select distinct producto from public.pos_lineas) p
        on public.normalizar_texto(p.producto) = public.normalizar_texto(m.producto)
      join public.insumos i on i.nombre = m.insumo
  loop
    insert into public.pos_vinculo (producto, insumo_id, modo, valor, lleva_soda)
    values (r.producto, r.insumo_id, r.modo, r.valor, r.lleva_soda)
    on conflict (producto, insumo_id) do update set modo = excluded.modo, valor = excluded.valor, lleva_soda = excluded.lleva_soda;
    if r.soda_grande and v_grande is not null then
      insert into public.pos_vinculo (producto, insumo_id, modo, valor, lleva_soda)
      values (r.producto, v_grande, 'unidad', 1, false)
      on conflict (producto, insumo_id) do update set modo = 'unidad', valor = 1, lleva_soda = false;
    end if;
    -- si estaban marcados como "no descuenta", se saca la marca
    delete from public.pos_producto where producto = r.producto and omitir is not null;
  end loop;
end
$$;

-- ============================================================ recalcular el consumo con los vinculos nuevos
do $$
declare a timestamp; b timestamp;
begin
  select min(fecha), max(fecha) into a, b from public.pos_lineas;
  if a is not null then perform public._pos_aplicar(a, b); end if;
end
$$;

-- ============================================================ resultado: como quedaron los productos tocados y lo que sigue sin vincular
select p.producto,
       coalesce((select string_agg(i.nombre || ' [' || v.modo || ' ' || v.valor || ']', ' + ' order by v.id) from public.pos_vinculo v join public.insumos i on i.id = v.insumo_id where v.producto = p.producto),
                (select 'NO DESCUENTA: ' || x.omitir from public.pos_producto x where x.producto = p.producto and x.omitir is not null),
                'SIN VINCULAR') as descuenta
  from (select distinct producto from public.pos_lineas) p
 where public.normalizar_texto(p.producto) ~ '(FEDERAL|GIOVANON|LA FUERZA.*(ROJO|BIANCO)|LUI VERMU|TORINO|VIARAVA PATENTE|AGUA MINERAL|FERMENTUM|H2O|HOPPY|TOROS|APERITIVO SIN ALCOHOL LORENZO 750)'
 order by 1;
