-- SOLO MIRA, no cambia nada. Ingredientes de recetas que NO se llevan en el stock pero que parecen ser el mismo producto
-- que uno que SI se lleva en el stock (ej. "TOMATES CHERRY" de la receta vs "TOMATES CHERRYS" del stock).
-- Para cada ingrediente muestra el candidato mas parecido, los dos precios y en cuantas recetas se usa.
with norm as (
  select i.id, i.precio_costo_kg,
         trim(coalesce(i.marca || ' ', '') || i.nombre) as nombre,
         regexp_replace(public.normalizar_texto(trim(coalesce(i.marca || ' ', '') || i.nombre)), 'S\M', '', 'g') as n,
         (s.insumo_id is not null) as en_stock, s.cantidad_actual
    from public.insumos i left join public.stock s on s.insumo_id = i.id
), usados as (
  select ri.insumo_id, count(distinct ri.receta_id) as recetas
    from public.receta_insumos ri group by ri.insumo_id
), par as (
  select a.id as id_receta, a.nombre as ingrediente, a.precio_costo_kg as precio_receta, u.recetas,
         b.id as id_stock, b.nombre as candidato, b.precio_costo_kg as precio_stock, b.cantidad_actual as stock,
         greatest(public.similitud_palabras(a.n, b.n), public.similitud_palabras(b.n, a.n)) as sim
    from norm a
    join usados u on u.insumo_id = a.id
    join norm b on b.en_stock and b.id <> a.id
   where not a.en_stock
)
select distinct on (p.id_receta) p.ingrediente, p.precio_receta, p.recetas as en_recetas, p.candidato as parecido_en_stock,
       p.precio_stock, p.stock, round(p.sim::numeric, 2) as parecido
  from par p
 where p.sim >= 0.5
 order by p.id_receta, p.sim desc, p.precio_stock desc;
