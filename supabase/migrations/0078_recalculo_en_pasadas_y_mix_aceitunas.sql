-- Gata Maula: dos arreglos de costos.
--   1) El recalculo general de costos dejaba desactualizados los platos que usan una preparacion cuyo precio cambia en esa misma pasada
--      (la preparacion quedaba bien y el plato con el costo viejo: por ejemplo la racion de aceitunas condimentadas seguia en $1.783).
--      Ahora el recalculo general repite las pasadas (hasta 4) hasta que ningun precio de preparacion cambie. Solo actualiza el precio de
--      una preparacion cuando de verdad cambio. El recalculo de un solo producto sigue igual.
--   2) ACEITUNAS RELLENAS MIX WARA PALLAY 1,5 KG figuraba a $32.000 "el kilo": es el precio del balde de 1,5 kg. Se cuenta en kilos,
--      asi que pasa a $21.333/kg (solo si todavia esta el precio del balde, mas de $25.000), igual que tu Excel.
-- Despues se recalcula todo y se muestran los costos de las recetas nuevas.
-- Correr UNA vez en el SQL Editor y mandar el resultado. Es seguro correrlo mas de una vez.

create or replace function public._recalcular_costo_recetas(p_insumo_id uuid)
returns integer
language plpgsql security definer set search_path = public as $$
declare
  r record;
  v_tipo text; v_merma numeric; v_insumo_prep uuid; v_nuevo numeric;
  v_filas integer := 0; v_n integer; v_pasada integer := 0; v_cambio boolean;
begin
  loop
    v_pasada := v_pasada + 1;
    v_cambio := false;
    for r in
      select ri.receta_id,
             sum(case when ri.tipo_medida = 'unidad'
                      then ri.cantidad * i.precio_costo_kg
                      else ri.cantidad / 1000 * i.precio_costo_kg end) as costo,
             sum(case when ri.tipo_medida = 'gramos' then ri.cantidad else 0 end) as gramos
        from public.receta_insumos ri
        join public.insumos i on i.id = ri.insumo_id
       where p_insumo_id is null
          or ri.receta_id in (select receta_id from public.receta_insumos where insumo_id = p_insumo_id)
       group by ri.receta_id
    loop
      update public.recetas set costo_total_calculado = round(r.costo, 2) where id = r.receta_id;
      v_filas := v_filas + 1;
      select tipo, merma_pct, insumo_id into v_tipo, v_merma, v_insumo_prep from public.recetas where id = r.receta_id;
      if v_tipo = 'preparacion' and v_insumo_prep is not null and r.gramos > 0 and (1 - v_merma / 100) > 0 then
        v_nuevo := round(r.costo * 1000 / (r.gramos * (1 - v_merma / 100)), 6);
        update public.insumos set precio_costo_kg = v_nuevo, fecha_ultima_actualizacion = now()
         where id = v_insumo_prep and precio_costo_kg is distinct from v_nuevo;
        get diagnostics v_n = row_count;
        if v_n > 0 then v_cambio := true; end if;
      end if;
    end loop;
    -- un solo producto: una pasada (los cambios en cascada los hace el propio cambio de precio); recalculo general: se repite hasta que quede estable
    exit when p_insumo_id is not null or not v_cambio or v_pasada >= 4;
  end loop;
  return v_filas;
end;
$$;
revoke all on function public._recalcular_costo_recetas(uuid) from public;

do $$
begin
  perform set_config('app.sin_historial', 'on', true);
  update public.insumos set precio_costo_kg = round(precio_costo_kg / 1.5, 2), fecha_ultima_actualizacion = now()
   where public.normalizar_texto(trim(coalesce(marca || ' ', '') || nombre)) like 'ACEITUNAS RELLENAS MIX WARA PALLAY 1,5 KG%'
     and precio_costo_kg > 25000;
end
$$;

select public._recalcular_costo_recetas(null) as recetas_recalculadas;

-- resultado
select x.tema, x.detalle, x.precio
  from (
    select 1 as orden, 'PRECIO DEL MIX DE ACEITUNAS (por kg)'::text as tema, trim(coalesce(i.marca || ' ', '') || i.nombre) as detalle, round(i.precio_costo_kg) as precio
      from public.insumos i where public.normalizar_texto(trim(coalesce(i.marca || ' ', '') || i.nombre)) like 'ACEITUNAS RELLENAS MIX WARA PALLAY 1,5 KG%'
    union all select 2, 'REFERENCIA DE TU EXCEL', 'mix de aceitunas (por kg)', 21333
    union all select 3, 'REFERENCIA DE TU EXCEL', 'racion de aceitunas condimentadas (120 g)', 746
    union all select 4, 'REFERENCIA DE TU EXCEL', 'racion de lengua a la vinagreta (120 g)', 749
    union all
    select 10 + row_number() over (order by r.nombre_producto), 'COSTO DE LA RECETA', r.nombre_producto, round(r.costo_total_calculado)
      from public.recetas r
     where r.tipo = 'plato' and public.normalizar_texto(r.nombre_producto) like any (array[
       'PICADA PARA LLEVAR%','CONO SOLO%','PICADA VERMUTERA','ANTIPASTI','LA EXQUISITA','PLATO AHUMADO','LA CABRITA',
       'CONO DE FIAMBRES%','RACION %','PASTRON, RELISH%','PORTOBELLOS%','LOMO A LAS FINAS%','COCIDO, TYBO%','CRUDO, PARMESANO%',
       'SANDWICH ASADITO%','SANDWICH MORTADELLA%','SANDWICH ESPECIAL EMBUCHADO','SANDWICH SALAME%','SANDWICH BONDIOLA, BRIE%','SANDWICH VEGGIE%',
       'ACEITUNAS VERDES CONDIMENTADAS%','MIX DE ACEITUNAS RELLENAS%','LENGUA A LA VINAGRETA'])
  ) x
 order by x.orden;
