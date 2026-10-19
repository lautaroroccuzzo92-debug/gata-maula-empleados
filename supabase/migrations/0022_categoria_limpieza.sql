-- Gata Maula: agrega la categoria "limpieza" a los insumos.
-- Correr SOLA, primero (Postgres no deja usar el valor nuevo en la misma corrida). Despues correr 0023.
alter type subcategoria_insumo add value if not exists 'limpieza';
