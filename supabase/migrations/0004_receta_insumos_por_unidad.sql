-- Gata Maula: permitir que un ingrediente de receta se cargue "por gramo/ml"
-- (como un fiambre o queso) o "por unidad" (como un pan, un packaging, una
-- lata de algo) sin tener que inventar un peso falso para que la cuenta cierre.

create type tipo_medida_receta as enum ('gramos', 'unidad');

alter table public.receta_insumos rename column cantidad_gramos to cantidad;
alter table public.receta_insumos add column tipo_medida tipo_medida_receta not null default 'gramos';

comment on column public.receta_insumos.cantidad is 'Si tipo_medida=gramos: gramos/ml usados. Si tipo_medida=unidad: cantidad de unidades usadas.';
comment on column public.insumos.precio_costo_kg is 'Precio por kg/litro si el insumo se usa por peso; precio por unidad si en la receta se usa como "unidad" (el mismo insumo puede tener ambos usos segun la receta).';
