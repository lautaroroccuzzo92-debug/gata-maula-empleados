-- Gata Maula: carga las cantidades del stock desde tu planilla PPTO (14) (hoja de cada rubro, columna 'Hay').
--   * busca cada producto por el enlace a Costos Variables, por el nombre que usaba la planilla o por su nombre; si hay varios renglones de la planilla que van al mismo producto, suma
--   * solo actualiza productos que YA estan en el stock; los que no encuentra o no estan en el stock quedan en la lista del resultado (no se crea nada)
--   * guarda lo que habia antes en la tabla import_stock_log por si hay que volver atras
--   * al final muestra la lista para revisar (tipo: no_encontrado / sin_stock / no_esta_en_la_planilla / cambio)
-- Correr UNA vez en el SQL Editor (despues de 0036). Exportar el resultado a CSV con el boton Export y pasarmelo.

create table if not exists public.import_stock_log (
  id bigserial primary key, corrida timestamptz not null default now(), hoja text, nombre_hoja text, hay numeric, estado text,
  insumo_id uuid, insumo text, antes numeric, ahora numeric, via text
);

create or replace function public._stock_match(p_nombre text, p_marca text)
returns uuid language sql stable security definer set search_path = public as $$
  select i.id from public.insumos i
   where not i.es_preparacion and p_nombre is not null
     and upper(regexp_replace(trim(i.nombre), '\s+', ' ', 'g')) = upper(regexp_replace(trim(p_nombre), '\s+', ' ', 'g'))
     and upper(coalesce(trim(i.marca), '')) = upper(coalesce(trim(p_marca), ''))
   order by exists (select 1 from public.stock s where s.insumo_id = i.id) desc, i.fecha_ultima_actualizacion desc limit 1
$$;
revoke all on function public._stock_match(text, text) from public;

do $$
declare t record; k uuid; k_sin uuid; c uuid; via_sin text; v_via text; v_corrida timestamptz := now(); v_nom text; v_mar text;
begin
  delete from public.import_stock_log where corrida < now() - interval '30 days';
  create temporary table if not exists _imp (hoja text, nombre_hoja text, hay numeric, insumo_id uuid, via text) on commit drop;
  truncate _imp;
  for t in select * from (values
    ('vermut', 'AJENJO DRY', 1, null, 'VERMUT AJENJO DRY', 'VERMUT AJENJO DRY', ''),
    ('vermut', 'AJENJO ROJO', 2, null, 'VERMUT AJENJO ROJO', 'VERMUT AJENJO ROJO', ''),
    ('vermut', 'AJENJO ROSSO', 8, null, 'VERMUT AJENJO ROSSO', 'VERMUT AJENJO ROSSO', ''),
    ('vermut', 'AL VOLEO BIANCO', 7, null, 'AL VOLEO VERMUT BIANCO', 'AL VOLEO VERMUT BIANCO', ''),
    ('vermut', 'AL VOLEO ROSSO', 6, null, 'AL VOLEO VERMUT ROSSO', 'AL VOLEO VERMUT ROSSO', ''),
    ('vermut', 'BELGRANO DE BARRIO', 0, null, 'VERMUT BELGRANO 960 ML', 'VERMUT BELGRANO 960 ML', ''),
    ('vermut', 'BELGRANO DE LITORAL', 0, null, 'VERMUT BELGRANO DEL LITORAL 960 ML', 'VERMUT BELGRANO DEL LITORAL 960 ML', ''),
    ('vermut', 'BELGRANO SERRANO', 0, null, 'VERMUT BELGRANO SERRANO', 'VERMUT BELGRANO SERRANO', ''),
    ('vermut', 'BUM BUM VERMUT', 8, null, 'BUM BUM  "VERMUT ITALIANO"', 'BUM BUM "VERMUT ITALIANO"', ''),
    ('vermut', 'CANTIERI BIANCO', 0, null, 'VERMUT CANTIERI BIANCO', 'VERMUT CANTIERI BIANCO', ''),
    ('vermut', 'CANTIERI ROSSO', 0, null, 'VERMUT CANTIERI ROSSO', 'VERMUT CANTIERI ROSSO', ''),
    ('vermut', 'DESCONFIADO', 0, null, 'DESCONFIADO VERMUT LA SEPTIMA', 'DESCONFIADO VERMUT LA SEPTIMA', ''),
    ('vermut', 'DIO FAUSS BLANCO', 0, null, 'DIO FAUSS VERMUT BLANCO', 'DIO FAUSS VERMUT BLANCO', ''),
    ('vermut', 'DIO FAUSS ROSADO', 0, null, 'DIO FAUSS VERMUT ROSADO', 'DIO FAUSS VERMUT ROSADO', ''),
    ('vermut', 'DIO FAUSS TINTO', 0, null, 'DIO FAUSS VERMUT TINTO', 'DIO FAUSS VERMUT TINTO', ''),
    ('vermut', 'FAMIGILIA ROSSO ROBLE', 3, null, 'FAMIGLIA DELLE VEDOVE ROSSO ROBLE', 'FAMIGLIA DELLE VEDOVE ROSSO ROBLE', ''),
    ('vermut', 'FAMIGLIA  DELLE VEDOVE ROSSO', 5, null, 'FAMIGLIA DELLE VEDOVE ROSSO', 'FAMIGLIA DELLE VEDOVE ROSSO', ''),
    ('vermut', 'FAMIGLIA VEDOVE FRIULIANI', 0, null, 'FAMIGLIA DELLE VEDOVE FRIULIANI', 'FAMIGLIA DELLE VEDOVE FRIULIANI', ''),
    ('vermut', 'FASANO', 0, null, 'FASANO ROSSO', 'FASANO ROSSO', ''),
    ('vermut', 'FEDERAL', 4, null, 'VERMUT FEDERAL', 'VERMUT FEDERAL', ''),
    ('vermut', 'FEDERAL ROSSATO', 12, null, 'VERMUT FEDERAL ROSADO', 'VERMUT FEDERAL ROSADO', ''),
    ('vermut', 'GATA MAULA', 9, null, 'VERMUT GATA MAULA', 'VERMUT GATA MAULA', ''),
    ('vermut', 'GATA MAULA BARRIL 20LTS', 0, null, 'BARRIL VERMUT GATA MAULA', '', ''),
    ('vermut', 'GATA MAULA BARRIL', 0, null, 'BARRIL VERMUT GATA MAULA', '', ''),
    ('vermut', 'GILBER JUAN ROSSO', 0, null, 'GILBER JUAN', 'GILBER JUAN', ''),
    ('vermut', 'GIOVANONNI BIANCO', 2, null, 'GIOVANNONI SECO750ML', 'GIOVANNONI SECO750ML', ''),
    ('vermut', 'GIOVANONNI ROSSO', 1, null, 'GIOVANNONI ROSSO 750ML', 'GIOVANNONI ROSSO 750ML', ''),
    ('vermut', 'HIERBA MALA VERMUT', 0, null, 'HIERBA MALA VERMUT', 'HIERBA MALA VERMUT', ''),
    ('vermut', 'IL TANO ROSE', 0, null, 'VERMUT IL TANO ROSSO', 'VERMUT IL TANO ROSSO', ''),
    ('vermut', 'IL TANO ROSSO', 0, null, 'VERMUT IL TANO ROSSE', 'VERMUT IL TANO ROSSE', ''),
    ('vermut', 'INFINITO BIANCO VERMUT', 0, null, 'DESMADRE', 'DESMADRE', ''),
    ('vermut', 'INFINITO VERMUT', 0, null, 'VERMUT INFINITO BIANCO', 'VERMUT INFINITO BIANCO', ''),
    ('vermut', 'JOLGORIO', 1, null, 'JOLGORIO ROSSO VERMUT', 'JOLGORIO ROSSO VERMUT', ''),
    ('vermut', 'LA CHARLA VERMUT BIANCO', 0, null, 'LA CHARLA BIANCO', 'LA CHARLA BIANCO', ''),
    ('vermut', 'LA CHARLA VERMUT ROSSO', 0, null, 'LA CHARLA ROSSO', 'LA CHARLA ROSSO', ''),
    ('vermut', 'LA CHARLA ROSSO INTENSO', 0, null, 'LA CHARLA ROSSO', '', ''),
    ('vermut', 'LA CHARLA BIB', 0.9, null, 'LA CHARLA BIB ROSSO', '', ''),
    ('vermut', 'LA FUERZA BIANCO', 5, null, 'LA FUERZA VERMUT BLANCO', 'LA FUERZA VERMUT BLANCO', ''),
    ('vermut', 'LA FUERZA PRIMAVERA', 6, null, 'LA FUERZA VERMUT PRIMAVERA', 'LA FUERZA VERMUT PRIMAVERA', ''),
    ('vermut', 'LA FUERZA PROYECTO LOCAL', 1, null, 'LA FUERZA PROYECTO LOCAL', 'LA FUERZA PROYECTO LOCAL', ''),
    ('vermut', 'LA FUERZA ROSSO', 11, null, 'LA FUERZA VERMUT ROSSO', 'LA FUERZA VERMUT ROSSO', ''),
    ('vermut', 'LA FUERZA SIDERAL', 6, null, 'LA FUERZA VERMUT SIDERAL', 'LA FUERZA VERMUT SIDERAL', ''),
    ('vermut', 'LA FUERZA SIDERAL BARRICA UNICA', 6, null, 'LA FUERZA VERMUT SIDERAL BARRICA UNICA', 'LA FUERZA VERMUT SIDERAL BARRICA UNICA', ''),
    ('vermut', 'LEONCE ROSADO', 5, null, 'LEONCE ROSE VERMUTH', 'LEONCE ROSE VERMUTH', ''),
    ('vermut', 'LEONCE ROSSO', 4, null, 'LEONCE MALBEC VERMUTH', 'LEONCE MALBEC VERMUTH', ''),
    ('vermut', 'LOMBRONI BAG IN BOX', 1.6, null, 'LOMBRONI ROSSO BAG IN BOX', 'LOMBRONI ROSSO BAG IN BOX', ''),
    ('vermut', 'LOMBRONI BIANCO', 1, null, 'LOMBRONI VERMUT BIANCO', 'LOMBRONI VERMUT BIANCO', ''),
    ('vermut', 'LOMBRONI ROSSO', 0, null, 'LOMBRONI VERMUT ROSSO', 'LOMBRONI VERMUT ROSSO', ''),
    ('vermut', 'LORENZO TINTO', 2, null, 'LORENZO TINTO BOTELLA', 'LORENZO TINTO BOTELLA', ''),
    ('vermut', 'LORENZO BIANCO', 5, null, 'LORENZO BLANCO BOTELLA', 'LORENZO BLANCO BOTELLA', ''),
    ('vermut', 'LORENZO TINTO BAG IN BOX', 0, null, 'VERMUT LORENZOS BAG IN BOX', 'VERMUT LORENZOS BAG IN BOX', ''),
    ('vermut', 'LUNFA BIANCO', 0, null, 'LUNFA BIANCO', 'LUNFA BIANCO', ''),
    ('vermut', 'LUNFA ROSADO', 8, null, 'LUNFA ROSSO', 'LUNFA ROSSO', ''),
    ('vermut', 'LUNFA ROSSO', 6, null, 'LUNFA ROSADO', 'LUNFA ROSADO', ''),
    ('vermut', 'MALA MARIA FRANCES', 4, null, 'MALA MARIA VERMUT ESTILO FRANCES', 'MALA MARIA VERMUT ESTILO FRANCES', ''),
    ('vermut', 'MALA MARIA IL CACCIATORE', 3, null, 'IL CACCIATORE "VERMUT ITALIANO"', 'IL CACCIATORE "VERMUT ITALIANO"', ''),
    ('vermut', 'MALA MARIA LE REFUGE', 3, null, 'LE REFUGE "VERMUT FRANCES"', 'LE REFUGE "VERMUT FRANCES"', ''),
    ('vermut', 'MALA MARIA TORINO', 10, null, 'MALA MARIA VERMUT ESTILO ITALIANO', 'MALA MARIA VERMUT ESTILO ITALIANO', ''),
    ('vermut', 'METODICO VERMUT', 3, null, 'VERMUT METODICO', 'VERMUT METODICO', ''),
    ('vermut', 'MIL DEMONIOS', 0, null, 'VERMUT MIL DEMONIOS', 'VERMUT MIL DEMONIOS', ''),
    ('vermut', 'NUESTRO ROSSO', 12, null, 'NUESTRO VERMUT BIANCO', 'NUESTRO VERMUT BIANCO', ''),
    ('vermut', 'NUESTRO BIANCO', 5, null, 'NUESTRO VERMUT ROSSO', 'NUESTRO VERMUT ROSSO', ''),
    ('vermut', 'PICHINCHA', 0, null, 'VERMUT PICHINCHA', 'VERMUT PICHINCHA', ''),
    ('vermut', 'PICHINCHA BAG IN BOX', 0, null, 'VERMUT PICHINCHA BAG IN BOX', 'VERMUT PICHINCHA BAG IN BOX', ''),
    ('vermut', 'POCIMARIO BIANCO', 0, null, 'VERMUT POCIMARIO BLANCO', 'VERMUT POCIMARIO BLANCO', ''),
    ('vermut', 'POCIMARIO ROSADO', 0, null, 'VERMUT POCIMARIO ROSADO', 'VERMUT POCIMARIO ROSADO', ''),
    ('vermut', 'PRIMMO BIANCO', 3, null, 'VERMUT PRIMMO BIANCO', 'VERMUT PRIMMO BIANCO', ''),
    ('vermut', 'PRIMMO ROSADO', 5, null, 'VERMUT PRIMMO ROSADO', 'VERMUT PRIMMO ROSADO', ''),
    ('vermut', 'PRIMMO', 6, null, 'VERMUT PRIMMO ROSSO', 'VERMUT PRIMMO ROSSO', ''),
    ('vermut', 'ROCA MADRE', 6, null, 'ROCAMADRE VERMUT', 'ROCAMADRE VERMUT', ''),
    ('vermut', 'SABADO VERMUT ROSSO', 0, null, 'SABADO VERMUT', 'SABADO VERMUT', ''),
    ('vermut', 'SIN APURO ISABELLA', 2, null, 'SIN APURO VERMUT SYRAH', 'SIN APURO VERMUT SYRAH', ''),
    ('vermut', 'SIN APURO SYRAH', 4, null, 'SIN APURO VERMUT SYRAH', '', ''),
    ('vermut', 'TANDIL PICAPEDRERO ROSSO', 0, null, 'VERMUT PICAPEDRERO', 'VERMUT PICAPEDRERO', ''),
    ('vermut', 'TANDIL PIONERA BIANCO', 0, null, 'VERMUT PIONERA', 'VERMUT PIONERA', ''),
    ('vermut', 'TRINCHERA BIANCO', 0, null, 'VERMUT TRINCHERA ROSSO', 'VERMUT TRINCHERA ROSSO', ''),
    ('vermut', 'TRINCHERA ROSSO', 0, null, 'VERMUT TRINCHERA BLANCO', 'VERMUT TRINCHERA BLANCO', ''),
    ('vermut', 'VERMUT 746', 1, null, 'LUI VERMU 746', 'LUI VERMU 746', ''),
    ('vermut', 'ABSUELTO ROSSO', 0, null, null, '', ''),
    ('vermut', 'SALVA GARCIA', 0, null, 'VERMUT VESTA', 'VERMUT VESTA', ''),
    ('vermut', 'VIARAVA', 3, null, 'VIARAVA VERMUT', 'VIARAVA VERMUT', ''),
    ('vermut', 'VIARAVA TINTO', 4, null, null, '', ''),
    ('vermut', 'PETRICORE', 1, null, 'VERMUT PETRICORE', 'VERMUT PETRICORE', ''),
    ('vermut', 'ARRABAL ROJO', 0, null, 'ARRABAL ROJO', 'ARRABAL ROJO', ''),
    ('vermut', 'ARRABAL DRY', 0, null, 'ARRABAL BIANCO', 'ARRABAL BIANCO', ''),
    ('vermut', 'MENGANO', 6, null, 'VERMUT MENGANO BLANCO', 'VERMUT MENGANO BLANCO', ''),
    ('vermut', 'FULANO', 4, null, 'VERMUT FULANO ROJO', 'VERMUT FULANO ROJO', ''),
    ('vermut', 'LORENZO TINTO MAGNUM', 2.5, null, null, '', ''),
    ('vermut', '746 DORADO', 3, null, null, '', ''),
    ('vermut', 'MALARIA + MANIJA', 3, null, null, '', ''),
    ('vermut', 'INTERFERENCIA ROSSO', 2, null, null, '', ''),
    ('vermut', 'INTERFERECIA TEMPRANILLO', 1, null, null, '', ''),
    ('vermut', 'INTERFERENCIA BIB CATEDRAL', 0.4, null, null, '', ''),
    ('cerveza y sin alcohol', 'APERITIVO LORENZO TINTO 750', 0, null, 'APERITIVO SIN ALCOHOL LORENZO BAG IN BOX 3L', 'APERITIVO SIN ALCOHOL LORENZO BAG IN BOX 3L', ''),
    ('cerveza y sin alcohol', 'APERITIVO LORENZO BIANCO 750', 1, null, 'APERITIVO SIN ALCOHOL TINTO LORENZO BOTELLA 750 CC', 'APERITIVO SIN ALCOHOL TINTO LORENZO BOTELLA 750 CC', ''),
    ('cerveza y sin alcohol', 'FERNET SIN ALCOHOL LORENZO', 0, null, null, '', ''),
    ('cerveza y sin alcohol', 'CERVERZA FERMENTUM', 21, null, 'FERMENTUM', 'FERMENTUM', ''),
    ('cerveza y sin alcohol', 'CERVEZA VIARAVA', 0, null, null, '', ''),
    ('cerveza y sin alcohol', 'HOPPY TEA LUPULIS', 8, null, 'HOPPY TEA', 'HOPPY TEA', ''),
    ('cerveza y sin alcohol', 'AGUA', 0, null, 'NESTLE  AGUA MINERAL', 'NESTLE AGUA MINERAL', ''),
    ('cerveza y sin alcohol', 'H2O NARANJA', 0, null, 'AWAFRUT SABORIZADA 500CC', 'AWAFRUT SABORIZADA 500CC', ''),
    ('cerveza y sin alcohol', 'H2O SABORIZADA LIMON', 0, null, 'AWAFRUT SABORIZADA 500CC', '', ''),
    ('cerveza y sin alcohol', 'H2O SABORIZADA MANZANA', 0, null, 'AWAFRUT SABORIZADA 500CC', '', ''),
    ('cerveza y sin alcohol', 'H2O SABORIZADA POMELO', 0, null, 'AWAFRUT SABORIZADA 500CC', '', ''),
    ('cerveza y sin alcohol', 'MIRINDA MANZANA', 0, null, null, '', ''),
    ('cerveza y sin alcohol', 'PASO DE LOS TOROS POMELO', 15, null, null, '', ''),
    ('cerveza y sin alcohol', 'PASO DE LOS TOROS TONICA', 8, null, 'PASO DE LOS TOROS LATA', 'PASO DE LOS TOROS LATA', ''),
    ('cerveza y sin alcohol', 'PEPSI', 5, null, 'PEPSI X 500 CC', 'PEPSI X 500 CC', ''),
    ('cerveza y sin alcohol', 'PEPSI BLACK', 3, null, 'PEPSI SIN AZUCAR X 500 CC', 'PEPSI SIN AZUCAR X 500 CC', ''),
    ('cerveza y sin alcohol', 'SEVEN UP', 12, null, 'SEVEN UP', 'SEVEN UP', ''),
    ('cerveza y sin alcohol', 'SEVEN UP FREE', 0, null, null, '', ''),
    ('cerveza y sin alcohol', 'CERVEZA PERONI', 12, null, 'FILLS 90 GR', 'FILLS 90 GR', ''),
    ('cerveza y sin alcohol', 'DANAL 800 GR', 0.58, null, 'PAPAS DANAL', 'PAPAS DANAL', ''),
    ('fiambres', 'GRASSETTO MORTADELA CON PISTACHOS', 3.28, null, 'CAMPO AUSTRAL MORTADELA CON PISTACHO', 'CAMPO AUSTRAL MORTADELA CON PISTACHO', ''),
    ('fiambres', 'GRASSETO LOMO', 0, 'GRASETTO', 'LOMO FINAS HIERBAS HORNEADO', 'LOMO FINAS HIERBAS HORNEADO', 'GRASETTO'),
    ('fiambres', 'COLONIAL LOMO', 1.09, 'CALCHAQUI', 'JAMON COCIDO', 'JAMON COCIDO', 'CALCHAQUI'),
    ('fiambres', 'DON ANTONINO JAMON COCIDO', 0, 'CORDOBA FOOD', 'JAMON COCIDO SOL DEL PILAR', 'JAMON COCIDO SOL DEL PILAR', 'CORDOBA FOOD'),
    ('fiambres', 'EL BUHO JAMON CRUDO', 3.66, 'EL BUHO', 'JAMON CRUDO', 'JAMON CRUDO', 'EL BUHO'),
    ('fiambres', 'EL BUHO LOMO EMBUCHADO', 0.08, 'EL BUHO', 'LOMO EMBUCHADO', 'LOMO EMBUCHADO', 'EL BUHO'),
    ('fiambres', 'GRION PASTRON', 2.76, 'FAMILIA GRION', 'PASTRON AL PIMENTON', 'PASTRON AL PIMENTON', 'FAMILIA GRION'),
    ('fiambres', 'IL NONNO ALPINO SALAME', 2.48, 'IL NONNO ALPINO', 'SALAME', 'SALAME', 'IL NONNO ALPINO'),
    ('fiambres', 'IL NONNO ALPINO JAMON CRUDO', 6.8, 'IL NONNO ALPINO', 'JAMON CRUDO', 'JAMON CRUDO', 'IL NONNO ALPINO'),
    ('fiambres', 'IL NONNOALPINO BONDIOLA', 2.1, 'IL NONNO ALPINO', 'BONDIOLA', 'BONDIOLA', 'IL NONNO ALPINO'),
    ('fiambres', 'COCIDO COLONIAL', 5.34, null, null, '', ''),
    ('fiambres', 'LAS DINAS BONDIOLA AHUMADA', 0, 'LAS DINAS', 'BONDIOLA AHUMADA', 'BONDIOLA AHUMADA', 'LAS DINAS'),
    ('fiambres', 'LAS DINAS BRESAOLA', 1.34, 'LAS DINAS', 'BRESAOLA', 'BRESAOLA', 'LAS DINAS'),
    ('fiambres', 'CRUDO KUTSY', 0, null, 'LA PEQUEÑA JAMON CRUDO', 'LA PEQUEÑA JAMON CRUDO', ''),
    ('fiambres', 'CRUDO TACRA', 0, null, null, '', ''),
    ('fiambres', 'SALAME MILAN', 0, 'NAPOLES', 'SALAME MILAN', 'SALAME MILAN', 'NAPOLES'),
    ('quesos', 'VITTORIOS STRACCIATELLA', 4.5, 'VITTORIOS', 'STRACCIATELLA', 'STRACCIATELLA', 'VITTORIOS'),
    ('quesos', 'FERMIER CRIOLLO AHUMADO', 1.31, 'FERMIER', 'CRIOLLO AHUMADO', 'CRIOLLO AHUMADO', 'FERMIER'),
    ('quesos', 'FERMIER FONTINA', 3.13, 'FERMIER', 'QUESO FONTINA', 'QUESO FONTINA', 'FERMIER'),
    ('quesos', 'FERMIER GOYA', 3.02, 'FERMIER', 'GOYA', 'GOYA', 'FERMIER'),
    ('quesos', 'FERMIER MORBIER', 2.25, 'FERMIER', 'MORBIER', 'MORBIER', 'FERMIER'),
    ('quesos', 'LA PAULINA TYBO PATEGRAS', 3.05, null, 'TYBO LA PAULINA', 'TYBO LA PAULINA', ''),
    ('quesos', 'LA SUERTE LINCOLN', 2.5, 'LA SUERTE', 'LINCOLN', 'LINCOLN', 'LA SUERTE'),
    ('quesos', 'MIGUE PARMESANO', 3.99, 'MIGUE', 'PARMESANO 1/2 HORMA X 3KG', 'PARMESANO 1/2 HORMA X 3KG', 'MIGUE'),
    ('quesos', 'MIGUE  REGGIANITO', 0, 'MIGUE', 'QUESO REGGIANITO', 'QUESO REGGIANITO', 'MIGUE'),
    ('quesos', 'TIO PUJIO HOLANDA', 0, 'NAPOLES', 'HOLANDA TIO PUJIO', 'HOLANDA TIO PUJIO', 'NAPOLES'),
    ('quesos', 'TIO PUJIO SARDO', 0, null, null, '', ''),
    ('quesos', 'TIO PUJIO GRUYERE', 0, 'NAPOLES', 'GRUYERE TIO PUJIO', 'GRUYERE TIO PUJIO', 'NAPOLES'),
    ('quesos', 'SANTA OLALLA BRIE', 3.26, 'SANTA OLALLA', 'QUESO BRIE X HORMA DE 800 GR SANATA OLALLA', 'QUESO BRIE X HORMA DE 800 GR SANATA OLALLA', 'SANTA OLALLA'),
    ('quesos', 'SANTA OLALLA CAMEMBERT 50G', 0.56, 'SANTA OLALLA', 'MINI QUESO CAMEMBERT', 'MINI QUESO CAMEMBERT', 'SANTA OLALLA'),
    ('quesos', 'CREMAC SARDO', 0, 'NAPOLES', 'SARDO SOBRERO CREMAC', 'SARDO SOBRERO CREMAC', 'NAPOLES'),
    ('quesos', 'LUCRECIA PROVOLETA', 0.55, 'NAPOLES', 'PROVOLETA LUCRECIA', 'PROVOLETA LUCRECIA', 'NAPOLES'),
    ('quesos', 'LA QUESERA GRUYERITO', 0, null, 'GRUYERE LA QUESERA', 'GRUYERE LA QUESERA', ''),
    ('quesos', 'VANGUARD AZUL', 0.61, null, 'QUESO AZUL BAVARIA', 'QUESO AZUL BAVARIA', ''),
    ('quesos', 'SANTA OLALLA CROTTIN', 1.03, null, null, '', ''),
    ('quesos', 'GRUYERITO LACTOS PREMIUM', 2.8, null, null, '', ''),
    ('quesos', 'AZUL TORO AZUL', 0, 'SANTA OLALLA', 'AZUL TORO AZUL', 'AZUL TORO AZUL', 'SANTA OLALLA'),
    ('quesos', 'PATEGRAS lactear', 0, 'COLONIA ORCOVI', 'PATEGRAS X 4KG', 'PATEGRAS X 4KG', 'COLONIA ORCOVI'),
    ('quesos', 'TYBO GOLACTEOS KUTSI', 0, null, 'GOLACTEOS TYBO', 'GOLACTEOS TYBO', ''),
    ('quesos', 'CRIOLLO LACTEOS PREMIUM (REEMPLAZO PATEGRAS)3,7', 0, 'COLONIA ORCOVI', 'PATEGRAS X 4KG', '', ''),
    ('quesos', 'MIGUE PROVOLETA', 0, 'MIGUE', 'PROVOLONE MEDIA HORMA AL VACIO X 1.5KG', 'PROVOLONE MEDIA HORMA AL VACIO X 1.5KG', 'MIGUE'),
    ('quesos', 'brie LA BOHEME', 0, 'NAPOLES', 'BRIE  LA BOHEEM', 'BRIE LA BOHEEM', 'NAPOLES'),
    ('quesos', 'PATEGRAS ORCOVI', 0, null, null, '', ''),
    ('quesos', 'HOLANDA LACTEOS PREMIUM', 1.2, null, null, '', ''),
    ('quesos', 'TYBO NOALASA', 0, 'WAGGON', 'TYBO NOALSA', 'TYBO NOALSA', 'WAGGON'),
    ('quesos', 'ROMANITO MIGUE', 2.23, null, null, '', ''),
    ('cocina', 'ACEITE DE OLIVA', 11.5, null, 'ACEITE DE OLIVA 20LTS', '', ''),
    ('cocina', 'ACEITE GIRASOL', 5, null, 'ACEITE DE GIRASOL BARBIERI 10LTS', '', ''),
    ('cocina', 'ACEITUNAS RELLENAS', 0, null, 'ACEITUNAS RELLENAS MIX WARA PALLAY 1,5 KG', '', ''),
    ('cocina', 'ACEITUNAS VERDES', 0.3, null, 'ACEITUNAS VERDES WARA PALLAY 3KG', '', ''),
    ('cocina', 'ACEITUNAS CONDIMENTADAS', 1.13, null, null, '', ''),
    ('cocina', 'CHOCOLATE BLANCO', 0.08, null, null, '', ''),
    ('cocina', 'REDUCCION ACETO', 0.85, null, null, '', ''),
    ('cocina', 'REDUCCION VERMUT', 0.615, null, null, '', ''),
    ('cocina', 'ALBAHACA FRESCA', 0, null, null, '', ''),
    ('cocina', 'AJI MOLIDO', 0.07, null, 'AJI MOLIDO', '', ''),
    ('cocina', 'AJO CAEBZAS', 0.1, null, 'AJO', '', ''),
    ('cocina', 'ARROZ', 0.5, null, null, '', ''),
    ('cocina', 'AJO POLVO', 0.23, null, 'AJO EN POLVO', '', ''),
    ('cocina', 'ALBAHACA SECA', 0.165, null, 'ALBAHACA', '', ''),
    ('cocina', 'ALCAUCIL', 0, null, 'CORAZON DE ALCAUCIL WARA PALLAY 3 KG', '', ''),
    ('cocina', 'AZUCAR', 1.31, null, 'AZUCAR', '', ''),
    ('cocina', 'BERENJENA', 0, null, 'BERENJENA', '', ''),
    ('cocina', 'CASTAÑAS TOSTADAS', 0.55, null, null, '', ''),
    ('cocina', 'CASTAÑAS CAJU', 1, null, 'CASTAÑA DE CAJU', '', ''),
    ('cocina', 'ANCO', 1.56, null, null, '', ''),
    ('cocina', 'CILANTRO', 0.3, null, null, '', ''),
    ('cocina', 'PAPA', 2, null, null, '', ''),
    ('cocina', 'CEBOLLA', 0.8, null, 'CEBOLLA', '', ''),
    ('cocina', 'CEBOLLA POLVO', 0, null, 'CEBOLLA EN POLVO', '', ''),
    ('cocina', 'MAYO CHIMI', 0.2, null, null, '', ''),
    ('cocina', 'CHIMICHURRI', 0.125, null, null, '', ''),
    ('cocina', 'CORIANDRO', 0.35, null, null, '', ''),
    ('cocina', 'CREMA', 0, null, 'CREMA tonadita waggon', '', ''),
    ('cocina', 'CURCUMA', 0.32, null, 'CURCUMA', '', ''),
    ('cocina', 'ESPARRAGOS', 0, null, 'ESPARRAGOS', '', ''),
    ('cocina', 'GARBANZO', 0, null, 'GARBANZOS', '', ''),
    ('cocina', 'GELATIN SIN SABOR', 0.335, null, 'GELATINA SIN SABOR', '', ''),
    ('cocina', 'HONGOS DESHIDRATADOS', 0.375, null, 'HONGOS DE PINO', '', ''),
    ('cocina', 'LECHE (UNIDAD - CAJA)', 2, null, 'LECHE ENTERA LARGA VIDA', '', ''),
    ('cocina', 'LENGUA', 0.9, null, 'LENGUA A LA VINAGRETA', '', ''),
    ('cocina', 'LIMON', 2.315, null, 'LIMON', '', ''),
    ('cocina', 'NUECES', 1.16, null, null, '', ''),
    ('cocina', 'MERKEN', 0.225, null, null, '', ''),
    ('cocina', 'MANTECA', 2.89, null, 'MANTECA TONADITA', '', ''),
    ('cocina', 'MIEL (KG)', 1.3, null, 'MIEL', '', ''),
    ('cocina', 'MOSTAZA', 0.89, null, 'MOSTAZA NATURA X3KG', '', ''),
    ('cocina', 'MOSTAZA EN GRANOS', 0.2, null, null, '', ''),
    ('cocina', 'OREGANO', 0.13, null, 'OREGANO', '', ''),
    ('cocina', 'ADEREZO VERDURAS', 0.54, null, null, '', ''),
    ('cocina', 'TAPENADE', 0.55, null, null, '', ''),
    ('cocina', 'MANTECA SABORIZADA', 0.3, null, null, '', ''),
    ('cocina', 'UVAS CON AZUCAR', 0.34, null, null, '', ''),
    ('cocina', 'CEBOLLA CARAMELIZDA', 0.53, null, null, '', ''),
    ('cocina', 'VERDURAS ASADAS', 0.9, null, null, '', ''),
    ('cocina', 'ACEITUNAS NEGRAS', 2.45, null, null, '', ''),
    ('cocina', 'PEPINILLOS', 3, null, 'PEPINILLOS WARA PALLAY 3 KG', '', ''),
    ('cocina', 'PEPINO', 0, null, 'PEPINO', '', ''),
    ('cocina', 'PERAS', 0, null, 'PERAS', '', ''),
    ('cocina', 'PEREJIL', 0, null, 'PEREJIL', '', ''),
    ('cocina', 'PIMENTON', 0.1, null, 'PIMENTON AHUMADO', '', ''),
    ('cocina', 'PIMENTON AHUMADO', 0.385, null, null, '', ''),
    ('cocina', 'PIMIENTA NEGRA EN GRANO', 0.235, null, 'PIMIENTA MOLIDA', '', ''),
    ('cocina', 'PIMIENTA NEGRA MOLIDA', 0, null, 'PIMIENTA MOLIDA', '', ''),
    ('cocina', 'POROTOS PALLARES', 0.5, null, 'ESCABECHE DE POROTOS BLANCO', '', ''),
    ('cocina', 'CHAMPI (ESCABECHE)', 3.1, null, 'ESCABECHE DE PORTOBELLOS', '', ''),
    ('cocina', 'CHAMPI', 0.44, null, null, '', ''),
    ('cocina', 'QUESO CREMA', 3, null, 'QUESO CREMA', '', ''),
    ('cocina', 'REMOLACHA', 0, null, 'REMOLACHA', '', ''),
    ('cocina', 'ROMERO PAQUETES', 0.01, null, 'ROMERO', '', ''),
    ('cocina', 'RUCULA ATADO', 1, null, 'RUCULA ATADO', '', ''),
    ('cocina', 'SAL FINA', 0.265, null, 'SAL FINA', '', ''),
    ('cocina', 'SAL GRUESA', 0.375, null, 'SAL GRUESA', '', ''),
    ('cocina', 'SEMILLAS DE ENEBRO', 0, null, null, '', ''),
    ('cocina', 'SEMILLAS SESAMO', 0, null, 'SESAMO BLANCO', '', ''),
    ('cocina', 'CHERRY CONFITADOS', 1.29, null, null, '', ''),
    ('cocina', 'TOMATE PERITA', 2.37, null, 'TOMATE PERITA', '', ''),
    ('cocina', 'PIMINETO AMARILLO', 0.265, null, null, '', ''),
    ('cocina', 'PIMIENTO VERDE', 1.12, null, null, '', ''),
    ('cocina', 'PIMINETO ROJO', 0.77, null, null, '', ''),
    ('cocina', 'PIMIENTOS ASADOS', 0.18, null, null, '', ''),
    ('cocina', 'TOMATES CHERRYS', 1, null, 'TOMATES CHERRY', '', ''),
    ('cocina', 'TOMATES DESHIDRATADOS', 0.5, null, 'TOMATES DISECADOS', '', ''),
    ('cocina', 'TOMILLO', 0.24, null, 'TOMILLO', '', ''),
    ('cocina', 'VINAGRE', 3, null, 'VINAGRE DE ALCOHOL MENOYO 10LTS', '', ''),
    ('cocina', 'ZUCCINI', 0.83, null, null, '', ''),
    ('cocina', 'VERDEO', 0.22, null, null, '', ''),
    ('cocina', 'PEREJIL', 0.255, null, null, '', ''),
    ('cocina', 'ZANAHORIA', 0.48, null, 'ZANAHORIA', '', ''),
    ('cocina', 'RELISH', 2.1, null, null, '', ''),
    ('cocina', 'NARANJA', 1.18, null, null, '', ''),
    ('cocina', 'POMELO', 2.735, null, null, '', ''),
    ('cocina', 'LIMA', 0.52, null, null, '', ''),
    ('cocina', 'PERA', 0.235, null, null, '', ''),
    ('cocina', 'PESTO', 0.65, null, null, '', ''),
    ('cocina', 'CEBOLLA MORADA', 1.385, null, 'CEBOLLA MORADA', '', ''),
    ('cocina', 'REPOLLO', 0.64, null, 'REPOLLO', '', ''),
    ('cocina', 'MANZANA VERDE', 0, null, 'MANZANA VERDE', '', ''),
    ('cocina', 'CREMA PALTA', 0.15, null, null, '', ''),
    ('cocina', 'PALTA', 0.075, null, 'PALTA', '', ''),
    ('cocina', 'POROTOS SECOS', 0, null, 'POROTOS PALLARES', '', ''),
    ('cocina', 'ESCABECHE DE POROTOS', 1.35, null, null, '', ''),
    ('cocina', 'ALBONDIGAS', 0, null, null, '', ''),
    ('cocina', 'BONDIOLA', 0, null, null, '', ''),
    ('cocina', 'PLATO AHUMADO', 1, null, null, '', ''),
    ('cocina', 'EXQUISITA', 2, null, null, '', ''),
    ('cocina', 'ANTIPASTI', 2, null, null, '', ''),
    ('cocina', 'DIP MEDITERRANEO', 1.63, null, null, '', ''),
    ('cocina', 'UVAS', 0.325, null, null, '', ''),
    ('cocina', 'FRUTILLA', 0.15, null, null, '', ''),
    ('cocina', 'PICADA VERMUTERA', 2, null, null, '', ''),
    ('cocina', 'CONO FYQ', 3, null, null, '', ''),
    ('panes', 'Barras', 0, null, 'BARRA DE MASA MADRE', 'BARRA DE MASA MADRE', ''),
    ('panes', 'Ciabatta', 53, null, 'Pan ciabatta masa madre', 'Pan ciabatta masa madre', ''),
    ('panes', 'Focaccia ENTERAS', 12, null, 'FOCACCIA ENTERA', 'FOCACCIA ENTERA', ''),
    ('panes', 'Foccacias (cortados/sandwichs)', 2, null, 'focaccia CORTADA', 'focaccia CORTADA', ''),
    ('panes', 'Levadura Comun', 115, null, 'PAN BAGUETIN LEVADURA', 'PAN BAGUETIN LEVADURA', ''),
    ('panes', 'Pan de Molde ENTERO', 4, null, 'PAN DE MOLDE BRIOCHE', '', ''),
    ('panes', 'Molde cortados / sandwich{', 6, null, null, '', ''),
    ('panes', 'PAN PAPA BURGER', 0, 'WAGGON', 'PAN HAMBURGUESA GOLDEN LISO KALIS', 'PAN HAMBURGUESA GOLDEN LISO KALIS', 'WAGGON'),
    ('panes', 'SCHIACCIATA', 3, null, null, '', ''),
    ('panes', 'SCHIACCIATA FRACC.', 11, null, null, '', ''),
    ('panes', 'PANZ CIABATTA', 0, 'PANZ', 'PAN CIABATTA', 'PAN CIABATTA', 'PANZ'),
    ('panes', 'PANZ PAN A LA CHAPA', 2, null, 'PAN A LA CHAPA', 'PAN A LA CHAPA', ''),
    ('panes', 'PANZ PANCHOS', 51, null, null, '', ''),
    ('panes', 'TORTILLAS MACHOTE', 51, 'MACHOTE', 'WRAP GRANDE', 'WRAP GRANDE', 'MACHOTE'),
    ('descartables', 'CAJAS', 200, null, null, '', ''),
    ('descartables', 'BOLSAS MADERA', 250, null, null, '', ''),
    ('descartables', 'CAJAS REGALO', 14, null, null, '', ''),
    ('descartables', 'BOBINA', 1, null, null, '', ''),
    ('descartables', 'tapas', 0, null, null, '', ''),
    ('descartables', 'FRASCOS PLASTICO', 0, null, null, '', ''),
    ('descartables', 'FOILEX', 1, null, null, '', ''),
    ('descartables', 'ROLLOS MERCADO PAGO', 14, null, null, '', ''),
    ('descartables', 'ROLLOS POSNET', 7, null, null, '', ''),
    ('descartables', 'ROLLOS COMANDERAS', 6, null, null, '', ''),
    ('descartables', 'BOLSAS ENVASADORA', 0, null, null, '', ''),
    ('descartables', 'CINTA SCOTCH', 0, null, null, '', '')
  ) as v(sub, nombre_hoja, hay, cv_marca, cv_desc, map_nombre, map_marca) loop
    k := null; v_via := null; k_sin := null; via_sin := null; c := null;
    -- 1) casos que la planilla enlazaba mal o que se unieron / renombraron en la app
    select o.n, o.m into v_nom, v_mar from (values
      ('CERVEZA PERONI','PERONI',null), ('PEPSI','PEPSI 354CC',null), ('PEPSI BLACK','PEPSI BLACK 354CC',null), ('SEVEN UP','SEVEN UP 354CC',null),
      ('SIN APURO ISABELLA','SIN APURO VERMUT ISABELLA',null), ('VANGUARD AZUL','QUESO AZUL VANGUARD',null), ('AZUL BAVARIA','QUESO AZUL BAVARIA',null),
      ('MIGUE REGGIANITO','QUESO REGGIANITO','MIGUE'), ('LUI VERMU 746','LUI VERMUT 746 ROJO',null), ('LUI VERMU 746 DORADO','LUI VERMUT 746 DORADO',null), ('746 DORADO','LUI VERMUT 746 DORADO',null),
      ('DANAL 800 GR','PAPAS DANAL',null), ('CONDIMENTO P/CHIMI A','CHIMICHURRI',null), ('POROTOS','POROTOS PALLARES',null), ('POROTOS SECOS','POROTOS PALLARES',null),
      ('PERA','PERAS',null), ('PIMINETO ROJO','PIMIENTO ROJO',null), ('PIMINETO AMARILLO','PIMIENTO AMARILLO',null), ('ZUCCINI','ZUCCHINI',null),
      ('MOSTAZA EN GRANOS','MOSTAZA EN GRANO AMARILLA',null), ('MOSTAZA EN GRANO','MOSTAZA EN GRANO AMARILLA',null), ('COCIDO EL COLONIAL','JAMON COCIDO COLONIAL','NAPOLES'),
      ('BOLSAS ENVASADORA','BOLSAS ENVASADORA',null), ('BOLSAS ENVADADORA','BOLSAS ENVASADORA',null)
    ) as o(h, n, m) where upper(regexp_replace(trim(t.nombre_hoja), '\s+', ' ', 'g')) = o.h limit 1;
    -- se prueban varias formas de encontrar el producto; gana la primera que ya esta en el stock
    c := null;
    if v_nom is not null then c := public._stock_match(v_nom, v_mar); if c is not null then if exists (select 1 from public.stock where insumo_id = c) then k := c; v_via := 'caso especial'; elsif k_sin is null then k_sin := c; via_sin := 'caso especial'; end if; end if; end if;
    if k is null and t.cv_desc is not null then c := public._stock_match(t.cv_desc, t.cv_marca); if c is not null then if exists (select 1 from public.stock where insumo_id = c) then k := c; v_via := 'costos variables'; elsif k_sin is null then k_sin := c; via_sin := 'costos variables'; end if; end if; end if;
    if k is null and nullif(t.map_nombre, '') is not null then c := public._stock_match(t.map_nombre, nullif(t.map_marca, '')); if c is not null then if exists (select 1 from public.stock where insumo_id = c) then k := c; v_via := 'importacion anterior'; elsif k_sin is null then k_sin := c; via_sin := 'importacion anterior'; end if; end if; end if;
    if k is null then c := public._stock_match(t.nombre_hoja, null); if c is not null then if exists (select 1 from public.stock where insumo_id = c) then k := c; v_via := 'mismo nombre'; elsif k_sin is null then k_sin := c; via_sin := 'mismo nombre'; end if; end if; end if;
    if k is null then
      select i.id into c from public.insumos i where not i.es_preparacion and upper(regexp_replace(trim(coalesce(i.marca || ' ', '') || i.nombre), '\s+', ' ', 'g')) = upper(regexp_replace(trim(t.nombre_hoja), '\s+', ' ', 'g')) order by exists (select 1 from public.stock s where s.insumo_id = i.id) desc limit 1;
      if c is not null then if exists (select 1 from public.stock where insumo_id = c) then k := c; v_via := 'marca y nombre'; elsif k_sin is null then k_sin := c; via_sin := 'marca y nombre'; end if; end if;
    end if;
    if k is null then k := k_sin; v_via := via_sin; end if;
    insert into _imp values (t.sub, t.nombre_hoja, t.hay, k, v_via);
  end loop;

  -- registrar y aplicar: se suman los renglones de la planilla que van al mismo producto
  insert into public.import_stock_log (corrida, hoja, nombre_hoja, hay, estado, insumo_id, insumo, antes, ahora, via)
  select v_corrida, x.hoja, x.nombre_hoja, x.hay,
         case when x.insumo_id is null then 'no_encontrado' when s.insumo_id is null then 'sin_stock' else 'ok' end,
         x.insumo_id, trim(coalesce(i.marca || ' ', '') || i.nombre), s.cantidad_actual, null, x.via
    from _imp x left join public.insumos i on i.id = x.insumo_id left join public.stock s on s.insumo_id = x.insumo_id;

  update public.stock s set cantidad_actual = z.total, valorizacion = z.total * coalesce(i.precio_costo_kg, 0), ultima_actualizacion = now()
    from (select insumo_id, sum(hay) as total from _imp where insumo_id is not null group by insumo_id) z, public.insumos i
   where s.insumo_id = z.insumo_id and i.id = s.insumo_id;
  update public.import_stock_log l set ahora = s.cantidad_actual from public.stock s where l.corrida = v_corrida and l.estado = 'ok' and s.insumo_id = l.insumo_id;
end
$$;

-- ===== resultado para revisar =====
select tipo, rubro, nombre, detalle from (
  select 'no_encontrado' as tipo, hoja as rubro, nombre_hoja as nombre, 'planilla dice ' || hay as detalle, 1 as o from public.import_stock_log
   where corrida = (select max(corrida) from public.import_stock_log) and estado = 'no_encontrado'
  union all
  select 'sin_stock', hoja, nombre_hoja, 'es ' || insumo || ' (existe pero no esta en el stock); planilla dice ' || hay, 2 from public.import_stock_log
   where corrida = (select max(corrida) from public.import_stock_log) and estado = 'sin_stock'
  union all
  select 'no_esta_en_la_planilla', i.subcategoria::text, trim(coalesce(i.marca || ' ', '') || i.nombre), 'en la app tiene ' || s.cantidad_actual, 3
    from public.stock s join public.insumos i on i.id = s.insumo_id
   where i.subcategoria::text in ('vermut', 'cerveza y sin alcohol', 'fiambres', 'quesos', 'cocina', 'panes', 'descartables')
     and not exists (select 1 from public.import_stock_log l where l.corrida = (select max(corrida) from public.import_stock_log) and l.insumo_id = s.insumo_id)
  union all
  select 'cambio', l.hoja, l.insumo, 'antes ' || l.antes || ' -> ahora ' || l.ahora || ' (planilla: ' || l.nombre_hoja || ' via ' || l.via || ')', 4 from public.import_stock_log l
   where l.corrida = (select max(corrida) from public.import_stock_log) and l.estado = 'ok' and l.antes is distinct from l.ahora
) r order by o, rubro, nombre;
