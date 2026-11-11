-- Gata Maula: recetas por porcion de los sandwiches, picoteo y raciones (segun el Recetario Gourmet v2).
--   * Las recetas que YA existen en la app se actualizan en el lugar (mismos platos, cantidades del recetario) y se mantienen sus extras
--     (caja de sandwich, packaging, papas Danal, "pan monto fijo"). Las que faltan se crean.
--   * Las recetas de focaccia entera para eventos NO se tocan.
--   * Pan: focaccia = 1/6 de focaccia entera por sandwich; pan de molde = 1/9. Los ingredientes "c/n" (aceite, tostadas) no se cargan.
--   * Si a una receta le falta encontrar algun ingrediente en el stock, esa receta NO se toca y queda en el resultado como "NO SE TOCO".
--   * Se crean TABLA DE MADERA ($500 cada una, 1 por picada) y, si no existiera, PASTRON GRION (con precio 0: hay que cargarlo).
--   * Al final se recalculan los costos y se muestra, receta por receta, el costo antes y despues y con que producto del stock se unio cada ingrediente.
-- NO descuenta nada del stock todavia (eso viene en la siguiente migracion).
-- Correr UNA vez en el SQL Editor y mandar el resultado. Es seguro correrlo mas de una vez.

-- ============================================================ productos nuevos
insert into public.insumos (nombre, marca, grupo, subcategoria, precio_costo_kg, unidad_medida, origen_alta)
select 'TABLA DE MADERA', null, 'cocina', 'descartables', 500, 'unidad', 'manual'
 where not exists (select 1 from public.insumos where public.normalizar_texto(nombre) = 'TABLA DE MADERA');
insert into public.stock (insumo_id, cantidad_actual, stock_minimo, valorizacion, unidad)
select id, 0, 0, 0, 'unidad' from public.insumos where public.normalizar_texto(nombre) = 'TABLA DE MADERA'
on conflict (insumo_id) do nothing;

insert into public.insumos (nombre, marca, grupo, subcategoria, precio_costo_kg, unidad_medida, origen_alta)
select 'PASTRON', 'GRION', 'cocina', 'fiambres', 0, 'kg', 'manual'
 where not exists (select 1 from public.insumos where public.normalizar_texto(trim(coalesce(marca || ' ', '') || nombre)) like '%PASTRON%');
insert into public.stock (insumo_id, cantidad_actual, stock_minimo, valorizacion, unidad)
select id, 0, 0, 0, 'kg' from public.insumos
 where public.normalizar_texto(trim(coalesce(marca || ' ', '') || nombre)) = 'GRION PASTRON'
on conflict (insumo_id) do nothing;

-- ============================================================ ayuda: buscar un producto del stock por nombre (prefiere el que esta en el stock)
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

-- ============================================================ recetas a cargar
drop table if exists _rec_def;
drop table if exists _rec_lineas;
drop table if exists _rep;
create temp table _rec_def (k text primary key, buscar text, nuevo text, tipo text);   -- buscar = patron del nombre de la receta que ya existe
create temp table _rec_lineas (id serial, rk text, ing text, pats text[], cant numeric, med text, insumo_id uuid);
create temp table _rep (rk text primary key, receta text, accion text, antes numeric, despues numeric, detalle text);

insert into _rec_def (k, buscar, nuevo, tipo) values
  -- sandwiches que ya existen en la app (se actualizan)
  ('S1',  '%PASTRON%RELISH%',            'SANDWICH DE PASTRON, RELISH DE PEPINILLOS Y MOSTAZA', 'sand'),
  ('S2',  '%PORTOBELLO%BRIE%',           'SANDWICH HONGOS, BRIE, MIEL Y RUCULA', 'sand'),
  ('S3',  'LOMO A LAS FINAS%',           'SANDWICH LOMO FINAS HIERBAS', 'sand'),
  ('S4',  'COCIDO%TYBO%PALTA%',          'SANDWICH COCIDO , CREMA DE PALTA', 'sand'),
  ('S5',  'CRUDO%PARMESANO%CHERRY%',     'SANDWICH ESPECIAL JAMON CRUDO', 'sand'),
  -- sandwiches nuevos
  ('S6',  '#NUEVA#',                     'SANDWICH ASADITO ARGENTINO FOCACCIA', 'sand'),
  ('S7',  '#NUEVA#',                     'SANDWICH MORTADELLA PISTACHIO, BURRATINA ALCAUCIL Y CAJU', 'sand'),
  ('S8',  '#NUEVA#',                     'SANDWICH ESPECIAL EMBUCHADO', 'sand'),
  ('S9',  '#NUEVA#',                     'SANDWICH SALAME Y PATEGRAS', 'sand'),
  ('S10', '#NUEVA#',                     'SANDWICH BONDIOLA, BRIE Y MOSTAZA', 'sand'),
  ('S11', '#NUEVA#',                     'SANDWICH VEGGIE FOCACCIA', 'sand'),
  -- picoteo que ya existe (se actualiza)
  ('P1',  'PICADA VERMUTERA',            'PICADA VERMUTERA', 'pic'),
  ('P2',  'ANTIPASTI',                   'ANTIPASTI', 'pic'),
  ('P3',  'LA EXQUISITA',                'LA EXQUISITA', 'pic'),
  ('P4',  'PLATO AHUMADO',               'PLATO AHUMADO', 'pic'),
  ('P5',  'LA CABRITA',                  'LA CABRITA', 'pic'),
  ('P6',  'CONO DE FIAMBRES%',           'CONO DE FIAMBRES Y QUESOS', 'pic'),
  -- nuevos
  ('N1',  '#NUEVA#',                     'PICADA PARA LLEVAR X1 PERSONA', 'pic'),
  ('N2',  '#NUEVA#',                     'CONO SOLO DE QUESOS', 'pic'),
  ('R1',  '#NUEVA#',                     'RACION DIP MEDITERRANEO (90 g)', 'rac'),
  ('R2',  '#NUEVA#',                     'RACION DE LENGUA (120 g)', 'rac'),
  ('R3',  '#NUEVA#',                     'RACION DE HONGOS EN ESCABECHE (120 g)', 'rac'),
  ('R4',  '#NUEVA#',                     'RACION DE PEPINILLOS (120 g)', 'rac'),
  ('R5',  '#NUEVA#',                     'RACION DE ACEITUNAS CONDIMENTADAS (120 g)', 'rac');

insert into _rec_lineas (rk, ing, pats, cant, med) values
  -- S1 pastron
  ('S1','Pan de molde (1/9)',        array['%PAN DE MOLDE ENTERO%','%PAN DE MOLDE%'], 0.111111, 'unidad'),
  ('S1','Pastron',                   array['%GRION%PASTRON%','%PASTRON%GRION%','%PASTRON%'], 80, 'gramos'),
  ('S1','Relish',                    array['RELISH','%RELISH%'], 65, 'gramos'),
  ('S1','Pepinillos',                array['PEPINILLOS','%PEPINILLOS%'], 20, 'gramos'),
  ('S1','Mostaza',                   array['MOSTAZA','%MOSTAZA ANTIGUA%'], 20, 'gramos'),
  -- S2 hongos al escabeche
  ('S2','Pan ciabatta masa madre',   array['%PAN CIABATTA MASA MADRE%','%CIABATTA%'], 1, 'unidad'),
  ('S2','Escabeche de hongos',       array['%HONGOS EN ESCABECHE%','%ESCABECHE DE HONGOS%'], 100, 'gramos'),
  ('S2','Queso brie',                array['%OLALLA%BRIE%','%BRIE%OLALLA%','%QUESO BRIE%'], 70, 'gramos'),
  ('S2','Miel picante',              array['%MIEL PICANTE%','MIEL (KG)','%MIEL%'], 30, 'gramos'),
  ('S2','Rucula',                    array['RUCULA ATADO','%RUCULA%'], 15, 'gramos'),
  -- S3 lomo finas hierbas
  ('S3','Pan de levadura',           array['%PAN BAGUETIN LEVADURA%'], 1, 'unidad'),
  ('S3','Lomo finas hierbas',        array['%GRASETTO%LOMO%FINAS%HIERBAS%','%LOMO%FINAS%HIERBAS%'], 80, 'gramos'),
  ('S3','Queso tybo',                array['%TYBO%PAULINA%'], 50, 'gramos'),
  ('S3','Aderezo verduras',          array['ADEREZO VERDURAS','%ADEREZO%VERDURAS%'], 30, 'gramos'),
  ('S3','Manteca tonadita',          array['%MANTECA TONADITA%'], 5, 'gramos'),
  -- S4 jamon cocido
  ('S4','Pan de levadura',           array['%PAN BAGUETIN LEVADURA%'], 1, 'unidad'),
  ('S4','Jamon cocido',              array['%JAMON COCIDO%'], 80, 'gramos'),
  ('S4','Queso tybo',                array['%TYBO%PAULINA%'], 50, 'gramos'),
  ('S4','Crema de palta',            array['CREMA PALTA','%CREMA%PALTA%'], 8, 'gramos'),
  -- S5 jamon crudo
  ('S5','Pan focaccia (1/6)',        array['FOCACCIA ENTERA','%FOCACCIA ENTERA%'], 0.166667, 'unidad'),
  ('S5','Jamon crudo Il Nonno Alpino', array['%NONNO%JAMON CRUDO%'], 80, 'gramos'),
  ('S5','Parmesano rallado',         array['%MIGUE%PARMESANO%','%PARMESANO%MIGUE%','PARMESANO%HORMA%'], 50, 'gramos'),
  ('S5','Cherrys confitados',        array['CHERRY CONFITADOS','%CHERRY%CONFITADO%'], 30, 'gramos'),
  ('S5','Rucula',                    array['RUCULA ATADO','%RUCULA%'], 15, 'gramos'),
  -- S6 asadito
  ('S6','Pan focaccia (1/6)',        array['FOCACCIA ENTERA','%FOCACCIA ENTERA%'], 0.166667, 'unidad'),
  ('S6','Provoleta',                 array['%PROVOLETA%'], 70, 'gramos'),
  ('S6','Pimiento rojo asado',       array['%MORRONES ASADOS%','PIMIENTO ROJO'], 40, 'gramos'),
  ('S6','Mayo de chimi',             array['MAYO CHIMI','%MAYO%CHIMI%'], 80, 'gramos'),
  ('S6','Caja sandwich',             array['%CAJA SANDWICH XL%'], 1, 'unidad'),
  ('S6','Papas Danal',               array['%PAPAS DANAL%'], 25, 'gramos'),
  -- S7 mortadella con pistachos
  ('S7','Pan focaccia (1/6)',        array['FOCACCIA ENTERA','%FOCACCIA ENTERA%'], 0.166667, 'unidad'),
  ('S7','Stracciatella',             array['%VITTORIOS%STRACCIATELLA%','%STRACCIATELLA%'], 70, 'gramos'),
  ('S7','Castanas tostadas',         array['%CASTANA%CAJU%ASADA%','%CASTANA%ASADA%'], 45, 'gramos'),
  ('S7','Mortadella con pistachos',  array['%MORTADEL%PISTACH%GRASETTO%','%MORTADEL%PISTACH%','%MORTADEL%'], 80, 'gramos'),
  ('S7','Pesto',                     array['%PESTO%'], 50, 'gramos'),
  ('S7','Caja sandwich',             array['%CAJA SANDWICH XL%'], 1, 'unidad'),
  ('S7','Papas Danal',               array['%PAPAS DANAL%'], 25, 'gramos'),
  -- S8 lomo embuchado
  ('S8','Pan ciabatta masa madre',   array['%PAN CIABATTA MASA MADRE%','%CIABATTA%'], 1, 'unidad'),
  ('S8','Lomo embuchado',            array['%BUHO%LOMO%EMBUCHADO%','%LOMO EMBUCHADO%'], 80, 'gramos'),
  ('S8','Queso pategras (Holanda Tio Pujio)', array['%HOLANDA%TIO%PUJIO%'], 70, 'gramos'),
  ('S8','Pate de hongos',            array['%PATE DE HONGOS%'], 60, 'gramos'),
  ('S8','Tomate rallado',            array['%TOMATE RALLADO%'], 60, 'gramos'),
  ('S8','Caja sandwich',             array['%CAJA SANDWICH XL%'], 1, 'unidad'),
  ('S8','Papas Danal',               array['%PAPAS DANAL%'], 25, 'gramos'),
  -- S9 salame de la colonia
  ('S9','Pan de levadura',           array['%PAN BAGUETIN LEVADURA%'], 1, 'unidad'),
  ('S9','Salame Il Nonno Alpino',    array['%NONNO%SALAME%','%SALAME%'], 80, 'gramos'),
  ('S9','Queso pategras (Holanda Tio Pujio)', array['%HOLANDA%TIO%PUJIO%'], 50, 'gramos'),
  ('S9','Tomate rallado',            array['%TOMATE RALLADO%'], 30, 'gramos'),
  ('S9','Manteca saborizada',        array['MANTECA SABORIZADA','%MANTECA%SABORIZADA%'], 10, 'gramos'),
  ('S9','Caja sandwich',             array['%CAJA SANDWICH XL%'], 1, 'unidad'),
  ('S9','Papas Danal',               array['%PAPAS DANAL%'], 25, 'gramos'),
  -- S10 bondiola
  ('S10','Pan de levadura',          array['%PAN BAGUETIN LEVADURA%'], 1, 'unidad'),
  ('S10','Bondiola',                 array['BONDIOLA','%BONDIOLA%'], 80, 'gramos'),
  ('S10','Brie',                     array['%OLALLA%BRIE%','%BRIE%OLALLA%','%QUESO BRIE%'], 50, 'gramos'),
  ('S10','Mostaza',                  array['MOSTAZA','%MOSTAZA ANTIGUA%'], 20, 'gramos'),
  ('S10','Manteca tonadita',         array['%MANTECA TONADITA%'], 5, 'gramos'),
  ('S10','Caja sandwich',            array['%CAJA SANDWICH XL%'], 1, 'unidad'),
  ('S10','Papas Danal',              array['%PAPAS DANAL%'], 25, 'gramos'),
  -- S11 veggie
  ('S11','Pan focaccia (1/6)',       array['FOCACCIA ENTERA','%FOCACCIA ENTERA%'], 0.166667, 'unidad'),
  ('S11','Verduras asadas',          array['%VERDURAS ASADAS%'], 120, 'gramos'),
  ('S11','Criollo ahumado',          array['%CRIOLLO AHUMADO%'], 50, 'gramos'),
  ('S11','Tapenade',                 array['TAPENADE','%TAPENADE%'], 25, 'gramos'),
  ('S11','Cebolla caramelizada',     array['%CEBOLLA CARAMELIZ%'], 10, 'gramos'),
  ('S11','Caja sandwich',            array['%CAJA SANDWICH XL%'], 1, 'unidad'),
  ('S11','Papas Danal',              array['%PAPAS DANAL%'], 25, 'gramos'),
  -- P1 picada vermutera
  ('P1','Jamon crudo El Buho',       array['%BUHO%JAMON CRUDO%'], 50, 'gramos'),
  ('P1','Lomo finas hierbas',        array['%GRASETTO%LOMO%FINAS%HIERBAS%','%LOMO%FINAS%HIERBAS%'], 30, 'gramos'),
  ('P1','Bondiola ahumada',          array['%DINAS%BONDIOLA%AHUMADA%','%BONDIOLA%AHUMADA%'], 30, 'gramos'),
  ('P1','Bresaola',                  array['%BRESAOLA%'], 30, 'gramos'),
  ('P1','Queso azul Vanguard',       array['%QUESO AZUL%VANGUARD%','%AZUL%VANGUARD%'], 30, 'gramos'),
  ('P1','Queso Goya',                array['%FERMIER%GOYA%','%GOYA%'], 30, 'gramos'),
  ('P1','Parmesano Migue',           array['%MIGUE%PARMESANO%','%PARMESANO%MIGUE%','PARMESANO%HORMA%'], 30, 'gramos'),
  ('P1','Gruyere',                   array['%GRUYERE%'], 30, 'gramos'),
  ('P1','Mini camembert',            array['%MINI%CAMEMBERT%','%CAMEMBERT%'], 70, 'gramos'),
  ('P1','Peras caramelizadas',       array['%PERAS CARAMELIZADAS%','PERAS'], 50, 'gramos'),
  ('P1','Castanas de caju',          array['CASTANA DE CAJU','%CASTANA%CAJU%'], 30, 'gramos'),
  ('P1','Reduccion de vermut',       array['%REDUCCION DE VERMUT%'], 20, 'gramos'),
  ('P1','Mix aceitunas rellenas',    array['%ACEITUNAS RELLENAS%MIX%','%ACEITUNAS RELLENAS%'], 50, 'gramos'),
  ('P1','Hongos en escabeche',       array['%HONGOS EN ESCABECHE%'], 40, 'gramos'),
  ('P1','Porotos en escabeche',      array['ESCABECHE DE POROTOS','%POROTOS%ESCABECHE%','%ESCABECHE%POROTOS%'], 40, 'gramos'),
  ('P1','Chocolate blanco',          array['CHOCOLATE BLANCO'], 30, 'gramos'),
  ('P1','Nuez',                      array['NUEZ','%NUEZ%'], 7, 'gramos'),
  ('P1','Almendras',                 array['%ALMENDRAS%'], 7, 'gramos'),
  ('P1','Reduccion de aceto',        array['REDUCCION ACETO','%REDUCCION%ACETO%'], 5, 'gramos'),
  -- P2 antipasti
  ('P2','Jamon crudo El Buho',       array['%BUHO%JAMON CRUDO%'], 50, 'gramos'),
  ('P2','Reggianito',                array['%MIGUE%REGGIANITO%','%REGGIANITO%'], 50, 'gramos'),
  ('P2','Aceite de oliva',           array['ACEITE DE OLIVA','%ACEITE%OLIVA%'], 15, 'gramos'),
  ('P2','Reduccion de aceto',        array['REDUCCION ACETO','%REDUCCION%ACETO%'], 15, 'gramos'),
  -- P3 la exquisita
  ('P3','Brie preparado (dip de brie)', array['%DIP DE BRIE%'], 70, 'gramos'),
  ('P3','Jamon crudo El Buho',       array['%BUHO%JAMON CRUDO%'], 30, 'gramos'),
  ('P3','Morbier',                   array['%MORBIER%'], 30, 'gramos'),
  ('P3','Lincoln',                   array['%LINCOLN%'], 30, 'gramos'),
  ('P3','Frutillas',                 array['FRUTILLAS','%FRUTILLA%'], 15, 'gramos'),
  ('P3','Reduccion de aceto',        array['REDUCCION ACETO','%REDUCCION%ACETO%'], 15, 'gramos'),
  -- P4 plato ahumado
  ('P4','Criollo ahumado',           array['%CRIOLLO AHUMADO%'], 30, 'gramos'),
  ('P4','Bondiola ahumada',          array['%DINAS%BONDIOLA%AHUMADA%','%BONDIOLA%AHUMADA%'], 30, 'gramos'),
  ('P4','Embuchado',                 array['%BUHO%LOMO%EMBUCHADO%','%LOMO EMBUCHADO%'], 30, 'gramos'),
  ('P4','Pepinillos',                array['PEPINILLOS','%PEPINILLOS%'], 60, 'gramos'),
  -- P5 la cabrita
  ('P5','Queso de cabra Crottin',    array['%CROTTIN%'], 40, 'gramos'),
  ('P5','Queso Goya',                array['%FERMIER%GOYA%','%GOYA%'], 40, 'gramos'),
  ('P5','Uvas con azucar',           array['UVAS CON AZUCAR','%UVAS%AZUCAR%'], 80, 'gramos'),
  -- P6 cono de fiambres y quesos
  ('P6','Jamon crudo El Buho',       array['%BUHO%JAMON CRUDO%'], 30, 'gramos'),
  ('P6','Lomo embuchado',            array['%BUHO%LOMO%EMBUCHADO%','%LOMO EMBUCHADO%'], 30, 'gramos'),
  ('P6','Lomo finas hierbas',        array['%GRASETTO%LOMO%FINAS%HIERBAS%','%LOMO%FINAS%HIERBAS%'], 30, 'gramos'),
  ('P6','Bondiola',                  array['BONDIOLA','%BONDIOLA%'], 30, 'gramos'),
  ('P6','Reggianito',                array['%MIGUE%REGGIANITO%','%REGGIANITO%'], 30, 'gramos'),
  ('P6','Queso pategras (Holanda Tio Pujio)', array['%HOLANDA%TIO%PUJIO%'], 30, 'gramos'),
  ('P6','Morbier',                   array['%MORBIER%'], 30, 'gramos'),
  -- N1 picada para llevar, por persona (la tabla de madera es 1 por picada)
  ('N1','Jamon crudo El Buho',       array['%BUHO%JAMON CRUDO%'], 30, 'gramos'),
  ('N1','Salame Il Nonno Alpino',    array['%NONNO%SALAME%','%SALAME%'], 30, 'gramos'),
  ('N1','Bondiola',                  array['BONDIOLA','%BONDIOLA%'], 30, 'gramos'),
  ('N1','Lomo horneado (finas hierbas)', array['%GRASETTO%LOMO%FINAS%HIERBAS%','%LOMO%FINAS%HIERBAS%'], 30, 'gramos'),
  ('N1','Lomo embuchado',            array['%BUHO%LOMO%EMBUCHADO%','%LOMO EMBUCHADO%'], 30, 'gramos'),
  ('N1','Queso brie',                array['%OLALLA%BRIE%','%BRIE%OLALLA%','%QUESO BRIE%'], 25, 'gramos'),
  ('N1','Queso azul Vanguard',       array['%QUESO AZUL%VANGUARD%','%AZUL%VANGUARD%'], 25, 'gramos'),
  ('N1','Queso pategras (Holanda Tio Pujio)', array['%HOLANDA%TIO%PUJIO%'], 25, 'gramos'),
  ('N1','Queso Goya',                array['%FERMIER%GOYA%','%GOYA%'], 25, 'gramos'),
  ('N1','Aceitunas condimentadas',   array['ACEITUNAS CONDIMENTADAS','%ACEITUNAS CONDIMENTADAS%'], 48, 'gramos'),
  ('N1','Escabeche de porotos',      array['ESCABECHE DE POROTOS','%POROTOS%ESCABECHE%'], 48, 'gramos'),
  ('N1','Pepinillos',                array['PEPINILLOS','%PEPINILLOS%'], 48, 'gramos'),
  ('N1','Pan focaccia (1/12)',       array['FOCACCIA ENTERA','%FOCACCIA ENTERA%'], 0.083333, 'unidad'),
  ('N1','Tabla de madera',           array['TABLA DE MADERA'], 1, 'unidad'),
  -- N2 cono solo de quesos (supuesto: los 3 quesos del cono)
  ('N2','Reggianito',                array['%MIGUE%REGGIANITO%','%REGGIANITO%'], 30, 'gramos'),
  ('N2','Queso pategras (Holanda Tio Pujio)', array['%HOLANDA%TIO%PUJIO%'], 30, 'gramos'),
  ('N2','Morbier',                   array['%MORBIER%'], 30, 'gramos'),
  ('N2','Packaging',                 array['PACKAGING','%PACKAGING%'], 1, 'unidad'),
  ('N2','Pan (monto fijo)',          array['PAN (MONTO FIJO)','%MONTO FIJO%'], 1, 'unidad'),
  -- raciones (90 y 120 g de la preparacion)
  ('R1','Dip mediterraneo',          array['%DIP MEDITERRANEO%'], 90, 'gramos'),
  ('R2','Lengua a la vinagreta',     array['%LENGUA A LA VINAGRETA%','LENGUA','%LENGUA%'], 120, 'gramos'),
  ('R3','Hongos en escabeche',       array['%HONGOS EN ESCABECHE%'], 120, 'gramos'),
  ('R4','Pepinillos',                array['PEPINILLOS','%PEPINILLOS%'], 120, 'gramos'),
  ('R5','Aceitunas condimentadas',   array['ACEITUNAS CONDIMENTADAS','%ACEITUNAS CONDIMENTADAS%'], 120, 'gramos');

update _rec_lineas set insumo_id = pg_temp._ins(pats);

-- ============================================================ aplicar
do $$
declare
  d record; v_rec uuid; v_antes numeric; v_cat text; v_falta text; v_accion text;
  v_cat_sand text := (select categoria_carta from public.recetas where public.normalizar_texto(nombre_producto) like '%PASTRON%RELISH%' limit 1);
  v_cat_pic text := (select categoria_carta from public.recetas where public.normalizar_texto(nombre_producto) = 'PICADA VERMUTERA' limit 1);
  v_cat_rac text := (select categoria_carta from public.recetas where public.normalizar_texto(nombre_producto) like 'DIP DE CAMEMBERT%' limit 1);
begin
  for d in select * from _rec_def order by k loop
    select string_agg(ing, ', ') into v_falta from _rec_lineas where rk = d.k and insumo_id is null;
    if v_falta is not null then
      insert into _rep (rk, receta, accion, detalle) values (d.k, d.nuevo, 'NO SE TOCO', 'no encontre en el stock: ' || v_falta);
      continue;
    end if;
    v_rec := null; v_antes := null;
    if d.buscar <> '#NUEVA#' then
      select id, costo_total_calculado into v_rec, v_antes from public.recetas
       where public.normalizar_texto(nombre_producto) like d.buscar and tipo = 'plato' order by created_at limit 1;
    end if;
    if v_rec is null then
      select id, costo_total_calculado into v_rec, v_antes from public.recetas
       where public.normalizar_texto(nombre_producto) = public.normalizar_texto(d.nuevo) order by created_at limit 1;
    end if;
    if v_rec is null then
      v_cat := case d.tipo when 'sand' then coalesce(v_cat_sand, 'SANDWICHES') when 'pic' then coalesce(v_cat_pic, 'PICADAS') else coalesce(v_cat_rac, 'RACIONES') end;
      insert into public.recetas (nombre_producto, categoria_carta, tipo, margen_objetivo) values (d.nuevo, v_cat, 'plato', 65) returning id into v_rec;
      v_accion := 'CREADA';
    else
      -- se borran los ingredientes viejos, menos los extras (caja, packaging, papas, pan monto fijo)
      delete from public.receta_insumos ri using public.insumos i
       where ri.receta_id = v_rec and i.id = ri.insumo_id
         and not (public.normalizar_texto(trim(coalesce(i.marca || ' ', '') || i.nombre)) like any (array['CAJA SANDWICH%', '%PACKAGING%', 'PAPAS DANAL%', '%MONTO FIJO%']));
      v_accion := 'ACTUALIZADA';
    end if;
    insert into public.receta_insumos (receta_id, insumo_id, cantidad, tipo_medida)
    select v_rec, l.insumo_id, sum(l.cant), l.med::tipo_medida_receta
      from _rec_lineas l
     where l.rk = d.k
       and not exists (select 1 from public.receta_insumos x where x.receta_id = v_rec and x.insumo_id = l.insumo_id)
     group by l.insumo_id, l.med;
    insert into _rep (rk, receta, accion, antes, detalle)
    values (d.k, d.nuevo, v_accion, v_antes,
            (select string_agg(l.ing || ' > ' || trim(coalesce(i.marca || ' ', '') || i.nombre), ' | ' order by l.id)
               from _rec_lineas l join public.insumos i on i.id = l.insumo_id where l.rk = d.k));
    update _rep r set receta = (select nombre_producto from public.recetas where id = v_rec) where r.rk = d.k;
  end loop;
end
$$;

-- recalcular los costos de todas las recetas con los ingredientes nuevos
select public._recalcular_costo_recetas(null) as recetas_recalculadas;

update _rep r set despues = (select rc.costo_total_calculado from public.recetas rc
                              where public.normalizar_texto(rc.nombre_producto) = public.normalizar_texto(r.receta) order by rc.created_at limit 1)
 where r.accion in ('CREADA', 'ACTUALIZADA');

-- ============================================================ resultado para revisar
select r.accion, r.receta, round(r.antes) as costo_antes, round(r.despues) as costo_despues, r.detalle
  from _rep r order by case r.accion when 'NO SE TOCO' then 0 else 1 end, r.rk;
