-- Gata Maula: corrige el stock de mercaderia al inicio de septiembre 2026 (tu planilla corregida dice 3.938.557, igual al cierre de agosto).
-- Era 5.807.043. Es lo unico que cambio entre la planilla que estaba cargada y la nueva.
-- Correr UNA vez en el SQL Editor.
update public.eerr_manual set stock_inicio = 3938557 where mes = '2026-09-01';

select mes, stock_inicio, stock_fin, desperdicios, costo_teorico_pct from public.eerr_manual where mes in ('2026-08-01', '2026-09-01') order by mes;
