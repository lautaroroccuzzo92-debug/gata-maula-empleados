-- SOLO MIRA, no cambia nada. Para cada producto de Produccion con receta muestra:
--   * si lo elaborado va a SUBIR al stock (unidad del lote = unidad del stock)
--   * que ingredientes BAJAN y cuanto, por cada 1 kg (o 1 unidad) elaborado
--   * que ingredientes NO bajan (no se cuentan en el stock o la unidad no se puede convertir)
with base as (
  select pi.id, pi.nombre, pi.insumo_id, r.id as rid, r.tipo, coalesce(r.merma_pct, 0) as m,
         case when pi.unidad in ('kg', 'gr') then 'kg' else pi.unidad end as u_item,
         (select sum(cantidad) from public.receta_insumos where receta_id = r.id and tipo_medida::text = 'gramos') as gr,
         coalesce(s.unidad, i.unidad_medida) as u_stock, (s.insumo_id is not null) as en_stock
    from public.produccion_items pi
    join public.recetas r on r.id = pi.receta_id
    left join public.insumos i on i.id = pi.insumo_id
    left join public.stock s on s.insumo_id = pi.insumo_id
   where pi.activo
), fac as (
  select b.*, case when b.tipo = 'preparacion'
                   then (case when b.u_item = 'kg' and coalesce(b.gr, 0) > 0 then 1000 / (b.gr * (1 - b.m / 100)) end)
                   else (case when b.u_item = 'unidad' then 1 when coalesce(b.gr, 0) > 0 then 1000 / b.gr end) end as f
    from base b
), lin as (
  select f.id, trim(coalesce(i2.marca || ' ', '') || i2.nombre) as prod, st2.insumo_id is not null as en_st,
         ri.cantidad, f.f,
         case when ri.tipo_medida::text = 'unidad' then (case when st2.unidad = 'kg' then null else 1 end)
              when coalesce(st2.unidad, i2.unidad_medida) = 'kg' then 1000
              when coalesce(st2.unidad, i2.unidad_medida) = 'unidad' and coalesce(i2.gramos_paquete, 0) > 0 then i2.gramos_paquete
              else null end as divisor,
         coalesce(st2.unidad, i2.unidad_medida) as u2
    from fac f
    join public.receta_insumos ri on ri.receta_id = f.rid
    join public.insumos i2 on i2.id = ri.insumo_id
    left join public.stock st2 on st2.insumo_id = ri.insumo_id
   where ri.insumo_id is distinct from f.insumo_id
)
select f.nombre as producto, f.u_item as se_carga_en, f.u_stock as stock_en,
       case when f.en_stock and f.u_item = f.u_stock then 'SUBE al stock' else 'NO sube (revisar)' end as lo_elaborado,
       case when f.f is null then 'SIN FACTOR: la receta no tiene gramos o el lote esta en otra unidad' end as aviso,
       (select string_agg(l.prod || ' -' || round(l.f * l.cantidad / l.divisor, 3) || ' ' || l.u2, ' | ' order by l.prod)
          from lin l where l.id = f.id and l.en_st and l.divisor is not null) as bajan_por_1,
       (select string_agg(l.prod, ' | ' order by l.prod)
          from lin l where l.id = f.id and not (l.en_st and l.divisor is not null)) as no_bajan
  from fac f
 order by f.nombre;
