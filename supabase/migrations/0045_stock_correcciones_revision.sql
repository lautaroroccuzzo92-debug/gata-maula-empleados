-- Gata Maula: correcciones despues de revisar la importacion de stock (0040).
--   * NUESTRO Bianco / Rosso estaban cruzados: planilla dice BIANCO 5 y ROSSO 12
--   * Castanas tostadas (0,55) no se habia encontrado: va en la preparacion "Castana de caju asadas"
--   * Se saca una llave "{" que sobraba en el nombre "Molde cortados / sandwich"
-- Correr UNA vez en el SQL Editor.

do $$
declare v_id uuid;
begin
  -- NUESTRO Bianco = 5, NUESTRO Rosso = 12
  update public.stock s set cantidad_actual = 5, valorizacion = 5 * coalesce(i.precio_costo_kg, 0), ultima_actualizacion = now()
    from public.insumos i where i.id = s.insumo_id and upper(trim(i.nombre)) = 'NUESTRO VERMUT BIANCO';
  update public.stock s set cantidad_actual = 12, valorizacion = 12 * coalesce(i.precio_costo_kg, 0), ultima_actualizacion = now()
    from public.insumos i where i.id = s.insumo_id and upper(trim(i.nombre)) = 'NUESTRO VERMUT ROSSO';

  -- Castanas tostadas = 0,55 kg
  select id into v_id from public.insumos where es_preparacion and nombre ilike 'CASTA%CAJU ASADAS' limit 1;
  if v_id is not null then
    perform public._stock_alta(v_id, 'kg');
    update public.stock s set cantidad_actual = 0.55, valorizacion = 0.55 * coalesce(i.precio_costo_kg, 0), ultima_actualizacion = now()
      from public.insumos i where i.id = s.insumo_id and s.insumo_id = v_id;
  end if;

  -- Nombre con llave de mas
  update public.insumos set nombre = trim(replace(nombre, '{', '')) where nombre like '%{%';
end
$$;

select trim(coalesce(i.marca || ' ', '') || i.nombre) as insumo, s.cantidad_actual
  from public.stock s join public.insumos i on i.id = s.insumo_id
 where upper(i.nombre) in ('NUESTRO VERMUT BIANCO', 'NUESTRO VERMUT ROSSO') or (i.es_preparacion and i.nombre ilike 'CASTA%CAJU ASADAS')
 order by 1;
