-- Gata Maula: las papas Danal se cuentan en unidades (paquetes de 800 g) y la receta de cada sandwich lleva 25 g.
-- Se carga el peso de cada paquete (800 g) para que cada sandwich descuente 25/800 de paquete. Luego se recalcula el descuento de lo ya cargado.
-- Correr UNA vez en el SQL Editor. Es seguro correrlo mas de una vez.

update public.insumos set gramos_paquete = 800
 where public.normalizar_texto(trim(coalesce(marca || ' ', '') || nombre)) = 'PAPAS DANAL';

do $$
declare a timestamp; b timestamp;
begin
  select min(fecha), max(fecha) into a, b from public.pos_lineas;
  if a is not null then perform public._pos_aplicar(a, b); end if;
end
$$;

-- resultado: las papas Danal con su peso por paquete, su unidad y su stock
select trim(coalesce(i.marca || ' ', '') || i.nombre) as producto, i.gramos_paquete as gramos_por_paquete,
       coalesce(s.unidad, i.unidad_medida) as se_cuenta_en, s.cantidad_actual as stock
  from public.insumos i left join public.stock s on s.insumo_id = i.id
 where public.normalizar_texto(trim(coalesce(i.marca || ' ', '') || i.nombre)) = 'PAPAS DANAL';
