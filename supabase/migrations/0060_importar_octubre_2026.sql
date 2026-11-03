-- Gata Maula: importa los egresos de octubre 2026 de tu planilla EERR OCTUBRE sin duplicar lo que ya estaba cargado desde la app.
--   1) borra las copias repetidas de la factura de Papu Cuisine del 21/10 ($157.400 estaba 3 veces; queda la pagada)
--   2) corrige el concepto de los gastos de la app que no coincidian con tu planilla (Pepsi, DCh, Fermentum, Soderia, Waggon, Libreria, Personal)
--   3) carga los movimientos de tu planilla que la app no tenia (se dejan afuera los que ya estaban con otro nombre o dividido por concepto:
--      Lorenzos/Fermentum del 22/10 y 30/10, Supermercado del 21/10 y Green City del 2/10)
--   4) los pagos de deuda cargados cruzan con el calendario: si coinciden con un pago pendiente (mismo proveedor y monto), se marca pagado
-- Es seguro correrlo mas de una vez (lo importado se reemplaza). No crea pagos pendientes en el calendario.
-- Correr UNA vez en el SQL Editor y revisar el resultado final.

-- ===== ayuda: cruzar un pago con el calendario aunque venga de una importacion =====
create or replace function public._calendario_conciliar(p_egreso_id uuid, p_forzar boolean)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  e record; v_nombre text; v_ids uuid[]; v_tot numeric; v_pct numeric; v_nro text;
  v_dto boolean; c record; v_desc numeric; v_conc text;
begin
  select * into e from public.ingresos_egresos where id = p_egreso_id;
  if not found or e.forma not in ('egreso_efectivo', 'egreso_banco') or (not p_forzar and (e.origen <> 'manual' or e.lote_importacion is not null))
     or e.proveedor_id is null or coalesce(e.monto, 0) <= 0 or coalesce(e.observaciones, '') like 'Pago de % del %' then
    return null;
  end if;
  select nombre into v_nombre from public.proveedores where id = e.proveedor_id;
  if v_nombre is null then return null; end if;

  with cand as (
    select cp.*, coalesce(pr.descuento_efectivo_pct, 0) as pct
      from public.calendario_pagos cp left join public.proveedores pr on pr.id = cp.proveedor_id
     where not cp.pagado and cp.total > 0
       and (cp.fecha_factura is null or e.fecha >= cp.fecha_factura)
       and cp.egreso_id is distinct from e.id
       and (cp.proveedor_id = e.proveedor_id
            or public.similitud_palabras(public.normalizar_texto(cp.proveedor_texto), public.normalizar_texto(v_nombre)) >= 0.5)
  )
  select z.ids, z.tot, z.pct, z.nro into v_ids, v_tot, v_pct, v_nro from (
    select array[id] as ids, total as tot, pct, nro_factura as nro, 1 as pri, fecha_vencimiento as fv from cand
    union all
    select array_agg(id order by fecha_vencimiento), sum(total), max(pct), nro_factura, 2, min(fecha_vencimiento)
      from cand where nro_factura is not null group by nro_factura
  ) z
  where abs(z.tot - e.monto) < 1
     or (e.forma = 'egreso_efectivo' and z.pct > 0 and abs(round(z.tot * (1 - z.pct / 100), 2) - e.monto) < 1)
  order by z.pri, z.fv limit 1;

  if v_ids is null then return null; end if;
  v_dto := e.forma = 'egreso_efectivo' and v_pct > 0 and abs(v_tot - e.monto) >= 1;

  perform set_config('app.sin_conciliar', '1', true);
  for c in select * from public.calendario_pagos where id = any(v_ids) order by fecha_vencimiento loop
    update public.calendario_pagos set pagado = true, fecha_pago = e.fecha,
        medio_pago = case when e.forma = 'egreso_banco' then 'banco' else 'efectivo' end,
        nota = trim(coalesce(nota || ' · ', '') || 'Se marco pagado solo: pago anotado el ' || to_char(e.fecha, 'DD/MM') || case when v_dto then ' (con ' || v_pct || '% de descuento por efectivo)' else '' end)
      where id = c.id;
    if c.egreso_id is not null then
      update public.ingresos_egresos set estado_pago = 'pagado', fecha_pago = e.fecha where id = c.egreso_id;
      if v_dto then
        v_desc := round(c.total * v_pct / 100, 2);
        select concepto into v_conc from public.ingresos_egresos where id = c.egreso_id;
        insert into public.ingresos_egresos (fecha, proveedor_id, concepto, factura_numero, monto, forma, estado_pago, medio_pago, fecha_pago, origen, usuario_id, observaciones, lote_importacion, nc_de_factura)
          values (e.fecha, c.proveedor_id, v_conc, null, -v_desc, 'deuda_proveedores', 'pagado'::estado_pago_tipo, 'descuento por pago en efectivo', e.fecha,
                  'manual', e.usuario_id, 'Descuento por pago en efectivo (' || v_pct || '%) factura ' || coalesce(c.nro_factura, 's/n'), to_char(e.fecha, 'YYYY-MM'), c.nro_factura);
      end if;
    end if;
  end loop;
  return v_ids[1];
end;
$$;
revoke all on function public._calendario_conciliar(uuid, boolean) from public;

-- ===== 1) Papu Cuisine: tres copias de la misma factura del 21/10 =====
do $$
declare v_n int;
begin
  create temp table _papu on commit drop as
    select e.id from public.ingresos_egresos e join public.proveedores p on p.id = e.proveedor_id
     where e.fecha = '2026-10-21' and upper(p.nombre) like 'PAPU%' and e.estado_pago = 'pendiente' and e.forma = 'deuda_proveedores'
       and ((e.monto = 155400 and e.origen = 'factura')
         or (e.monto = 2000 and e.origen = 'factura' and e.concepto = 'GASTOS DIARIOS NO CLASIFICADOS')
         or (e.monto = 157400 and e.origen = 'manual' and e.factura_numero = '010573'));
  select count(*) into v_n from _papu;
  delete from public.calendario_pagos where egreso_id in (select id from _papu);
  delete from public.ingresos_egresos where id in (select id from _papu);
  raise notice 'Papu: se borraron % movimientos repetidos (tienen que ser 3)', v_n;
end
$$;

-- ===== 2) conceptos de la app que no coincidian con tu planilla =====
update public.ingresos_egresos e set concepto = c.nuevo
  from public.proveedores p, (values
    ('2026-10-22'::date, 'PEPSI%', 40476.53::numeric, 'GASTOS DIARIOS NO CLASIFICADOS', 'BEBIDA SIN ALCOHOL'),
    ('2026-10-23', 'DCH%', 87774.62, 'GASTOS DIARIOS NO CLASIFICADOS', 'BEBIDA CON ALCOHOL'),
    ('2026-10-23', 'FERMENTUM FABER%', 56944, 'GASTOS DIARIOS NO CLASIFICADOS', 'BEBIDA SIN ALCOHOL'),
    ('2026-10-30', 'FERMENTUM FABER%', 59208, 'GASTOS DIARIOS NO CLASIFICADOS', 'VERMUT'),
    ('2026-10-27', 'SODERIA DEL CIELO%', 84000, 'Insum', 'INSUMOS BARRA'),
    ('2026-10-27', 'WAGGON%', 33554.86, 'FIAMBRES Y QUESOS', 'COCINA'),
    ('2026-10-28', 'PERSONAL%', 34150, 'Cocina', 'PERSONAL COCINA'),
    ('2026-10-31', 'LIBRERIA%', 23200, 'Libreria', 'IMPRENTA, LIBRERÍA'),
    ('2026-10-31', 'LIBRERIA%', 45000, 'Libreria', 'IMPRENTA, LIBRERÍA')
  ) as c(fecha, prov, monto, viejo, nuevo)
 where p.id = e.proveedor_id and e.fecha = c.fecha and upper(p.nombre) like c.prov and abs(e.monto - c.monto) < 0.01 and e.concepto = c.viejo;

-- ===== 3) importar lo que la app no tenia =====
do $$
begin
  create temp table _imp (fecha text, prov text, conc text, fac text, monto numeric, forma text) on commit drop;
  insert into _imp values
    ('2026-10-01', 'FLETE', 'FLETE', '', 6000, 'egreso_efectivo'),
    ('2026-10-01', 'HAEDO', 'FIAMBRES Y QUESOS', '126686', 95762.15, 'deuda_proveedores'),
    ('2026-10-01', 'JUAN PABLO', 'FIAMBRES Y QUESOS', '1266', 151632.01, 'deuda_proveedores'),
    ('2026-10-01', 'LIBRERIA', 'IMPRENTA, LIBRERÍA', '', 4800, 'egreso_efectivo'),
    ('2026-10-01', 'PAPU CUISINE', 'PAGO DEUDA PROVEEDORES', '', 260200, 'egreso_efectivo'),
    ('2026-10-01', 'PERSONAL', 'PERSONAL COCINA', '', 39300, 'egreso_efectivo'),
    ('2026-10-01', 'PERSONAL', 'PERSONAL SALON', '', 20500, 'egreso_efectivo'),
    ('2026-10-01', 'PZ LIMPIEZA', 'INSUMOS DE LIMPIEZA', '18016', 138762.9, 'deuda_proveedores'),
    ('2026-10-01', 'SODERIA DEL CIELO', 'INSUMOS BARRA', '', 149500, 'egreso_efectivo'),
    ('2026-10-01', 'TWEETY VERDULERIA', 'VERDULERIA', '', 7637, 'egreso_efectivo'),
    ('2026-10-01', 'WAGGON', 'COCINA', '80981', 807.3, 'deuda_proveedores'),
    ('2026-10-02', 'DESPENSA', 'COCINA', '', 3000, 'egreso_efectivo'),
    ('2026-10-02', 'El BUHO', 'PAGO DEUDA PROVEEDORES', '', 301458, 'egreso_efectivo'),
    ('2026-10-02', 'El BUHO', 'FIAMBRES Y QUESOS', '', 346445, 'egreso_efectivo'),
    ('2026-10-02', 'GATA MAULA COMIDA PERSONAL', 'COMIDA DE PERSONAL', '', 45040, 'egreso_efectivo'),
    ('2026-10-02', 'HIELO CBA', 'INSUMOS BARRA', '', 16000, 'egreso_efectivo'),
    ('2026-10-02', 'NAPOLES', 'COCINA', '', 47001, 'egreso_banco'),
    ('2026-10-02', 'NAPOLES', 'FIAMBRES Y QUESOS', '', 47785, 'egreso_banco'),
    ('2026-10-02', 'PERSONAL', 'PERSONAL COCINA', '', 39200, 'egreso_efectivo'),
    ('2026-10-02', 'SANTOS CARNICERIA', 'COCINA', '', 51000, 'egreso_banco'),
    ('2026-10-02', 'SODERIA DEL CIELO', 'INSUMOS BARRA', '', 36000, 'egreso_efectivo'),
    ('2026-10-02', 'VIARAVA VERMUT', 'VERMUT', '', 121800, 'deuda_proveedores'),
    ('2026-10-02', 'VIDRIOS', 'MANTENIMIENTO LIMPIEZA', '', 14000, 'egreso_efectivo'),
    ('2026-10-02', 'WARA PALLAY - SABORES GOURMET', 'COCINA', '4641', 115900, 'deuda_proveedores'),
    ('2026-10-02', 'ZECOR', 'VERDULERIA', '5', 112500, 'deuda_proveedores'),
    ('2026-10-03', 'HIELO CBA', 'INSUMOS BARRA', '', 24000, 'egreso_efectivo'),
    ('2026-10-03', 'LORENZOS', 'BEBIDA SIN ALCOHOL', '', 56944, 'deuda_proveedores'),
    ('2026-10-03', 'PERSONAL', 'PERSONAL COCINA', '', 35900, 'egreso_efectivo'),
    ('2026-10-03', 'SUPERMERCADO', 'INSUMOS DE MANTENIMIENTO', '', 6350, 'egreso_efectivo'),
    ('2026-10-04', 'PERSONAL', 'PERSONAL COCINA', '', 32000, 'egreso_efectivo'),
    ('2026-10-05', 'ALQUERIA', 'PAGO DEUDA PROVEEDORES', '', 267744.46, 'egreso_banco'),
    ('2026-10-05', 'AMERICAN WINE GRUP', 'PAGO DEUDA PROVEEDORES', '', 238200.02, 'egreso_banco'),
    ('2026-10-05', 'AMERICAN WINE GRUP', 'PAGO DEUDA PROVEEDORES', '', 119400.02, 'egreso_banco'),
    ('2026-10-05', 'DILCOR', 'PAGO DEUDA PROVEEDORES', '', 198015.05, 'egreso_banco'),
    ('2026-10-05', 'ELECTRICISTA', 'MANO DE OBRA MANTENIMIENTO', '', 75000, 'egreso_efectivo'),
    ('2026-10-05', 'JUAN PABLO', 'PAGO DEUDA PROVEEDORES', '', 70012.56, 'egreso_banco'),
    ('2026-10-05', 'JUAN PABLO', 'PAGO DEUDA PROVEEDORES', '', 71530.5, 'egreso_banco'),
    ('2026-10-05', 'JUAN PABLO', 'PAGO DEUDA PROVEEDORES', '', 67392, 'egreso_banco'),
    ('2026-10-05', 'LORENZOS', 'BEBIDA SIN ALCOHOL', '10999', 56944, 'deuda_proveedores'),
    ('2026-10-05', 'PZ LIMPIEZA', 'PAGO DEUDA PROVEEDORES', '', 126479.29, 'egreso_banco'),
    ('2026-10-05', 'WAGGON', 'PAGO DEUDA PROVEEDORES', '', 1313.2, 'egreso_banco'),
    ('2026-10-05', 'WAGGON', 'PAGO DEUDA PROVEEDORES', '', 34915.06, 'egreso_banco'),
    ('2026-10-05', 'WAGGON', 'PAGO DEUDA PROVEEDORES', '', 135987.55, 'egreso_banco'),
    ('2026-10-06', 'CARNAVE', 'COCINA', '', 47282.48, 'egreso_efectivo'),
    ('2026-10-06', 'FERMENTUM JUAN PABLO', 'BEBIDA CON ALCOHOL', '1404', 86848, 'deuda_proveedores'),
    ('2026-10-06', 'JUAN PABLO', 'FIAMBRES Y QUESOS', '1281', 109512, 'deuda_proveedores'),
    ('2026-10-06', 'PAPU CUISINE', 'PAN', '', 92900, 'deuda_proveedores'),
    ('2026-10-06', 'PERSONAL', 'PERSONAL COCINA', '', 32500, 'egreso_efectivo'),
    ('2026-10-06', 'SODERIA DEL CIELO', 'INSUMOS BARRA', '', 99500, 'egreso_efectivo'),
    ('2026-10-06', 'SUPERMERCADO', 'COCINA', '', 4269.98, 'egreso_efectivo'),
    ('2026-10-06', 'SUPERMERCADO', 'INSUMOS DE LIMPIEZA', '', 1649.99, 'egreso_efectivo'),
    ('2026-10-06', 'TORK', 'DESCARTABLES', '564', 104026.85, 'deuda_proveedores'),
    ('2026-10-06', 'TWEETY VERDULERIA', 'VERDULERIA', '', 1900, 'egreso_efectivo'),
    ('2026-10-06', 'WAGGON', 'COCINA', '81244', 44271.99, 'deuda_proveedores'),
    ('2026-10-06', 'WAGGON', 'COMIDA DE PERSONAL', '81248', 13394.25, 'deuda_proveedores'),
    ('2026-10-06', 'ZECOR', 'PAGO DEUDA PROVEEDORES', '', 251000, 'egreso_efectivo'),
    ('2026-10-06', 'ZECOR', 'VERDULERIA', '', 186800, 'deuda_proveedores'),
    ('2026-10-06', 'ZECOR', 'COMIDA DE PERSONAL', '', 9000, 'deuda_proveedores'),
    ('2026-10-07', '', 'CARGAS SOCIALES - APORTES Y CONTRIB.', '', 174103, 'egreso_banco'),
    ('2026-10-07', 'ALQUERIA', 'FIAMBRES Y QUESOS', '6389', 328718.59, 'deuda_proveedores'),
    ('2026-10-07', 'DDF MARKET', 'COCINA', '', 128000, 'egreso_efectivo'),
    ('2026-10-07', 'HIELO CBA', 'INSUMOS BARRA', '', 24000, 'egreso_efectivo'),
    ('2026-10-07', 'IL NONNO ALPINO', 'FIAMBRES Y QUESOS', '180', 146192.32, 'deuda_proveedores'),
    ('2026-10-07', 'LA FUERZA', 'VERMUT', '2041', 531004.06, 'egreso_banco'),
    ('2026-10-07', 'LA FUERZA', 'VERMUT', '2041', 442376.03, 'deuda_proveedores'),
    ('2026-10-07', 'LIBRERIA', 'IMPRENTA, LIBRERÍA', '', 6000, 'egreso_efectivo'),
    ('2026-10-07', 'PERSONAL', 'PERSONAL COCINA', '', 35000, 'egreso_efectivo'),
    ('2026-10-07', 'TWEETY VERDULERIA', 'VERDULERIA', '', 1566, 'egreso_efectivo'),
    ('2026-10-08', 'CAROSSIO VAIROLATTI', 'COMISIONISTA', '', 39583.6, 'egreso_efectivo'),
    ('2026-10-08', 'EASY', 'INSUMOS DE MANTENIMIENTO', '', 30451.92, 'egreso_efectivo'),
    ('2026-10-08', 'LA FUERZA', 'VERMUT', '2041', 442376.03, 'deuda_proveedores'),
    ('2026-10-08', 'LIBRERIA', 'IMPRENTA, LIBRERÍA', '', 3500, 'egreso_efectivo'),
    ('2026-10-08', 'LORENZOS', 'BEBIDA SIN ALCOHOL', '11044', 26904, 'deuda_proveedores'),
    ('2026-10-08', 'NAPOLES', 'FIAMBRES Y QUESOS', '', 151108, 'egreso_efectivo'),
    ('2026-10-08', 'PAPU CUISINE', 'PAN', '', 110000, 'deuda_proveedores'),
    ('2026-10-08', 'PAPU CUISINE', 'PAGO DEUDA PROVEEDORES', '', 263000, 'egreso_efectivo'),
    ('2026-10-08', 'PEPSI', 'BEBIDA SIN ALCOHOL', '', 61123.04, 'egreso_efectivo'),
    ('2026-10-08', 'PERSONAL', 'PERSONAL COCINA', '', 35700, 'egreso_efectivo'),
    ('2026-10-08', 'PZ LIMPIEZA', 'INSUMOS DE LIMPIEZA', '389', 102052.4, 'deuda_proveedores'),
    ('2026-10-08', 'SODERIA DEL CIELO', 'INSUMOS BARRA', '', 54000, 'egreso_efectivo'),
    ('2026-10-08', 'SUPERMERCADO', 'COCINA', '', 5699.99, 'egreso_efectivo'),
    ('2026-10-08', 'VITTORIOS', 'FIAMBRES Y QUESOS', '11443', 92971.44, 'deuda_proveedores'),
    ('2026-10-09', 'CARNAVE', 'COCINA', '', 35204.89, 'egreso_efectivo'),
    ('2026-10-09', 'LIBRERIA', 'IMPRENTA, LIBRERÍA', '', 46500, 'egreso_efectivo'),
    ('2026-10-09', 'OPEN 365', 'VERMUT', '2580', 412842.01, 'deuda_proveedores'),
    ('2026-10-09', 'PERSONAL', 'PERSONAL COCINA', '', 37600, 'egreso_efectivo'),
    ('2026-10-09', 'ZECOR', 'VERDULERIA', '', 21200, 'deuda_proveedores'),
    ('2026-10-10', 'HIELO CBA', 'INSUMOS BARRA', '', 16000, 'egreso_efectivo'),
    ('2026-10-10', 'PERSONAL', 'PERSONAL COCINA', '', 40100, 'egreso_efectivo'),
    ('2026-10-10', 'SUPERMERCADO', 'COCINA', '', 2269.99, 'egreso_efectivo'),
    ('2026-10-11', 'PERSONAL', 'PERSONAL COCINA', '', 34900, 'egreso_efectivo'),
    ('2026-10-13', '', 'CARGAS SOCIALES - APORTES Y CONTRIB.', '', 546953.5, 'egreso_banco'),
    ('2026-10-13', 'ALQUERIA', 'PAGO DEUDA PROVEEDORES', '', 208086.24, 'egreso_banco'),
    ('2026-10-13', 'AMERICAN WINE GRUP', 'VERMUT', '9144', 146140.02, 'deuda_proveedores'),
    ('2026-10-13', 'CARNAVE', 'COCINA', '', 53963.7, 'egreso_efectivo'),
    ('2026-10-13', 'HAEDO', 'PAGO DEUDA PROVEEDORES', '', 95762.15, 'egreso_banco'),
    ('2026-10-13', 'IL NONNO ALPINO', 'PAGO DEUDA PROVEEDORES', '', 78721.87, 'egreso_banco'),
    ('2026-10-13', 'IVA', 'IVA', '', 320546.52, 'egreso_banco'),
    ('2026-10-13', 'JUAN PABLO', 'FIAMBRES Y QUESOS', '1298', 116900.88, 'deuda_proveedores'),
    ('2026-10-13', 'JUAN PABLO', 'PAGO DEUDA PROVEEDORES', '', 175993.15, 'egreso_banco'),
    ('2026-10-13', 'LAS COPLAS', 'PAGO DEUDA PROVEEDORES', '', 72000, 'egreso_banco'),
    ('2026-10-13', 'PERSONAL', 'PERSONAL COCINA', '', 29600, 'egreso_efectivo'),
    ('2026-10-13', 'PRIMMO VERMUT', 'PAGO DEUDA PROVEEDORES', '', 112320, 'egreso_banco'),
    ('2026-10-13', 'REDES SOCIALES', 'REDES', '', 500000, 'egreso_efectivo'),
    ('2026-10-13', 'SUPERMERCADO', 'COCINA', '', 5699.99, 'egreso_efectivo'),
    ('2026-10-13', 'TWEETY VERDULERIA', 'VERDULERIA', '', 1450, 'egreso_efectivo'),
    ('2026-10-13', 'VITIS SAS', 'VERMUT', '11621', 277799.98, 'deuda_proveedores'),
    ('2026-10-13', 'WAGGON', 'COCINA', '85580', 87198.35, 'deuda_proveedores'),
    ('2026-10-13', 'WAGGON', 'PAGO DEUDA PROVEEDORES', '', 96196.51, 'egreso_banco'),
    ('2026-10-13', 'WAGGON', 'COMIDA DE PERSONAL', '85584', 10102.6, 'deuda_proveedores'),
    ('2026-10-13', 'WAGGON', 'PAGO DEUDA PROVEEDORES', '', 807.3, 'egreso_banco'),
    ('2026-10-13', 'WARA PALLAY - SABORES GOURMET', 'PAGO DEUDA PROVEEDORES', '', 115900, 'egreso_banco'),
    ('2026-10-13', 'ZECOR', 'VERDULERIA', '', 115500, 'deuda_proveedores'),
    ('2026-10-13', 'ZECOR', 'COMIDA DE PERSONAL', '', 17750, 'deuda_proveedores'),
    ('2026-10-14', 'ALQUERIA', 'FIAMBRES Y QUESOS', '6464', 69104.32, 'deuda_proveedores'),
    ('2026-10-14', 'AROMAS', 'DESCARTABLES', '', 2000, 'egreso_efectivo'),
    ('2026-10-14', 'FAZZIO', 'COMIDA DE PERSONAL', '', 52211.25, 'egreso_efectivo'),
    ('2026-10-14', 'FAZZIO', 'COCINA', '', 31326.75, 'egreso_efectivo'),
    ('2026-10-14', 'IL NONNO ALPINO', 'FIAMBRES Y QUESOS', '205', 114397.32, 'deuda_proveedores'),
    ('2026-10-14', 'NUESTRO VERMUT', 'VERMUT', '1', 171000, 'deuda_proveedores'),
    ('2026-10-14', 'PAPU CUISINE', 'PAN', '', 108800, 'deuda_proveedores'),
    ('2026-10-14', 'PERSONAL', 'PERSONAL COCINA', '', 35200, 'egreso_efectivo'),
    ('2026-10-14', 'SUPERMERCADO', 'COCINA', '', 9069.96, 'egreso_efectivo'),
    ('2026-10-14', 'TEHILER', 'DESCARTABLES', '', 31000, 'egreso_efectivo'),
    ('2026-10-14', 'TWEETY VERDULERIA', 'COCINA', '', 46537, 'egreso_efectivo'),
    ('2026-10-15', 'DESPENSA', 'INSUMOS DE LIMPIEZA', '', 1800, 'egreso_efectivo'),
    ('2026-10-15', 'HIELO CBA', 'INSUMOS BARRA', '', 40000, 'egreso_efectivo'),
    ('2026-10-15', 'JUAN PABLO', 'FIAMBRES Y QUESOS', '1304', 171288.01, 'deuda_proveedores'),
    ('2026-10-15', 'PAPU CUISINE', 'PAGO DEUDA PROVEEDORES', '', 182600, 'egreso_efectivo'),
    ('2026-10-15', 'PERSONAL', 'PERSONAL COCINA', '', 35690, 'egreso_efectivo'),
    ('2026-10-15', 'PZ LIMPIEZA', 'INSUMOS DE LIMPIEZA', '', 101721.64, 'deuda_proveedores'),
    ('2026-10-15', 'SERVICIO TECNICO ELECTRODOMESTICO', 'MANO DE OBRA MANTENIMIENTO', '', 30000, 'egreso_efectivo'),
    ('2026-10-15', 'SISTEMA POSBERRY', 'ABONO SISTEMA', '', 70000, 'egreso_banco'),
    ('2026-10-15', 'SODERIA DEL CIELO', 'INSUMOS BARRA', '', 110000, 'egreso_efectivo'),
    ('2026-10-15', 'ZECOR', 'VERDULERIA', '', 65900, 'deuda_proveedores'),
    ('2026-10-16', 'BAZAR', 'DESCARTABLES', '', 5800, 'egreso_efectivo'),
    ('2026-10-16', 'BAZAR', 'DECORACION', '', 142000, 'egreso_banco'),
    ('2026-10-16', 'CELESTE', 'COCINA', '', 28500, 'egreso_efectivo'),
    ('2026-10-16', 'ELEWAIT', 'INSUMOS DE MANTENIMIENTO', '', 5200, 'egreso_efectivo'),
    ('2026-10-16', 'FARMACIA', 'DESCARTABLES', '', 3515.6, 'egreso_efectivo'),
    ('2026-10-16', 'FLETE', 'FLETE', '', 40000, 'egreso_efectivo'),
    ('2026-10-16', 'LIBRERIA', 'IMPRENTA, LIBRERÍA', '', 11500, 'egreso_efectivo'),
    ('2026-10-16', 'LIBRERIA', 'IMPRENTA, LIBRERÍA', '', 3000, 'egreso_efectivo'),
    ('2026-10-16', 'NAPOLES', 'FIAMBRES Y QUESOS', '', 177680, 'egreso_banco'),
    ('2026-10-16', 'PERSONAL', 'PERSONAL COCINA', '', 41200, 'egreso_efectivo'),
    ('2026-10-17', 'PERSONAL', 'PERSONAL COCINA', '', 38300, 'egreso_efectivo'),
    ('2026-10-19', 'ALQUERIA', 'PAGO DEUDA PROVEEDORES', '', 291805.75, 'egreso_banco'),
    ('2026-10-19', 'EPEC', 'PAGO DEUDA PROVEEDORES', '', 806055.5, 'egreso_banco'),
    ('2026-10-19', 'FLETE', 'FLETE', '', 35000, 'egreso_efectivo'),
    ('2026-10-19', 'IL NONNO ALPINO', 'PAGO DEUDA PROVEEDORES', '', 146192.32, 'egreso_banco'),
    ('2026-10-19', 'JUAN PABLO', 'PAGO DEUDA PROVEEDORES', '', 109512, 'egreso_banco'),
    ('2026-10-19', 'OPEN 365', 'PAGO DEUDA PROVEEDORES', '', 240239.99, 'egreso_banco'),
    ('2026-10-19', 'PZ LIMPIEZA', 'PAGO DEUDA PROVEEDORES', '', 102052.4, 'egreso_banco'),
    ('2026-10-19', 'VITTORIOS', 'PAGO DEUDA PROVEEDORES', '', 92971.44, 'egreso_banco'),
    ('2026-10-19', 'WAGGON', 'PAGO DEUDA PROVEEDORES', '', 13394.25, 'egreso_banco'),
    ('2026-10-19', 'WAGGON', 'PAGO DEUDA PROVEEDORES', '', 44271.99, 'egreso_banco'),
    ('2026-10-20', 'LIBRERIA', 'IMPRENTA, LIBRERÍA', '', 5600, 'egreso_efectivo'),
    ('2026-10-20', 'PERSONAL', 'PERSONAL COCINA', '', 33000, 'egreso_efectivo'),
    ('2026-10-20', 'SODERIA DEL CIELO', 'INSUMOS BARRA', '', 46000, 'egreso_efectivo'),
    ('2026-10-20', 'TWEETY VERDULERIA', 'VERDULERIA', '', 9061.5, 'egreso_efectivo'),
    ('2026-10-20', 'ZECOR', 'PAGO DEUDA', '', 198800, 'egreso_efectivo'),
    ('2026-10-21', 'PERSONAL', 'PERSONAL COCINA', '', 36300, 'egreso_efectivo'),
    ('2026-10-22', 'PAPU CUISINE', 'PAGO DEUDA PROVEEDORES', '', 97920, 'egreso_efectivo'),
    ('2026-10-26', 'ALQUERIA', 'PAGO DEUDA PROVEEDORES', '', 225643.81, 'egreso_banco'),
    ('2026-10-26', 'AMERICAN WINE GRUP', 'PAGO DEUDA PROVEEDORES', '', 176400.07, 'egreso_banco'),
    ('2026-10-26', 'AMERICAN WINE GRUP', 'PAGO DEUDA PROVEEDORES', '', 280799.96, 'egreso_banco'),
    ('2026-10-26', 'FERMENTUM JUAN PABLO', 'PAGO DEUDA PROVEEDORES', '', 86848, 'egreso_banco'),
    ('2026-10-26', 'IL NONNO ALPINO', 'PAGO DEUDA PROVEEDORES', '', 114397.32, 'egreso_banco'),
    ('2026-10-26', 'JUAN PABLO', 'PAGO DEUDA PROVEEDORES', '', 171288.01, 'egreso_banco'),
    ('2026-10-26', 'JUAN PABLO', 'PAGO DEUDA PROVEEDORES', '', 116900.88, 'egreso_banco'),
    ('2026-10-26', 'LORENZOS', 'PAGO DEUDA PROVEEDORES', '', 56944, 'egreso_banco'),
    ('2026-10-26', 'LORENZOS', 'PAGO DEUDA PROVEEDORES', '', 26904, 'egreso_banco'),
    ('2026-10-26', 'TORK', 'PAGO DEUDA PROVEEDORES', '', 104026.85, 'egreso_banco'),
    ('2026-10-26', 'WAGGON', 'PAGO DEUDA PROVEEDORES', '', 87198.35, 'egreso_banco'),
    ('2026-10-26', 'WAGGON', 'PAGO DEUDA PROVEEDORES', '', 10102.6, 'egreso_banco'),
    ('2026-10-28', 'SODERIA DEL CIELO', 'INSUMOS BARRA', '', 24500, 'egreso_efectivo'),
    ('2026-10-30', 'PERSONAL', 'PERSONAL SALON', '', 25750, 'egreso_efectivo'),
    ('2026-10-30', 'SABADO VERMUT', 'VERMUT', '', 138000, 'deuda_proveedores'),
    ('2026-10-30', 'VIDRIOS', 'MANTENIMIENTO LIMPIEZA', '', 14000, 'egreso_efectivo');

  delete from public.ingresos_egresos where lote_importacion = '2026-10' and observaciones = 'Importado del Excel octubre 2026';
  insert into public.proveedores (nombre) select distinct on (lower(prov)) prov from _imp where trim(prov) <> '' on conflict (lower(nombre)) do nothing;
  insert into public.ingresos_egresos (fecha, proveedor_id, concepto, factura_numero, monto, forma, estado_pago, medio_pago, origen, usuario_id, observaciones, lote_importacion)
  select i.fecha::date, (select p.id from public.proveedores p where lower(p.nombre) = lower(i.prov)), i.conc, nullif(i.fac, ''), i.monto, i.forma,
         'pagado'::estado_pago_tipo, case i.forma when 'egreso_banco' then 'banco' when 'egreso_efectivo' then 'efectivo' else null end,
         'manual', (select id from public.usuarios where rol = 'admin' order by created_at limit 1), 'Importado del Excel octubre 2026', '2026-10'
    from _imp i;
end
$$;

-- ===== 4) pagos de deuda importados: cruzar con el calendario =====
do $$
declare r record; v_cruzados int := 0;
begin
  for r in select id from public.ingresos_egresos
            where lote_importacion = '2026-10' and observaciones = 'Importado del Excel octubre 2026' and concepto in ('PAGO DEUDA PROVEEDORES', 'PAGO DEUDA')
              and forma in ('egreso_efectivo', 'egreso_banco') loop
    if public._calendario_conciliar(r.id, true) is not null then v_cruzados := v_cruzados + 1; end if;
  end loop;
  raise notice 'Pagos cruzados con el calendario: %', v_cruzados;
end
$$;

-- ===== Resultado: octubre por concepto (deuda + banco + efectivo + otras deudas), para comparar con tu planilla =====
select e.concepto, round(sum(e.monto)) as total_app, count(*) as movimientos
  from public.ingresos_egresos e
 where coalesce(to_date(e.lote_importacion || '-01', 'YYYY-MM-DD'), date_trunc('month', e.fecha)::date) = '2026-10-01'
   and e.forma in ('deuda_proveedores', 'egreso_banco', 'egreso_efectivo', 'otras_deudas')
 group by 1 order by 2 desc;
