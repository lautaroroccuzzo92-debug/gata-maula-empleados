-- Gata Maula: corrige la importacion del stock (0037) y la completa.
--   * 0037 busco primero por el enlace a Costos Variables de la planilla y algunos enlaces estaban cruzados (por ejemplo LUNFA Rosado/Rosso, NUESTRO Bianco/Rosso).
--     Ahora se busca primero por el nombre y por lo que ya estaba cargado en la app, y el enlace queda como ultimo recurso.
--   * vuelve a cargar TODAS las cantidades desde la planilla PPTO (14), asi se arreglan los cruzados
--   * suma al stock lo que la planilla tiene y la app no (preparaciones, Foilex, tapas, Interferencia Tempranillo / Rosso / BIB Catedral, Chocolate blanco, Pan Panchos...)
--   * saca del stock lo que ya no se usa (siguen en Insumos y precios)
--   * al final muestra una lista para revisar: renglones sin encontrar, renglones dudosos y lo que quedo en la app sin estar en la planilla
-- Correr UNA vez en el SQL Editor (despues de 0036 y 0037). Exportar el resultado a CSV y pasarmelo.

create table if not exists public.import_stock_log (
  id bigserial primary key, corrida timestamptz not null default now(), hoja text, nombre_hoja text, hay numeric, estado text,
  insumo_id uuid, insumo text, antes numeric, ahora numeric, via text
);
alter table public.import_stock_log add column if not exists sospechoso boolean;

create or replace function public._stock_match_prep(p_nombre text)
returns uuid language sql stable security definer set search_path = public as $$
  select i.id from public.insumos i where i.es_preparacion and upper(regexp_replace(trim(i.nombre), '\s+', ' ', 'g')) = upper(regexp_replace(trim(p_nombre), '\s+', ' ', 'g')) limit 1
$$;
revoke all on function public._stock_match_prep(text) from public;

do $$
declare t record; k uuid; k_sin uuid; c uuid; via_sin text; v_via text; v_corrida timestamptz := now(); v_nom text; v_mar text; v_prep boolean; v_unidad text;
begin
  -- nombres a corregir y insumos nuevos que pide la planilla
  update public.insumos set nombre = 'BOLSAS ENVASADORA' where subcategoria = 'descartables' and nombre = 'BOLSAS ENVADADORA';
  insert into public.insumos (nombre, marca, grupo, subcategoria, precio_costo_kg, unidad_medida, origen_alta)
    select v.n, null, 'cocina'::grupo_insumo, v.s::subcategoria_insumo, 0, v.u, 'manual'::origen_dato from (values ('FOILEX','descartables','unidad'), ('TAPAS','descartables','unidad')) v(n, s, u)
     where public._insumo_id(v.s, v.n, null) is null;
  insert into public.insumos (nombre, marca, grupo, subcategoria, precio_costo_kg, unidad_medida, origen_alta)
    select v.n, null, 'bebidas'::grupo_insumo, 'vermut'::subcategoria_insumo, 0, 'unidad', 'manual'::origen_dato from (values ('INTERFERENCIA ROSSO'), ('INTERFERENCIA BIB CATEDRAL')) v(n)
     where public._insumo_id('vermut', v.n, null) is null;

  create temporary table if not exists _quitar (insumo_id uuid) on commit drop;
  truncate _quitar;
  insert into _quitar values
('9888634a-9ab2-4b6e-9709-0aad4d9e75fd') /* H2O SABORIZADA LIMON */,
('06e34ec6-b5a7-4542-892a-cc4c4f70f63b') /* H2O SABORIZADA MANZANA */,
('d74eb251-c23a-4751-bb16-7dff2dd63f90') /* H2O SABORIZADA POMELO */,
('c52ad70d-1eff-4ad4-8c11-ca1e73578f3e') /* PEPSI SIN AZUCAR X 500 CC */,
('622931a2-7984-494e-a945-44bbe38e6d68') /* PEPSI X 500 CC */,
('8aea76b9-e364-404f-8225-261fa0b304d6') /* SEVEN UP */,
('86caf43c-b4d4-422b-8b2d-9b143a14fc0e') /* ACEITUNAS VERDES */,
('4f7e3439-7229-41e7-8943-d9a57273102d') /* ESCABECHE DE BERENJENAS */,
('05cf5321-c81f-490f-ae60-6d60151a8dda') /* PAVITA */,
('8e99bd93-5896-4155-9093-0d67a722c4bb') /* CRIOLLO LACTEOS PREMIUM (REEMPLAZO PATEGRAS)3,7 */,
('87b20fad-e6c0-4a03-97e4-2cba97af2a1c') /* MIGUE PROVOLONE */,
('3fc59adb-2bac-4611-b01f-ad3165cc25f9') /* QUESO AZUL BAVARIA */,
('8b660f44-a6c2-4282-9598-d902be7685e3') /* SANTA OLALLA CAMEMBERT100G */,
('8ee8dad0-e743-47d6-b471-829a3b1e5290') /* GRUYERE */,
('5adc4902-3c5c-4a84-b433-98359d77d4ef') /* FAMIGLIA  DELLE VEDOVE ROSSO */,
('d67af82d-d80a-4762-a2e4-4c5765fa6548') /* LA CHARLA ROSSO INTENSO */;
  insert into _quitar select id from public.insumos where (subcategoria::text = 'panes' and nombre in ('Ciabattas', 'Focaccias', 'Panes de leva')) or nombre = 'Sta Olalla Brie de vaca - 2 HORMAS';
  create temporary table if not exists _imp (hoja text, nombre_hoja text, hay numeric, insumo_id uuid, via text) on commit drop;
  truncate _imp;
  for t in select * from (values
    ('vermut', 'AJENJO DRY', 1, null, 'VERMUT AJENJO DRY', 'VERMUT AJENJO DRY', null),
    ('vermut', 'AJENJO ROJO', 2, null, 'VERMUT AJENJO ROJO', 'VERMUT AJENJO ROJO', null),
    ('vermut', 'AJENJO ROSSO', 8, null, 'VERMUT AJENJO ROSSO', 'VERMUT AJENJO ROSSO', null),
    ('vermut', 'AL VOLEO BIANCO', 7, null, 'AL VOLEO VERMUT BIANCO', 'AL VOLEO VERMUT BIANCO', null),
    ('vermut', 'AL VOLEO ROSSO', 6, null, 'AL VOLEO VERMUT ROSSO', 'AL VOLEO VERMUT ROSSO', null),
    ('vermut', 'BELGRANO DE BARRIO', 0, null, 'VERMUT BELGRANO 960 ML', 'VERMUT BELGRANO 960 ML', null),
    ('vermut', 'BELGRANO DE LITORAL', 0, null, 'VERMUT BELGRANO DEL LITORAL 960 ML', 'VERMUT BELGRANO DEL LITORAL 960 ML', null),
    ('vermut', 'BELGRANO SERRANO', 0, null, 'VERMUT BELGRANO SERRANO', 'VERMUT BELGRANO SERRANO', null),
    ('vermut', 'BUM BUM VERMUT', 8, null, 'BUM BUM  "VERMUT ITALIANO"', 'BUM BUM "VERMUT ITALIANO"', null),
    ('vermut', 'CANTIERI BIANCO', 0, null, 'VERMUT CANTIERI BIANCO', 'VERMUT CANTIERI BIANCO', null),
    ('vermut', 'CANTIERI ROSSO', 0, null, 'VERMUT CANTIERI ROSSO', 'VERMUT CANTIERI ROSSO', null),
    ('vermut', 'DESCONFIADO', 0, null, 'DESCONFIADO VERMUT LA SEPTIMA', 'DESCONFIADO VERMUT LA SEPTIMA', null),
    ('vermut', 'DIO FAUSS BLANCO', 0, null, 'DIO FAUSS VERMUT BLANCO', 'DIO FAUSS VERMUT BLANCO', null),
    ('vermut', 'DIO FAUSS ROSADO', 0, null, 'DIO FAUSS VERMUT ROSADO', 'DIO FAUSS VERMUT ROSADO', null),
    ('vermut', 'DIO FAUSS TINTO', 0, null, 'DIO FAUSS VERMUT TINTO', 'DIO FAUSS VERMUT TINTO', null),
    ('vermut', 'FAMIGILIA ROSSO ROBLE', 3, null, 'FAMIGLIA DELLE VEDOVE ROSSO ROBLE', 'FAMIGLIA DELLE VEDOVE ROSSO ROBLE', null),
    ('vermut', 'FAMIGLIA  DELLE VEDOVE ROSSO', 5, null, 'FAMIGLIA DELLE VEDOVE ROSSO', 'FAMIGLIA DELLE VEDOVE ROSSO', null),
    ('vermut', 'FAMIGLIA VEDOVE FRIULIANI', 0, null, 'FAMIGLIA DELLE VEDOVE FRIULIANI', 'FAMIGLIA DELLE VEDOVE FRIULIANI', null),
    ('vermut', 'FASANO', 0, null, 'FASANO ROSSO', 'FASANO ROSSO', null),
    ('vermut', 'FEDERAL', 4, null, 'VERMUT FEDERAL', 'VERMUT FEDERAL', null),
    ('vermut', 'FEDERAL ROSSATO', 12, null, 'VERMUT FEDERAL ROSADO', 'VERMUT FEDERAL ROSADO', null),
    ('vermut', 'GATA MAULA', 9, null, 'VERMUT GATA MAULA', 'VERMUT GATA MAULA', null),
    ('vermut', 'GATA MAULA BARRIL 20LTS', 0, null, 'BARRIL VERMUT GATA MAULA', null, null),
    ('vermut', 'GATA MAULA BARRIL', 0, null, 'BARRIL VERMUT GATA MAULA', null, null),
    ('vermut', 'GILBER JUAN ROSSO', 0, null, 'GILBER JUAN', 'GILBER JUAN', null),
    ('vermut', 'GIOVANONNI BIANCO', 2, null, 'GIOVANNONI SECO750ML', 'GIOVANNONI SECO750ML', null),
    ('vermut', 'GIOVANONNI ROSSO', 1, null, 'GIOVANNONI ROSSO 750ML', 'GIOVANNONI ROSSO 750ML', null),
    ('vermut', 'HIERBA MALA VERMUT', 0, null, 'HIERBA MALA VERMUT', 'HIERBA MALA VERMUT', null),
    ('vermut', 'IL TANO ROSE', 0, null, 'VERMUT IL TANO ROSSO', 'VERMUT IL TANO ROSSO', null),
    ('vermut', 'IL TANO ROSSO', 0, null, 'VERMUT IL TANO ROSSE', 'VERMUT IL TANO ROSSE', null),
    ('vermut', 'INFINITO BIANCO VERMUT', 0, null, 'DESMADRE', 'DESMADRE', null),
    ('vermut', 'INFINITO VERMUT', 0, null, 'VERMUT INFINITO BIANCO', 'VERMUT INFINITO BIANCO', null),
    ('vermut', 'JOLGORIO', 1, null, 'JOLGORIO ROSSO VERMUT', 'JOLGORIO ROSSO VERMUT', null),
    ('vermut', 'LA CHARLA VERMUT BIANCO', 0, null, 'LA CHARLA BIANCO', 'LA CHARLA BIANCO', null),
    ('vermut', 'LA CHARLA VERMUT ROSSO', 0, null, 'LA CHARLA ROSSO', 'LA CHARLA ROSSO', null),
    ('vermut', 'LA CHARLA ROSSO INTENSO', 0, null, 'LA CHARLA ROSSO', 'LA CHARLA ROSSO', null),
    ('vermut', 'LA CHARLA BIB', 0.9, null, 'LA CHARLA BIB ROSSO', null, null),
    ('vermut', 'LA FUERZA BIANCO', 5, null, 'LA FUERZA VERMUT BLANCO', 'LA FUERZA VERMUT BLANCO', null),
    ('vermut', 'LA FUERZA PRIMAVERA', 6, null, 'LA FUERZA VERMUT PRIMAVERA', 'LA FUERZA VERMUT PRIMAVERA', null),
    ('vermut', 'LA FUERZA PROYECTO LOCAL', 1, null, 'LA FUERZA PROYECTO LOCAL', 'LA FUERZA PROYECTO LOCAL', null),
    ('vermut', 'LA FUERZA ROSSO', 11, null, 'LA FUERZA VERMUT ROSSO', 'LA FUERZA VERMUT ROSSO', null),
    ('vermut', 'LA FUERZA SIDERAL', 6, null, 'LA FUERZA VERMUT SIDERAL', 'LA FUERZA VERMUT SIDERAL', null),
    ('vermut', 'LA FUERZA SIDERAL BARRICA UNICA', 6, null, 'LA FUERZA VERMUT SIDERAL BARRICA UNICA', 'LA FUERZA VERMUT SIDERAL BARRICA UNICA', null),
    ('vermut', 'LEONCE ROSADO', 5, null, 'LEONCE ROSE VERMUTH', 'LEONCE ROSE VERMUTH', null),
    ('vermut', 'LEONCE ROSSO', 4, null, 'LEONCE MALBEC VERMUTH', 'LEONCE MALBEC VERMUTH', null),
    ('vermut', 'LOMBRONI BAG IN BOX', 1.6, null, 'LOMBRONI ROSSO BAG IN BOX', 'LOMBRONI ROSSO BAG IN BOX', null),
    ('vermut', 'LOMBRONI BIANCO', 1, null, 'LOMBRONI VERMUT BIANCO', 'LOMBRONI VERMUT BIANCO', null),
    ('vermut', 'LOMBRONI ROSSO', 0, null, 'LOMBRONI VERMUT ROSSO', 'LOMBRONI VERMUT ROSSO', null),
    ('vermut', 'LORENZO TINTO', 2, null, 'LORENZO TINTO BOTELLA', 'LORENZO TINTO BOTELLA', null),
    ('vermut', 'LORENZO BIANCO', 5, null, 'LORENZO BLANCO BOTELLA', 'LORENZO BLANCO BOTELLA', null),
    ('vermut', 'LORENZO TINTO BAG IN BOX', 0, null, 'VERMUT LORENZOS BAG IN BOX', 'VERMUT LORENZOS BAG IN BOX', null),
    ('vermut', 'LUNFA BIANCO', 0, null, 'LUNFA BIANCO', 'LUNFA BIANCO', null),
    ('vermut', 'LUNFA ROSADO', 8, null, 'LUNFA ROSSO', 'LUNFA ROSSO', null),
    ('vermut', 'LUNFA ROSSO', 6, null, 'LUNFA ROSADO', 'LUNFA ROSADO', null),
    ('vermut', 'MALA MARIA FRANCES', 4, null, 'MALA MARIA VERMUT ESTILO FRANCES', 'MALA MARIA VERMUT ESTILO FRANCES', null),
    ('vermut', 'MALA MARIA IL CACCIATORE', 3, null, 'IL CACCIATORE "VERMUT ITALIANO"', 'IL CACCIATORE "VERMUT ITALIANO"', null),
    ('vermut', 'MALA MARIA LE REFUGE', 3, null, 'LE REFUGE "VERMUT FRANCES"', 'LE REFUGE "VERMUT FRANCES"', null),
    ('vermut', 'MALA MARIA TORINO', 10, null, 'MALA MARIA VERMUT ESTILO ITALIANO', 'MALA MARIA VERMUT ESTILO ITALIANO', null),
    ('vermut', 'METODICO VERMUT', 3, null, 'VERMUT METODICO', 'VERMUT METODICO', null),
    ('vermut', 'MIL DEMONIOS', 0, null, 'VERMUT MIL DEMONIOS', 'VERMUT MIL DEMONIOS', null),
    ('vermut', 'NUESTRO ROSSO', 12, null, 'NUESTRO VERMUT BIANCO', 'NUESTRO VERMUT BIANCO', null),
    ('vermut', 'NUESTRO BIANCO', 5, null, 'NUESTRO VERMUT ROSSO', 'NUESTRO VERMUT ROSSO', null),
    ('vermut', 'PICHINCHA', 0, null, 'VERMUT PICHINCHA', 'VERMUT PICHINCHA', null),
    ('vermut', 'PICHINCHA BAG IN BOX', 0, null, 'VERMUT PICHINCHA BAG IN BOX', 'VERMUT PICHINCHA BAG IN BOX', null),
    ('vermut', 'POCIMARIO BIANCO', 0, null, 'VERMUT POCIMARIO BLANCO', 'VERMUT POCIMARIO BLANCO', null),
    ('vermut', 'POCIMARIO ROSADO', 0, null, 'VERMUT POCIMARIO ROSADO', 'VERMUT POCIMARIO ROSADO', null),
    ('vermut', 'PRIMMO BIANCO', 3, null, 'VERMUT PRIMMO BIANCO', 'VERMUT PRIMMO BIANCO', null),
    ('vermut', 'PRIMMO ROSADO', 5, null, 'VERMUT PRIMMO ROSADO', 'VERMUT PRIMMO ROSADO', null),
    ('vermut', 'PRIMMO', 6, null, 'VERMUT PRIMMO ROSSO', 'VERMUT PRIMMO ROSSO', null),
    ('vermut', 'ROCA MADRE', 6, null, 'ROCAMADRE VERMUT', 'ROCAMADRE VERMUT', null),
    ('vermut', 'SABADO VERMUT ROSSO', 0, null, 'SABADO VERMUT', 'SABADO VERMUT', null),
    ('vermut', 'SIN APURO ISABELLA', 2, null, 'SIN APURO VERMUT SYRAH', 'SIN APURO VERMUT SYRAH', null),
    ('vermut', 'SIN APURO SYRAH', 4, null, 'SIN APURO VERMUT SYRAH', 'SIN APURO VERMUT SYRAH', null),
    ('vermut', 'TANDIL PICAPEDRERO ROSSO', 0, null, 'VERMUT PICAPEDRERO', 'VERMUT PICAPEDRERO', null),
    ('vermut', 'TANDIL PIONERA BIANCO', 0, null, 'VERMUT PIONERA', 'VERMUT PIONERA', null),
    ('vermut', 'TRINCHERA BIANCO', 0, null, 'VERMUT TRINCHERA ROSSO', 'VERMUT TRINCHERA ROSSO', null),
    ('vermut', 'TRINCHERA ROSSO', 0, null, 'VERMUT TRINCHERA BLANCO', 'VERMUT TRINCHERA BLANCO', null),
    ('vermut', 'VERMUT 746', 1, null, 'LUI VERMU 746', 'LUI VERMU 746', null),
    ('vermut', 'ABSUELTO ROSSO', 0, null, null, null, null),
    ('vermut', 'SALVA GARCIA', 0, null, 'VERMUT VESTA', 'VERMUT VESTA', null),
    ('vermut', 'VIARAVA', 3, null, 'VIARAVA VERMUT', 'VIARAVA VERMUT', null),
    ('vermut', 'VIARAVA TINTO', 4, null, null, null, null),
    ('vermut', 'PETRICORE', 1, null, 'VERMUT PETRICORE', 'VERMUT PETRICORE', null),
    ('vermut', 'ARRABAL ROJO', 0, null, 'ARRABAL ROJO', 'ARRABAL ROJO', null),
    ('vermut', 'ARRABAL DRY', 0, null, 'ARRABAL BIANCO', 'ARRABAL BIANCO', null),
    ('vermut', 'MENGANO', 6, null, 'VERMUT MENGANO BLANCO', 'VERMUT MENGANO BLANCO', null),
    ('vermut', 'FULANO', 4, null, 'VERMUT FULANO ROJO', 'VERMUT FULANO ROJO', null),
    ('vermut', 'LORENZO TINTO MAGNUM', 2.5, null, null, null, null),
    ('vermut', '746 DORADO', 3, null, null, null, null),
    ('vermut', 'MALARIA + MANIJA', 3, null, null, null, null),
    ('vermut', 'INTERFERENCIA ROSSO', 2, null, null, null, null),
    ('vermut', 'INTERFERECIA TEMPRANILLO', 1, null, null, null, null),
    ('vermut', 'INTERFERENCIA BIB CATEDRAL', 0.4, null, null, null, null),
    ('cerveza y sin alcohol', 'APERITIVO LORENZO TINTO 750', 0, null, 'APERITIVO SIN ALCOHOL LORENZO BAG IN BOX 3L', 'APERITIVO SIN ALCOHOL LORENZO BAG IN BOX 3L', null),
    ('cerveza y sin alcohol', 'APERITIVO LORENZO BIANCO 750', 1, null, 'APERITIVO SIN ALCOHOL TINTO LORENZO BOTELLA 750 CC', 'APERITIVO SIN ALCOHOL TINTO LORENZO BOTELLA 750 CC', null),
    ('cerveza y sin alcohol', 'FERNET SIN ALCOHOL LORENZO', 0, null, null, null, null),
    ('cerveza y sin alcohol', 'CERVERZA FERMENTUM', 21, null, 'FERMENTUM', 'FERMENTUM', null),
    ('cerveza y sin alcohol', 'CERVEZA VIARAVA', 0, null, null, null, null),
    ('cerveza y sin alcohol', 'HOPPY TEA LUPULIS', 8, null, 'HOPPY TEA', 'HOPPY TEA', null),
    ('cerveza y sin alcohol', 'AGUA', 0, null, 'NESTLE  AGUA MINERAL', 'NESTLE AGUA MINERAL', null),
    ('cerveza y sin alcohol', 'H2O NARANJA', 0, null, 'AWAFRUT SABORIZADA 500CC', 'AWAFRUT SABORIZADA 500CC', null),
    ('cerveza y sin alcohol', 'H2O SABORIZADA LIMON', 0, null, 'AWAFRUT SABORIZADA 500CC', 'AWAFRUT SABORIZADA 500CC', null),
    ('cerveza y sin alcohol', 'H2O SABORIZADA MANZANA', 0, null, 'AWAFRUT SABORIZADA 500CC', 'AWAFRUT SABORIZADA 500CC', null),
    ('cerveza y sin alcohol', 'H2O SABORIZADA POMELO', 0, null, 'AWAFRUT SABORIZADA 500CC', 'AWAFRUT SABORIZADA 500CC', null),
    ('cerveza y sin alcohol', 'MIRINDA MANZANA', 0, null, null, null, null),
    ('cerveza y sin alcohol', 'PASO DE LOS TOROS POMELO', 15, null, null, null, null),
    ('cerveza y sin alcohol', 'PASO DE LOS TOROS TONICA', 8, null, 'PASO DE LOS TOROS LATA', 'PASO DE LOS TOROS LATA', null),
    ('cerveza y sin alcohol', 'PEPSI', 5, null, 'PEPSI X 500 CC', 'PEPSI X 500 CC', null),
    ('cerveza y sin alcohol', 'PEPSI BLACK', 3, null, 'PEPSI SIN AZUCAR X 500 CC', 'PEPSI SIN AZUCAR X 500 CC', null),
    ('cerveza y sin alcohol', 'SEVEN UP', 12, null, 'SEVEN UP', 'SEVEN UP', null),
    ('cerveza y sin alcohol', 'SEVEN UP FREE', 0, null, null, null, null),
    ('cerveza y sin alcohol', 'CERVEZA PERONI', 12, null, 'FILLS 90 GR', 'FILLS 90 GR', null),
    ('cerveza y sin alcohol', 'DANAL 800 GR', 0.58, null, 'PAPAS DANAL', 'PAPAS DANAL', null),
    ('fiambres', 'GRASSETTO MORTADELA CON PISTACHOS', 3.28, null, 'CAMPO AUSTRAL MORTADELA CON PISTACHO', 'CAMPO AUSTRAL MORTADELA CON PISTACHO', null),
    ('fiambres', 'GRASSETO LOMO', 0, 'GRASETTO', 'LOMO FINAS HIERBAS HORNEADO', 'LOMO FINAS HIERBAS HORNEADO', 'GRASETTO'),
    ('fiambres', 'COLONIAL LOMO', 1.09, 'CALCHAQUI', 'JAMON COCIDO', 'JAMON COCIDO', 'CALCHAQUI'),
    ('fiambres', 'DON ANTONINO JAMON COCIDO', 0, 'CORDOBA FOOD', 'JAMON COCIDO SOL DEL PILAR', 'JAMON COCIDO SOL DEL PILAR', 'CORDOBA FOOD'),
    ('fiambres', 'EL BUHO JAMON CRUDO', 3.66, 'EL BUHO', 'JAMON CRUDO', 'JAMON CRUDO', 'EL BUHO'),
    ('fiambres', 'EL BUHO LOMO EMBUCHADO', 0.08, 'EL BUHO', 'LOMO EMBUCHADO', 'LOMO EMBUCHADO', 'EL BUHO'),
    ('fiambres', 'GRION PASTRON', 2.76, 'FAMILIA GRION', 'PASTRON AL PIMENTON', 'PASTRON AL PIMENTON', 'FAMILIA GRION'),
    ('fiambres', 'IL NONNO ALPINO SALAME', 2.48, 'IL NONNO ALPINO', 'SALAME', 'SALAME', 'IL NONNO ALPINO'),
    ('fiambres', 'IL NONNO ALPINO JAMON CRUDO', 6.8, 'IL NONNO ALPINO', 'JAMON CRUDO', 'JAMON CRUDO', 'IL NONNO ALPINO'),
    ('fiambres', 'IL NONNOALPINO BONDIOLA', 2.1, 'IL NONNO ALPINO', 'BONDIOLA', 'BONDIOLA', 'IL NONNO ALPINO'),
    ('fiambres', 'COCIDO COLONIAL', 5.34, null, null, null, null),
    ('fiambres', 'LAS DINAS BONDIOLA AHUMADA', 0, 'LAS DINAS', 'BONDIOLA AHUMADA', 'BONDIOLA AHUMADA', 'LAS DINAS'),
    ('fiambres', 'LAS DINAS BRESAOLA', 1.34, 'LAS DINAS', 'BRESAOLA', 'BRESAOLA', 'LAS DINAS'),
    ('fiambres', 'CRUDO KUTSY', 0, null, 'LA PEQUEÑA JAMON CRUDO', 'LA PEQUEÑA JAMON CRUDO', null),
    ('fiambres', 'SALAME MILAN', 0, 'NAPOLES', 'SALAME MILAN', 'SALAME MILAN', 'NAPOLES'),
    ('quesos', 'VITTORIOS STRACCIATELLA', 4.5, 'VITTORIOS', 'STRACCIATELLA', 'STRACCIATELLA', 'VITTORIOS'),
    ('quesos', 'FERMIER CRIOLLO AHUMADO', 1.31, 'FERMIER', 'CRIOLLO AHUMADO', 'CRIOLLO AHUMADO', 'FERMIER'),
    ('quesos', 'FERMIER FONTINA', 3.13, 'FERMIER', 'QUESO FONTINA', 'QUESO FONTINA', 'FERMIER'),
    ('quesos', 'FERMIER GOYA', 3.02, 'FERMIER', 'GOYA', 'GOYA', 'FERMIER'),
    ('quesos', 'FERMIER MORBIER', 2.25, 'FERMIER', 'MORBIER', 'MORBIER', 'FERMIER'),
    ('quesos', 'LA PAULINA TYBO PATEGRAS', 3.05, null, 'TYBO LA PAULINA', 'TYBO LA PAULINA', null),
    ('quesos', 'LA SUERTE LINCOLN', 2.5, 'LA SUERTE', 'LINCOLN', 'LINCOLN', 'LA SUERTE'),
    ('quesos', 'MIGUE PARMESANO', 3.99, 'MIGUE', 'PARMESANO 1/2 HORMA X 3KG', 'PARMESANO 1/2 HORMA X 3KG', 'MIGUE'),
    ('quesos', 'MIGUE  REGGIANITO', 0, 'MIGUE', 'QUESO REGGIANITO', 'QUESO REGGIANITO', 'MIGUE'),
    ('quesos', 'TIO PUJIO HOLANDA', 0, 'NAPOLES', 'HOLANDA TIO PUJIO', 'HOLANDA TIO PUJIO', 'NAPOLES'),
    ('quesos', 'TIO PUJIO SARDO', 0, null, null, null, null),
    ('quesos', 'TIO PUJIO GRUYERE', 0, 'NAPOLES', 'GRUYERE TIO PUJIO', 'GRUYERE TIO PUJIO', 'NAPOLES'),
    ('quesos', 'SANTA OLALLA BRIE', 3.26, 'SANTA OLALLA', 'QUESO BRIE X HORMA DE 800 GR SANATA OLALLA', 'QUESO BRIE X HORMA DE 800 GR SANATA OLALLA', 'SANTA OLALLA'),
    ('quesos', 'SANTA OLALLA CAMEMBERT 50G', 0.56, 'SANTA OLALLA', 'MINI QUESO CAMEMBERT', 'MINI QUESO CAMEMBERT', 'SANTA OLALLA'),
    ('quesos', 'CREMAC SARDO', 0, 'NAPOLES', 'SARDO SOBRERO CREMAC', 'SARDO SOBRERO CREMAC', 'NAPOLES'),
    ('quesos', 'LUCRECIA PROVOLETA', 0.55, 'NAPOLES', 'PROVOLETA LUCRECIA', 'PROVOLETA LUCRECIA', 'NAPOLES'),
    ('quesos', 'LA QUESERA GRUYERITO', 0, null, 'GRUYERE LA QUESERA', 'GRUYERE LA QUESERA', null),
    ('quesos', 'VANGUARD AZUL', 0.61, null, 'QUESO AZUL BAVARIA', 'QUESO AZUL BAVARIA', null),
    ('quesos', 'SANTA OLALLA CROTTIN', 1.03, null, null, null, null),
    ('quesos', 'GRUYERITO LACTOS PREMIUM', 2.8, null, null, null, null),
    ('quesos', 'AZUL TORO AZUL', 0, 'SANTA OLALLA', 'AZUL TORO AZUL', 'AZUL TORO AZUL', 'SANTA OLALLA'),
    ('quesos', 'PATEGRAS lactear', 0, 'COLONIA ORCOVI', 'PATEGRAS X 4KG', 'PATEGRAS X 4KG', 'COLONIA ORCOVI'),
    ('quesos', 'TYBO GOLACTEOS KUTSI', 0, null, 'GOLACTEOS TYBO', 'GOLACTEOS TYBO', null),
    ('quesos', 'CRIOLLO LACTEOS PREMIUM (REEMPLAZO PATEGRAS)3,7', 0, 'COLONIA ORCOVI', 'PATEGRAS X 4KG', 'PATEGRAS X 4KG', 'COLONIA ORCOVI'),
    ('quesos', 'MIGUE PROVOLETA', 0, 'MIGUE', 'PROVOLONE MEDIA HORMA AL VACIO X 1.5KG', 'PROVOLONE MEDIA HORMA AL VACIO X 1.5KG', 'MIGUE'),
    ('quesos', 'brie LA BOHEME', 0, 'NAPOLES', 'BRIE  LA BOHEEM', 'BRIE LA BOHEEM', 'NAPOLES'),
    ('quesos', 'PATEGRAS ORCOVI', 0, null, null, null, null),
    ('quesos', 'HOLANDA LACTEOS PREMIUM', 1.2, null, null, null, null),
    ('quesos', 'TYBO NOALASA', 0, 'WAGGON', 'TYBO NOALSA', 'TYBO NOALSA', 'WAGGON'),
    ('quesos', 'ROMANITO MIGUE', 2.23, null, null, null, null),
    ('cocina', 'ACEITE DE OLIVA', 11.5, null, 'ACEITE DE OLIVA 20LTS', null, null),
    ('cocina', 'ACEITE GIRASOL', 5, null, 'ACEITE DE GIRASOL BARBIERI 10LTS', null, null),
    ('cocina', 'ACEITUNAS RELLENAS', 0, null, 'ACEITUNAS RELLENAS MIX WARA PALLAY 1,5 KG', null, null),
    ('cocina', 'ACEITUNAS VERDES', 0.3, null, 'ACEITUNAS VERDES WARA PALLAY 3KG', null, null),
    ('cocina', 'ACEITUNAS CONDIMENTADAS', 1.13, null, null, null, null),
    ('cocina', 'CHOCOLATE BLANCO', 0.08, null, null, null, null),
    ('cocina', 'REDUCCION ACETO', 0.85, null, null, null, null),
    ('cocina', 'REDUCCION VERMUT', 0.615, null, null, null, null),
    ('cocina', 'ALBAHACA FRESCA', 0, null, null, null, null),
    ('cocina', 'AJI MOLIDO', 0.07, null, 'AJI MOLIDO', null, null),
    ('cocina', 'AJO CAEBZAS', 0.1, null, 'AJO', null, null),
    ('cocina', 'ARROZ', 0.5, null, null, null, null),
    ('cocina', 'AJO POLVO', 0.23, null, 'AJO EN POLVO', null, null),
    ('cocina', 'ALBAHACA SECA', 0.165, null, 'ALBAHACA', null, null),
    ('cocina', 'ALCAUCIL', 0, null, 'CORAZON DE ALCAUCIL WARA PALLAY 3 KG', null, null),
    ('cocina', 'BERENJENA', 0, null, 'BERENJENA', null, null),
    ('cocina', 'CASTAÑAS TOSTADAS', 0.55, null, null, null, null),
    ('cocina', 'CASTAÑAS CAJU', 1, null, 'CASTAÑA DE CAJU', null, null),
    ('cocina', 'ANCO', 1.56, null, null, null, null),
    ('cocina', 'CILANTRO', 0.3, null, null, null, null),
    ('cocina', 'PAPA', 2, null, null, null, null),
    ('cocina', 'CEBOLLA', 0.8, null, 'CEBOLLA', null, null),
    ('cocina', 'CEBOLLA POLVO', 0, null, 'CEBOLLA EN POLVO', null, null),
    ('cocina', 'MAYO CHIMI', 0.2, null, null, null, null),
    ('cocina', 'CHIMICHURRI', 0.125, null, null, null, null),
    ('cocina', 'CORIANDRO', 0.35, null, null, null, null),
    ('cocina', 'CREMA', 0, null, 'CREMA tonadita waggon', null, null),
    ('cocina', 'CURCUMA', 0.32, null, 'CURCUMA', null, null),
    ('cocina', 'ESPARRAGOS', 0, null, 'ESPARRAGOS', null, null),
    ('cocina', 'GARBANZO', 0, null, 'GARBANZOS', null, null),
    ('cocina', 'GELATIN SIN SABOR', 0.335, null, 'GELATINA SIN SABOR', null, null),
    ('cocina', 'HONGOS DESHIDRATADOS', 0.375, null, 'HONGOS DE PINO', null, null),
    ('cocina', 'LECHE (UNIDAD - CAJA)', 2, null, 'LECHE ENTERA LARGA VIDA', null, null),
    ('cocina', 'LENGUA', 0.9, null, 'LENGUA A LA VINAGRETA', null, null),
    ('cocina', 'LIMON', 2.315, null, 'LIMON', null, null),
    ('cocina', 'NUECES', 1.16, null, null, null, null),
    ('cocina', 'MERKEN', 0.225, null, null, null, null),
    ('cocina', 'MANTECA', 2.89, null, 'MANTECA TONADITA', null, null),
    ('cocina', 'MIEL (KG)', 1.3, null, 'MIEL', null, null),
    ('cocina', 'MOSTAZA', 0.89, null, 'MOSTAZA NATURA X3KG', null, null),
    ('cocina', 'MOSTAZA EN GRANOS', 0.2, null, null, null, null),
    ('cocina', 'OREGANO', 0.13, null, 'OREGANO', null, null),
    ('cocina', 'ADEREZO VERDURAS', 0.54, null, null, null, null),
    ('cocina', 'TAPENADE', 0.55, null, null, null, null),
    ('cocina', 'MANTECA SABORIZADA', 0.3, null, null, null, null),
    ('cocina', 'UVAS CON AZUCAR', 0.34, null, null, null, null),
    ('cocina', 'CEBOLLA CARAMELIZDA', 0.53, null, null, null, null),
    ('cocina', 'VERDURAS ASADAS', 0.9, null, null, null, null),
    ('cocina', 'ACEITUNAS NEGRAS', 2.45, null, null, null, null),
    ('cocina', 'PEPINILLOS', 3, null, 'PEPINILLOS WARA PALLAY 3 KG', null, null),
    ('cocina', 'PEPINO', 0, null, 'PEPINO', null, null),
    ('cocina', 'PERAS', 0, null, 'PERAS', null, null),
    ('cocina', 'PEREJIL', 0, null, 'PEREJIL', null, null),
    ('cocina', 'PIMENTON', 0.1, null, 'PIMENTON AHUMADO', null, null),
    ('cocina', 'PIMENTON AHUMADO', 0.385, null, null, null, null),
    ('cocina', 'PIMIENTA NEGRA EN GRANO', 0.235, null, 'PIMIENTA MOLIDA', null, null),
    ('cocina', 'PIMIENTA NEGRA MOLIDA', 0, null, 'PIMIENTA MOLIDA', null, null),
    ('cocina', 'POROTOS PALLARES', 0.5, null, 'ESCABECHE DE POROTOS BLANCO', null, null),
    ('cocina', 'CHAMPI (ESCABECHE)', 3.1, null, 'ESCABECHE DE PORTOBELLOS', null, null),
    ('cocina', 'CHAMPI', 0.44, null, null, null, null),
    ('cocina', 'QUESO CREMA', 3, null, 'QUESO CREMA', null, null),
    ('cocina', 'REMOLACHA', 0, null, 'REMOLACHA', null, null),
    ('cocina', 'ROMERO PAQUETES', 0.01, null, 'ROMERO', null, null),
    ('cocina', 'RUCULA ATADO', 1, null, 'RUCULA ATADO', null, null),
    ('cocina', 'SAL FINA', 0.265, null, 'SAL FINA', null, null),
    ('cocina', 'SAL GRUESA', 0.375, null, 'SAL GRUESA', null, null),
    ('cocina', 'SEMILLAS DE ENEBRO', 0, null, null, null, null),
    ('cocina', 'SEMILLAS SESAMO', 0, null, 'SESAMO BLANCO', null, null),
    ('cocina', 'CHERRY CONFITADOS', 1.29, null, null, null, null),
    ('cocina', 'TOMATE PERITA', 2.37, null, 'TOMATE PERITA', null, null),
    ('cocina', 'PIMINETO AMARILLO', 0.265, null, null, null, null),
    ('cocina', 'PIMIENTO VERDE', 1.12, null, null, null, null),
    ('cocina', 'PIMINETO ROJO', 0.77, null, null, null, null),
    ('cocina', 'PIMIENTOS ASADOS', 0.18, null, null, null, null),
    ('cocina', 'TOMATES CHERRYS', 1, null, 'TOMATES CHERRY', null, null),
    ('cocina', 'TOMATES DESHIDRATADOS', 0.5, null, 'TOMATES DISECADOS', null, null),
    ('cocina', 'TOMILLO', 0.24, null, 'TOMILLO', null, null),
    ('cocina', 'VINAGRE', 3, null, 'VINAGRE DE ALCOHOL MENOYO 10LTS', null, null),
    ('cocina', 'ZUCCINI', 0.83, null, null, null, null),
    ('cocina', 'VERDEO', 0.22, null, null, null, null),
    ('cocina', 'PEREJIL', 0.255, null, null, null, null),
    ('cocina', 'ZANAHORIA', 0.48, null, 'ZANAHORIA', null, null),
    ('cocina', 'RELISH', 2.1, null, null, null, null),
    ('cocina', 'NARANJA', 1.18, null, null, null, null),
    ('cocina', 'POMELO', 2.735, null, null, null, null),
    ('cocina', 'LIMA', 0.52, null, null, null, null),
    ('cocina', 'PERA', 0.235, null, null, null, null),
    ('cocina', 'PESTO', 0.65, null, null, null, null),
    ('cocina', 'CEBOLLA MORADA', 1.385, null, 'CEBOLLA MORADA', null, null),
    ('cocina', 'REPOLLO', 0.64, null, 'REPOLLO', null, null),
    ('cocina', 'MANZANA VERDE', 0, null, 'MANZANA VERDE', null, null),
    ('cocina', 'CREMA PALTA', 0.15, null, null, null, null),
    ('cocina', 'PALTA', 0.075, null, 'PALTA', null, null),
    ('cocina', 'POROTOS SECOS', 0, null, 'POROTOS PALLARES', null, null),
    ('cocina', 'ESCABECHE DE POROTOS', 1.35, null, null, null, null),
    ('cocina', 'ALBONDIGAS', 0, null, null, null, null),
    ('cocina', 'BONDIOLA', 0, null, null, null, null),
    ('cocina', 'PLATO AHUMADO', 1, null, null, null, null),
    ('cocina', 'EXQUISITA', 2, null, null, null, null),
    ('cocina', 'ANTIPASTI', 2, null, null, null, null),
    ('cocina', 'DIP MEDITERRANEO', 1.63, null, null, null, null),
    ('cocina', 'UVAS', 0.325, null, null, null, null),
    ('cocina', 'FRUTILLA', 0.15, null, null, null, null),
    ('cocina', 'PICADA VERMUTERA', 2, null, null, null, null),
    ('cocina', 'CONO FYQ', 3, null, null, null, null),
    ('panes', 'Barras', 0, null, 'BARRA DE MASA MADRE', 'BARRA DE MASA MADRE', null),
    ('panes', 'Ciabatta', 53, null, 'Pan ciabatta masa madre', 'Pan ciabatta masa madre', null),
    ('panes', 'Focaccia ENTERAS', 12, null, 'FOCACCIA ENTERA', 'FOCACCIA ENTERA', null),
    ('panes', 'Foccacias (cortados/sandwichs)', 2, null, 'focaccia CORTADA', 'focaccia CORTADA', null),
    ('panes', 'Levadura Comun', 115, null, 'PAN BAGUETIN LEVADURA', 'PAN BAGUETIN LEVADURA', null),
    ('panes', 'Pan de Molde ENTERO', 4, null, 'PAN DE MOLDE BRIOCHE', null, null),
    ('panes', 'Molde cortados / sandwich{', 6, null, null, null, null),
    ('panes', 'PAN PAPA BURGER', 0, 'WAGGON', 'PAN HAMBURGUESA GOLDEN LISO KALIS', 'PAN HAMBURGUESA GOLDEN LISO KALIS', 'WAGGON'),
    ('panes', 'SCHIACCIATA', 3, null, null, null, null),
    ('panes', 'SCHIACCIATA FRACC.', 11, null, null, null, null),
    ('panes', 'PANZ CIABATTA', 0, 'PANZ', 'PAN CIABATTA', 'PAN CIABATTA', 'PANZ'),
    ('panes', 'PANZ PAN A LA CHAPA', 2, null, 'PAN A LA CHAPA', 'PAN A LA CHAPA', null),
    ('panes', 'PANZ PANCHOS', 51, null, null, null, null),
    ('panes', 'TORTILLAS MACHOTE', 51, 'MACHOTE', 'WRAP GRANDE', 'WRAP GRANDE', 'MACHOTE'),
    ('descartables', 'CAJAS', 200, null, null, null, null),
    ('descartables', 'BOLSAS MADERA', 250, null, null, null, null),
    ('descartables', 'CAJAS REGALO', 14, null, null, null, null),
    ('descartables', 'BOBINA', 1, null, null, null, null),
    ('descartables', 'tapas', 0, null, null, null, null),
    ('descartables', 'FRASCOS PLASTICO', 0, null, null, null, null),
    ('descartables', 'FOILEX', 1, null, null, null, null),
    ('descartables', 'ROLLOS MERCADO PAGO', 14, null, null, null, null),
    ('descartables', 'ROLLOS POSNET', 7, null, null, null, null),
    ('descartables', 'ROLLOS COMANDERAS', 6, null, null, null, null),
    ('descartables', 'BOLSAS ENVASADORA', 0, null, null, null, null),
    ('descartables', 'CINTA SCOTCH', 0, null, null, null, null)
  ) as v(sub, nombre_hoja, hay, cv_marca, cv_desc, map_nombre, map_marca) loop
    k := null; v_via := null; k_sin := null; via_sin := null; c := null; v_nom := null; v_mar := null; v_prep := false;
    -- 1) casos que la planilla nombra distinto o enlazaba mal
    select o.n, o.m, o.p into v_nom, v_mar, v_prep from (values
      ('CERVEZA PERONI','PERONI',null,false), ('PEPSI','PEPSI 354CC',null,false), ('PEPSI BLACK','PEPSI BLACK 354CC',null,false), ('SEVEN UP','SEVEN UP 354CC',null,false),
      ('APERITIVO LORENZO BIANCO 750','APERITIVO SIN ALCOHOL BIANCO LORENZO BOTELLA 750 CC',null,false), ('APERITIVO LORENZO TINTO 750','APERITIVO SIN ALCOHOL TINTO LORENZO BOTELLA 750 CC',null,false),
      ('FERNET SIN ALCOHOL LORENZO','FERNET SIN ALCOHOL LORENZO BOTELLA 750 CC',null,false), ('DANAL 800 GR','PAPAS DANAL',null,false),
      ('SIN APURO ISABELLA','SIN APURO VERMUT ISABELLA',null,false), ('VANGUARD AZUL','QUESO AZUL VANGUARD',null,false),
      ('MIGUE REGGIANITO','QUESO REGGIANITO','MIGUE',false), ('MIGUE  REGGIANITO','QUESO REGGIANITO','MIGUE',false),
      ('LUI VERMU 746','LUI VERMUT 746 ROJO',null,false), ('VERMUT 746','LUI VERMUT 746 ROJO',null,false), ('LUI VERMU 746 DORADO','LUI VERMUT 746 DORADO',null,false), ('746 DORADO','LUI VERMUT 746 DORADO',null,false),
      ('VIARAVA TINTO','VIARAVA VERMUT BARRIO',null,false), ('INTERFERECIA TEMPRANILLO','INTERFERENCIA TEMPRANILLO',null,false),
      ('CONDIMENTO P/CHIMI A','CHIMICHURRI',null,false), ('POROTOS','POROTOS PALLARES',null,false), ('POROTOS SECOS','POROTOS PALLARES',null,false),
      ('PERA','PERAS',null,false), ('PIMINETO ROJO','PIMIENTO ROJO',null,false), ('PIMINETO AMARILLO','PIMIENTO AMARILLO',null,false), ('ZUCCINI','ZUCCHINI',null,false),
      ('MOSTAZA EN GRANOS','MOSTAZA EN GRANO AMARILLA',null,false), ('MOSTAZA EN GRANO','MOSTAZA EN GRANO AMARILLA',null,false),
      ('COCIDO COLONIAL','JAMON COCIDO COLONIAL','NAPOLES',false), ('COCIDO EL COLONIAL','JAMON COCIDO COLONIAL','NAPOLES',false),
      ('PANZ PANCHOS','PAN PANCHO CHICO','PANZ',false), ('BOLSAS ENVADADORA','BOLSAS ENVASADORA',null,false),
      ('CASTAÃ‘AS TOSTADAS','CASTAÃ‘A DE CAJU ASADAS',null,true), ('DIP MEDITERRANEO','DIP MEDITERRANEO',null,true), ('PESTO','PESTO',null,true), ('VERDURAS ASADAS','VERDURAS ASADAS',null,true)
    ) as o(h, n, m, p) where upper(regexp_replace(trim(t.nombre_hoja), '\s+', ' ', 'g')) = o.h limit 1;
    if v_nom is not null then
      if coalesce(v_prep, false) then c := public._stock_match_prep(v_nom); else c := public._stock_match(v_nom, v_mar); end if;
      if c is not null then if exists (select 1 from public.stock where insumo_id = c) then k := c; v_via := 'caso especial'; else k_sin := c; via_sin := 'caso especial'; end if; end if;
    end if;
    -- 2) el mismo nombre (con o sin marca delante)
    if k is null then c := public._stock_match(t.nombre_hoja, null); if c is not null then if exists (select 1 from public.stock where insumo_id = c) then k := c; v_via := 'mismo nombre'; elsif k_sin is null then k_sin := c; via_sin := 'mismo nombre'; end if; end if; end if;
    if k is null then
      select i.id into c from public.insumos i where not i.es_preparacion and upper(regexp_replace(trim(coalesce(i.marca || ' ', '') || i.nombre), '\s+', ' ', 'g')) = upper(regexp_replace(trim(t.nombre_hoja), '\s+', ' ', 'g')) order by exists (select 1 from public.stock s where s.insumo_id = i.id) desc limit 1;
      if c is not null then if exists (select 1 from public.stock where insumo_id = c) then k := c; v_via := 'marca y nombre'; elsif k_sin is null then k_sin := c; via_sin := 'marca y nombre'; end if; end if;
    end if;
    -- 3) como estaba cargado antes en la app
    if k is null and nullif(t.map_nombre, '') is not null then c := public._stock_match(t.map_nombre, nullif(t.map_marca, '')); if c is not null then if exists (select 1 from public.stock where insumo_id = c) then k := c; v_via := 'importacion anterior'; elsif k_sin is null then k_sin := c; via_sin := 'importacion anterior'; end if; end if; end if;
    -- 4) ultimo recurso: el enlace a Costos Variables de la planilla
    if k is null and t.cv_desc is not null then c := public._stock_match(t.cv_desc, t.cv_marca); if c is not null then if exists (select 1 from public.stock where insumo_id = c) then k := c; v_via := 'costos variables'; elsif k_sin is null then k_sin := c; via_sin := 'costos variables'; end if; end if; end if;
    if k is null then k := k_sin; v_via := via_sin; end if;
    insert into _imp values (t.sub, t.nombre_hoja, t.hay, k, v_via);
  end loop;

  -- primero se sacan del stock los que ya no se usan
  delete from public.stock where insumo_id in (select insumo_id from _quitar);
  -- los productos de la planilla que existen como insumo pero todavia no estaban en el stock se suman
  for t in select distinct x.insumo_id, i.subcategoria::text as sub, i.unidad_medida from _imp x join public.insumos i on i.id = x.insumo_id
            where x.insumo_id not in (select insumo_id from _quitar) and not exists (select 1 from public.stock s where s.insumo_id = x.insumo_id) loop
    perform public._stock_alta(t.insumo_id, case when t.unidad_medida = 'unidad' then 'unidad' else 'kg' end);
  end loop;

  insert into public.import_stock_log (corrida, hoja, nombre_hoja, hay, estado, insumo_id, insumo, antes, ahora, via, sospechoso)
  select v_corrida, x.hoja, x.nombre_hoja, x.hay,
         case when x.insumo_id is null then 'no_encontrado' when x.insumo_id in (select insumo_id from _quitar) then 'quitado' else 'ok' end,
         x.insumo_id, trim(coalesce(i.marca || ' ', '') || i.nombre), s.cantidad_actual, null, x.via,
         x.via in ('importacion anterior', 'costos variables') and public.similitud_palabras(public.normalizar_texto(x.nombre_hoja), public.normalizar_texto(coalesce(i.marca || ' ', '') || i.nombre)) < 0.34
    from _imp x left join public.insumos i on i.id = x.insumo_id left join public.stock s on s.insumo_id = x.insumo_id;

  update public.stock s set cantidad_actual = z.total, valorizacion = z.total * coalesce(i.precio_costo_kg, 0), ultima_actualizacion = now()
    from (select insumo_id, sum(hay) as total from _imp where insumo_id is not null and insumo_id not in (select insumo_id from _quitar) group by insumo_id) z, public.insumos i
   where s.insumo_id = z.insumo_id and i.id = s.insumo_id;
  update public.import_stock_log l set ahora = s.cantidad_actual from public.stock s where l.corrida = v_corrida and l.estado = 'ok' and s.insumo_id = l.insumo_id;
end
$$;

-- ===== resultado para revisar =====
select tipo, rubro, nombre, detalle from (
  select 'no_encontrado' as tipo, hoja as rubro, nombre_hoja as nombre, 'planilla dice ' || hay as detalle, 1 as o from public.import_stock_log
   where corrida = (select max(corrida) from public.import_stock_log) and estado = 'no_encontrado'
  union all
  select 'dudoso', hoja, nombre_hoja, 'se cargo en ' || insumo || ' (' || via || '); planilla dice ' || hay, 2 from public.import_stock_log
   where corrida = (select max(corrida) from public.import_stock_log) and estado = 'ok' and sospechoso
  union all
  select 'en_la_app_no_en_la_planilla', i.subcategoria::text, trim(coalesce(i.marca || ' ', '') || i.nombre), 'en la app tiene ' || s.cantidad_actual, 3
    from public.stock s join public.insumos i on i.id = s.insumo_id
   where i.subcategoria::text in ('vermut', 'cerveza y sin alcohol', 'fiambres', 'quesos', 'cocina', 'panes', 'descartables')
     and not exists (select 1 from public.import_stock_log l where l.corrida = (select max(corrida) from public.import_stock_log) and l.insumo_id = s.insumo_id)
  union all
  select 'cambio', l.hoja, l.insumo, 'antes ' || l.antes || ' -> ahora ' || l.ahora || ' (planilla: ' || l.nombre_hoja || ')', 4 from public.import_stock_log l
   where l.corrida = (select max(corrida) from public.import_stock_log) and l.estado = 'ok' and l.antes is distinct from l.ahora
) r order by o, rubro, nombre;
