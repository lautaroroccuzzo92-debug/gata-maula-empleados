-- Gata Maula: Zecor y Papu Cuisine se pagan una vez por semana (todo lo de la semana, el mismo dia de la semana siguiente).
--   * proveedores.pago_semanal_dia: dia de la semana de cobro (1 = lunes ... 7 = domingo). Zecor = martes (2), Papu Cuisine = jueves (4).
--   * Las boletas de esos proveedores vencen el dia de cobro de la semana siguiente (en vez de fecha + dias de plazo). Se recalculan las que siguen pendientes.
--   * Cuando anotas en Ingresos/Egresos el efectivo de la semana (un solo pago por el total), la app lo cruza con TODAS las boletas de ese ciclo
--     (Papu: tambien con el 10% de descuento por efectivo) y las marca pagadas; el pago pasa a "PAGO DEUDA PROVEEDORES" para que el gasto no se cuente dos veces.
--   * pagar_calendario_grupo: paga de una vez todas las boletas de una semana.
--   * Al final se cruzan los pagos anotados en los ultimos 60 dias que no se habian cruzado y se muestra que se marco pagado solo y que sigue pendiente.
-- Correr UNA vez en el SQL Editor y revisar el resultado final. Es seguro correrlo mas de una vez.

alter table public.proveedores add column if not exists pago_semanal_dia smallint check (pago_semanal_dia between 1 and 7);
update public.proveedores set pago_semanal_dia = 2 where lower(nombre) like '%zecor%';
update public.proveedores set pago_semanal_dia = 4 where lower(nombre) like '%papu%';

-- vencimiento de una boleta: dia de cobro de la semana siguiente (si el proveedor es semanal), o fecha + plazo
create or replace function public._venc_proveedor(p_prov uuid, p_fecha date)
returns date
language sql stable set search_path = public as $$
  select case when pr.pago_semanal_dia is not null
              then date_trunc('week', p_fecha)::date + 7 + (pr.pago_semanal_dia - 1)
              else p_fecha + coalesce(pr.plazo_pago_dias, 7) end
    from (select 1) x left join public.proveedores pr on pr.id = p_prov
$$;

-- cada deuda con un proveedor entra sola al calendario (igual que antes, con el vencimiento nuevo)
create or replace function public.trg_deuda_a_calendario()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_nombre text;
begin
  if new.forma = 'deuda_proveedores' and new.lote_importacion is null then
    select nombre into v_nombre from public.proveedores where id = new.proveedor_id;
    insert into public.calendario_pagos
      (fecha_factura, fecha_vencimiento, nro_factura, proveedor_id, proveedor_texto, concepto, total, facturado, egreso_id, origen)
    values
      (new.fecha, public._venc_proveedor(new.proveedor_id, new.fecha), new.factura_numero, new.proveedor_id,
       coalesce(v_nombre, new.concepto), new.concepto, new.monto, case when new.factura_numero is not null then 'SI' else 'NO' end, new.id, 'app');
  end if;
  return new;
end;
$$;

-- las boletas pendientes de Zecor y Papu pasan al vencimiento semanal
update public.calendario_pagos cp
   set fecha_vencimiento = public._venc_proveedor(cp.proveedor_id, cp.fecha_factura)
  from public.proveedores pr
 where pr.id = cp.proveedor_id and pr.pago_semanal_dia is not null and not cp.pagado and cp.fecha_factura is not null;

-- ============================================================ cruzar un pago anotado con las boletas pendientes (ahora tambien por semana)
create or replace function public._calendario_conciliar(p_egreso_id uuid)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  e record; v_nombre text; v_ids uuid[]; v_tot numeric; v_pct numeric; v_nro text;
  v_dto boolean; c record; v_desc numeric; v_conc text;
begin
  select * into e from public.ingresos_egresos where id = p_egreso_id;
  if not found or e.forma not in ('egreso_efectivo', 'egreso_banco') or e.origen <> 'manual' or e.lote_importacion is not null
     or e.proveedor_id is null or coalesce(e.monto, 0) <= 0 or coalesce(e.observaciones, '') like 'Pago de % del %' then
    return null;
  end if;
  select nombre into v_nombre from public.proveedores where id = e.proveedor_id;
  if v_nombre is null then return null; end if;

  with cand as (
    select cp.*, coalesce(pr.descuento_efectivo_pct, 0) as pct, coalesce(pr.pago_semanal_dia, 0) as semanal
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
    union all
    -- proveedores semanales: todas las boletas de un mismo ciclo (mismo dia de cobro) se pagan juntas
    select array_agg(id order by fecha_factura, id), sum(total), max(pct), null::text, 3, fecha_vencimiento
      from cand where semanal > 0 group by fecha_vencimiento
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
        nota = trim(coalesce(nota || ' · ', '') || 'Se marco pagado solo: pago anotado en Ingresos y egresos el ' || to_char(e.fecha, 'DD/MM') || case when v_dto then ' (con ' || v_pct || '% de descuento por efectivo)' else '' end)
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

  if e.concepto is distinct from 'PAGO DEUDA PROVEEDORES' then
    update public.ingresos_egresos set concepto = 'PAGO DEUDA PROVEEDORES',
        observaciones = trim(coalesce(observaciones || ' | ', '') || 'Pago de ' || case when v_nro is null then 'boletas de la semana' else 'factura ' || v_nro end || ' (concepto que se habia cargado: ' || e.concepto || ')')
      where id = e.id;
  end if;
  return v_ids[1];
end;
$$;
revoke all on function public._calendario_conciliar(uuid) from public;

-- ============================================================ pagar de una vez todas las boletas de una semana
create or replace function public.pagar_calendario_grupo(p_ids uuid[], p_forma text, p_fecha date)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  i uuid; r jsonb; v_pagado numeric := 0; v_desc numeric := 0;
begin
  if public.rol_actual() <> 'admin' then
    raise exception 'Sin permiso';
  end if;
  if p_ids is null or array_length(p_ids, 1) is null then raise exception 'No hay boletas para pagar'; end if;
  foreach i in array p_ids loop
    r := public.pagar_calendario(i, p_forma, p_fecha);
    v_pagado := v_pagado + coalesce((r->>'pagado')::numeric, 0);
    v_desc := v_desc + coalesce((r->>'descuento')::numeric, 0);
  end loop;
  return jsonb_build_object('ok', true, 'pagado', v_pagado, 'descuento', v_desc, 'boletas', array_length(p_ids, 1));
end;
$$;
grant execute on function public.pagar_calendario_grupo(uuid[], text, date) to authenticated;

-- ============================================================ cruzar los pagos de Zecor y Papu anotados en los ultimos 60 dias
do $$
declare r record;
begin
  for r in select e.id from public.ingresos_egresos e join public.proveedores p on p.id = e.proveedor_id
            where p.pago_semanal_dia is not null and e.origen = 'manual' and e.forma in ('egreso_efectivo', 'egreso_banco')
              and e.lote_importacion is null and e.fecha >= public.hoy_ar() - 60
              and coalesce(e.observaciones, '') not like 'Pago de % del %'
            order by e.fecha, e.id loop
    perform public._calendario_conciliar(r.id);
  end loop;
end
$$;

-- ============================================================ resultado para revisar
select 'SE MARCO PAGADA SOLA' as estado, to_char(cp.fecha_pago, 'YYYY-MM-DD') as fecha, cp.proveedor_texto as proveedor,
       coalesce(cp.nro_factura, '') as numero, round(cp.total) as monto, cp.nota as detalle
  from public.calendario_pagos cp join public.proveedores p on p.id = cp.proveedor_id
 where p.pago_semanal_dia is not null and cp.pagado and cp.nota like '%Se marco pagado solo%' and cp.fecha_pago >= public.hoy_ar() - 60
union all
select 'SIGUE PENDIENTE', to_char(cp.fecha_vencimiento, 'YYYY-MM-DD'), cp.proveedor_texto, coalesce(cp.nro_factura, ''), round(cp.total),
       'boleta del ' || coalesce(to_char(cp.fecha_factura, 'DD/MM'), '?') || ' · se cobra el ' || to_char(cp.fecha_vencimiento, 'DD/MM')
  from public.calendario_pagos cp join public.proveedores p on p.id = cp.proveedor_id
 where p.pago_semanal_dia is not null and not cp.pagado
union all
select 'PENDIENTE SIN RENGLON EN EL CALENDARIO', to_char(i.fecha, 'YYYY-MM-DD'), coalesce(p.nombre, ''), coalesce(i.factura_numero, i.remito_numero, ''), round(i.monto), i.concepto
  from public.ingresos_egresos i left join public.proveedores p on p.id = i.proveedor_id
 where i.forma = 'deuda_proveedores' and i.estado_pago = 'pendiente' and i.monto > 0
   and not exists (select 1 from public.calendario_pagos cp where cp.egreso_id = i.id)
 order by 1, 2, 3;
