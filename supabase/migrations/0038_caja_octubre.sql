-- Gata Maula: carga los cierres de caja de OCTUBRE (hoja INGRESOS OCTUBRE de tu planilla) por turno.
--   * segun la fila en que esta anotado cada cierre: primera fila del dia = turno manana, segunda fila = turno tarde; un dia sin filas anotadas es un dia cerrado
--   * columnas: tarjeta credito, debito, transferencia, QR Posnet, QR, efectivo; cierre sistema y responsable (Manu / Facu)
--   * no pisa nada: si ese dia y turno ya tiene un cierre, lo deja como esta (y si el dia ya tiene un cierre de dia completo, tampoco carga)
-- Correr UNA vez en el SQL Editor (despues de 0030). Muestra al final lo cargado y lo que se salteo.

do $$
declare t record; v_uid uuid; v_admin uuid; v_cargados int := 0;
begin
  select id into v_admin from public.usuarios where rol = 'admin' order by created_at limit 1;
  for t in select * from (values
    ('2026-10-01', 'manana', 0, 0, 0, 0, 34400, 90360, null, 124760, 'MANU'),
    ('2026-10-01', 'tarde', 0, 232300, 231400, 0, 197890, 91490.51, null, 753080.56, 'FACU'),
    ('2026-10-02', 'manana', 0, 0, 0, 0, 23000, 134732, null, 157732, 'MANU'),
    ('2026-10-02', 'tarde', 137400, 275600, 12000, 97300, 821896, 287980.01, null, 1632576.4, 'FACU'),
    ('2026-10-03', 'manana', 35300, 81500, 30500, 44400, 225100, 114764, null, 531564, 'MANU'),
    ('2026-10-03', 'tarde', 80900, 0, 57100, 0, 634765, 424290, null, 1197055, 'FACU'),
    ('2026-10-04', 'tarde', 39000, 0, 518975, 0, 0, 229719, null, 787695, 'MANU'),
    ('2026-10-06', 'manana', 0, 34816.77, 22500, 0, 54800, 13501.09, null, 125922.59, 'FACU'),
    ('2026-10-06', 'tarde', 28200, 59400, 35000, 0, 148700, 54000, null, 325300, 'MANU'),
    ('2026-10-07', 'manana', 17000, 0, 0, 0, 14500, 0, null, 31500, 'MANU'),
    ('2026-10-07', 'tarde', 71500, 111000, 0, 0, 402283, 98675.49, null, 683458.57, 'FACU'),
    ('2026-10-08', 'manana', 0, 15000, 14500, 0, 0, 5, null, 29505, 'MANU'),
    ('2026-10-08', 'tarde', 42800, 137300, 682675.1, 0, 0, 71000, null, 933775.1, 'FACU'),
    ('2026-10-09', 'manana', 0, 43300, 0, 0, 0, 0, null, 43300, 'FACU'),
    ('2026-10-09', 'tarde', 0, 152500, 415963, 0, 0, 146800, null, 715263, 'MANU'),
    ('2026-10-10', 'manana', 0, 39000, 160116, 20000, 0, 35500, null, 254616, 'MANU'),
    ('2026-10-10', 'tarde', 98800, 55000, 683192.17, 48900, 0, 118840.05, null, 1004732.2, 'FACU'),
    ('2026-10-11', 'tarde', 121600, 33000, 428200.13, 0, 12300, 247600, null, 842700.13, 'FACU'),
    ('2026-10-13', 'manana', 0, 0, 0, 0, 0, 14500, null, 14500, 'FACU'),
    ('2026-10-13', 'tarde', 0, 22000, 27430, 0, 0, 23288, null, 72718, 'FACU'),
    ('2026-10-14', 'manana', 0, 0, 0, 0, 209330, 14507, null, 223837, 'MANU'),
    ('2026-10-14', 'tarde', 0, 122800, 146900, 0, 5895, 19000, null, 294595.04, 'FACU'),
    ('2026-10-15', 'manana', 0, 0, 0, 0, 126700, 0, null, 126700, 'MANU'),
    ('2026-10-15', 'tarde', 0, 82300, 46100.03, 0, 492300, 103575, null, 724275.1, 'FACU'),
    ('2026-10-16', 'manana', 0, 0, 0, 0, 49250, 67002, null, 116252, 'MANU'),
    ('2026-10-16', 'tarde', 0, 112000, 12000, 0, 586175, 521202.25, null, 1231377.2, 'FACU'),
    ('2026-10-17', 'manana', 0, 73800, 218620, 0, 0, 0, null, 292420, 'MANU'),
    ('2026-10-17', 'tarde', 37000, 156300, 488200.06, 0, 63000, 300605.06, null, 1045105.1, 'FACU'),
    ('2026-10-18', 'manana', 0, 63500, 253675, 0, 0, 216000, null, 533175, 'MANU'),
    ('2026-10-20', 'manana', 0, 0, 19000, 0, 0, 21500, null, 40500, 'MANU'),
    ('2026-10-20', 'tarde', 0, 242300, 235800.03, 0, 0, 21142.01, null, 499242.06, 'FACU'),
    ('2026-10-21', 'manana', 94500, 14800, 258800, 0, 0, 0, null, 368100, 'MANU'),
    ('2026-10-21', 'tarde', 30800, 0, 874740.87, 0, 0, 134800.05, null, 1040340.9, 'FACU'),
    ('2026-10-22', 'manana', 0, 13000, 73100, 3000, 0, 37200, null, 126300, 'MANU'),
    ('2026-10-22', 'tarde', 90500, 188200, 660500, 0, 0, 176132.5, null, 1115332.5, 'FACU'),
    ('2026-10-23', 'manana', 0, 0, 48200, 0, 0, 0, null, 48200, 'FACU'),
    ('2026-10-23', 'tarde', 105700, 58500, 891499, 118000, 0, 214200, null, 1387899, 'MANU')
  ) as v(fecha, turno, credito, debito, transf, qrp, qr, efe, fiscal, cierre, resp) loop
    if exists (select 1 from public.caja_diaria where fecha = t.fecha::date and (turno = t.turno or turno = 'completo')) then continue; end if;
    select id into v_uid from public.usuarios where upper(nombre) = upper(t.resp) limit 1;
    insert into public.caja_diaria (fecha, turno, tarjeta_credito, tarjeta_debito, transferencia, qr_posnet, qr_mercado_pago, efectivo, monto_fiscal, cierre_sistema, responsable, usuario_id)
      values (t.fecha::date, t.turno, t.credito, t.debito, t.transf, t.qrp, t.qr, t.efe, t.fiscal::numeric, t.cierre::numeric, nullif(t.resp, ''), coalesce(v_uid, v_admin));
    v_cargados := v_cargados + 1;
  end loop;
  raise notice 'Cierres cargados: %', v_cargados;
end
$$;

-- ===== lo que quedo cargado en octubre =====
select c.fecha, c.turno, c.venta_total as total, c.tarjeta_credito as credito, c.tarjeta_debito as debito, c.transferencia, c.qr_posnet, c.qr_mercado_pago as qr, c.efectivo, coalesce(u.nombre, c.responsable) as cerro
  from public.caja_diaria c left join public.usuarios u on u.id = c.usuario_id
 where c.fecha between '2026-10-01' and '2026-10-31' order by c.fecha, c.turno;
