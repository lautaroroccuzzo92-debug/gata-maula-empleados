-- Gata Maula: el "Colonial Lomo" de la planilla (1,09) es el Lomo Colonial de Napoles, no el jamon cocido Calchaqui.
--   * Calchaqui jamon cocido vuelve a 0 (como estaba antes)
--   * Napoles Lomo Colonial queda con 1,09 y pasa a Fiambres (en la planilla esta en fiambres)
-- Correr UNA vez en el SQL Editor.

do $$
declare v_lomo uuid;
begin
  update public.stock s set cantidad_actual = 0, valorizacion = 0, ultima_actualizacion = now()
    from public.insumos i
   where i.id = s.insumo_id and upper(trim(coalesce(i.marca, ''))) = 'CALCHAQUI' and upper(trim(i.nombre)) = 'JAMON COCIDO';

  select id into v_lomo from public.insumos where upper(trim(nombre)) = 'LOMO COLONIAL' and upper(trim(coalesce(marca, ''))) = 'NAPOLES' and not es_preparacion limit 1;
  if v_lomo is null then raise exception 'No encontre el insumo Napoles Lomo Colonial'; end if;
  update public.insumos set subcategoria = 'fiambres' where id = v_lomo;
  perform public._stock_alta(v_lomo, 'kg');
  update public.stock s set cantidad_actual = 1.09, valorizacion = 1.09 * coalesce(i.precio_costo_kg, 0), ultima_actualizacion = now()
    from public.insumos i where i.id = s.insumo_id and s.insumo_id = v_lomo;
end
$$;

select trim(coalesce(i.marca || ' ', '') || i.nombre) as insumo, i.subcategoria::text as rubro, s.cantidad_actual
  from public.stock s join public.insumos i on i.id = s.insumo_id
 where (upper(i.nombre) = 'LOMO COLONIAL') or (upper(i.nombre) = 'JAMON COCIDO' and upper(coalesce(i.marca, '')) = 'CALCHAQUI')
 order by 1;
