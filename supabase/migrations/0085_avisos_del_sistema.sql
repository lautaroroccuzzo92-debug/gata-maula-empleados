-- Gata Maula: avisos del sistema para el administrador.
-- Cuando la inteligencia artificial (lectura de facturas o gatito) falla porque se acabo el credito de la cuenta de Anthropic,
-- el servidor deja un aviso y el administrador lo ve en rojo arriba de la pantalla de inicio. Se borra solo cuando la IA vuelve a funcionar
-- (o con el boton "Ya lo resolvi").
-- Correr UNA vez en el SQL Editor. Es seguro correrlo mas de una vez.

create table if not exists public.avisos_sistema (
  id uuid primary key default gen_random_uuid(),
  tipo text not null,
  mensaje text not null,
  origen text,
  veces int not null default 1,
  resuelto boolean not null default false,
  creado_en timestamptz not null default now(),
  ultimo_en timestamptz not null default now(),
  resuelto_en timestamptz
);
-- un solo aviso abierto por tipo
create unique index if not exists avisos_sistema_abierto_idx on public.avisos_sistema (tipo) where not resuelto;
alter table public.avisos_sistema enable row level security;
drop policy if exists avisos_sistema_select on public.avisos_sistema;
create policy avisos_sistema_select on public.avisos_sistema for select using (public.rol_actual() = 'admin');

-- lo usa el servidor (service_role) cuando detecta el problema
create or replace function public.aviso_sistema_registrar(p_tipo text, p_mensaje text, p_origen text default null)
returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.avisos_sistema (tipo, mensaje, origen) values (p_tipo, p_mensaje, p_origen)
  on conflict (tipo) where not resuelto
  do update set veces = public.avisos_sistema.veces + 1, ultimo_en = now(), origen = excluded.origen;
end;
$$;
revoke all on function public.aviso_sistema_registrar(text, text, text) from public;
grant execute on function public.aviso_sistema_registrar(text, text, text) to service_role;

-- lo usa el servidor cuando la IA vuelve a funcionar
create or replace function public.aviso_sistema_resolver_tipo(p_tipo text)
returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.avisos_sistema set resuelto = true, resuelto_en = now() where tipo = p_tipo and not resuelto;
end;
$$;
revoke all on function public.aviso_sistema_resolver_tipo(text) from public;
grant execute on function public.aviso_sistema_resolver_tipo(text) to service_role;

-- boton "Ya lo resolvi" (solo admin)
create or replace function public.aviso_resolver(p_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if public.rol_actual() <> 'admin' then raise exception 'Sin permiso'; end if;
  update public.avisos_sistema set resuelto = true, resuelto_en = now() where id = p_id and not resuelto;
end;
$$;
grant execute on function public.aviso_resolver(uuid) to authenticated;

select 'listo' as resultado, count(*) as avisos_abiertos from public.avisos_sistema where not resuelto;
