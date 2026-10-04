-- Gata Maula: unifica las categorias de carta de las recetas con la lista fija
-- de la app (Sandwiches, Picadas y platitos, Conservas, Conito de picada,
-- Kutsi, Sandwiches de Focaccia entera, Fuera de carta).
-- Solo cambia el texto de recetas.categoria_carta; no toca costos ni ingredientes.

update public.recetas set categoria_carta = 'Conito de picada'
  where lower(nombre_producto) = 'cono de fiambres y quesos';

update public.recetas set categoria_carta = 'Sandwiches'
  where lower(categoria_carta) = 'sandwiches';

update public.recetas set categoria_carta = 'Kutsi'
  where lower(categoria_carta) = 'kutsi';

update public.recetas set categoria_carta = 'Picadas y platitos'
  where lower(categoria_carta) in ('picada', 'tapeo');

update public.recetas set categoria_carta = 'Conservas'
  where lower(categoria_carta) = 'conservas de la casa';
