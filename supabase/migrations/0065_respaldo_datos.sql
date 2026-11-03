-- Gata Maula: copia de seguridad descargable desde la app (Ajustes > Copia de seguridad). Solo admin.
--   * respaldo_tablas(): lista las tablas de la app con la cantidad exacta de filas
--   * respaldo_pagina(tabla, desde, cuantos): devuelve un tramo de filas de una tabla (la app los junta en un archivo)
-- Correr UNA vez en el SQL Editor. Es seguro correrlo mas de una vez.

create or replace function public.respaldo_tablas() returns table (tabla text, filas bigint)
language plpgsql security definer set search_path = public as $$
declare r record; n bigint;
begin
  if public.rol_actual() is distinct from 'admin' then raise exception 'Sin permiso'; end if;
  for r in select c.relname::text as nombre from pg_class c join pg_namespace s on s.oid = c.relnamespace
            where s.nspname = 'public' and c.relkind in ('r', 'p') order by 1
  loop
    execute format('select count(*) from public.%I', r.nombre) into n;
    tabla := r.nombre; filas := n;
    return next;
  end loop;
end;
$$;
revoke all on function public.respaldo_tablas() from public;
grant execute on function public.respaldo_tablas() to authenticated;

create or replace function public.respaldo_pagina(p_tabla text, p_desde int, p_cuantos int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v jsonb;
begin
  if public.rol_actual() is distinct from 'admin' then raise exception 'Sin permiso'; end if;
  if not exists (select 1 from pg_class c join pg_namespace s on s.oid = c.relnamespace
                  where s.nspname = 'public' and c.relkind in ('r', 'p') and c.relname = p_tabla) then
    raise exception 'La tabla % no existe', p_tabla;
  end if;
  execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]''::jsonb) from (select * from public.%I t order by t.ctid offset %s limit %s) x',
                 p_tabla, greatest(p_desde, 0), least(greatest(p_cuantos, 1), 5000)) into v;
  return v;
end;
$$;
revoke all on function public.respaldo_pagina(text, int, int) from public;
grant execute on function public.respaldo_pagina(text, int, int) to authenticated;

-- prueba (desde el SQL Editor no hay usuario logueado, por eso se llama directo a las tablas)
select count(*) as tablas_en_la_app from pg_class c join pg_namespace s on s.oid = c.relnamespace where s.nspname = 'public' and c.relkind in ('r', 'p');
