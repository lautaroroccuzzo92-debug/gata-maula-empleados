-- Gata Maula: ajustes a los cierres de caja de octubre.
--   * 18/10: el cierre quedo anotado como turno manana, pero es del turno tarde -> se pasa a turno tarde
--   * 20/10 y 21/10: ya estaban cargados como "dia completo" pero eran solo la fila del turno tarde de la planilla
--       -> se pasan a turno tarde y se suma el turno manana (primera fila de esos dias)
-- Correr UNA vez en el SQL Editor (despues de 0038).

do $$
declare v_admin uuid; v_manu uuid;
begin
  select id into v_admin from public.usuarios where rol = 'admin' order by created_at limit 1;
  select id into v_manu from public.usuarios where upper(nombre) = 'MANU' limit 1;

  -- 18/10: manana -> tarde
  update public.caja_diaria set turno = 'tarde', actualizado_por = v_admin, actualizado_en = now()
    where fecha = '2026-10-18' and turno = 'manana'
      and not exists (select 1 from public.caja_diaria where fecha = '2026-10-18' and turno = 'tarde');

  -- 20/10: el "dia completo" cargado coincide con la fila tarde de la planilla (499.242)
  update public.caja_diaria set turno = 'tarde', actualizado_por = v_admin, actualizado_en = now()
    where fecha = '2026-10-20' and turno = 'completo' and abs(venta_total - 499242) < 1
      and not exists (select 1 from public.caja_diaria where fecha = '2026-10-20' and turno = 'tarde');
  insert into public.caja_diaria (fecha, turno, tarjeta_credito, tarjeta_debito, transferencia, qr_posnet, qr_mercado_pago, efectivo, cierre_sistema, responsable, usuario_id)
    select '2026-10-20', 'manana', 0, 0, 19000, 0, 0, 21500, 40500, 'MANU', coalesce(v_manu, v_admin)
    where exists (select 1 from public.caja_diaria where fecha = '2026-10-20' and turno = 'tarde')
      and not exists (select 1 from public.caja_diaria where fecha = '2026-10-20' and turno = 'manana');

  -- 21/10: el "dia completo" cargado coincide con la fila tarde de la planilla (1.040.340,92)
  update public.caja_diaria set turno = 'tarde', actualizado_por = v_admin, actualizado_en = now()
    where fecha = '2026-10-21' and turno = 'completo' and abs(venta_total - 1040340.92) < 1
      and not exists (select 1 from public.caja_diaria where fecha = '2026-10-21' and turno = 'tarde');
  insert into public.caja_diaria (fecha, turno, tarjeta_credito, tarjeta_debito, transferencia, qr_posnet, qr_mercado_pago, efectivo, cierre_sistema, responsable, usuario_id)
    select '2026-10-21', 'manana', 94500, 14800, 258800, 0, 0, 0, 368100, 'MANU', coalesce(v_manu, v_admin)
    where exists (select 1 from public.caja_diaria where fecha = '2026-10-21' and turno = 'tarde')
      and not exists (select 1 from public.caja_diaria where fecha = '2026-10-21' and turno = 'manana');
end
$$;

-- ===== octubre despues de los ajustes =====
select c.fecha, c.turno, c.venta_total as total, c.tarjeta_credito as credito, c.tarjeta_debito as debito, c.transferencia, c.qr_posnet, c.qr_mercado_pago as qr, c.efectivo, coalesce(u.nombre, c.responsable) as cerro
  from public.caja_diaria c left join public.usuarios u on u.id = c.usuario_id
 where c.fecha between '2026-10-01' and '2026-10-31' order by c.fecha, c.turno;
