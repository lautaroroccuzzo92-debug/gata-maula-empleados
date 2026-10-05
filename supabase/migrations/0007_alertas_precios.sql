-- Gata Maula: cuando cambia el precio de un insumo (por factura o a mano):
--   1) se guarda el cambio en historial_precios,
--   2) si subio mas de 7% se marca como alerta (para hablar con el proveedor),
--   3) se recalcula el costo de todas las recetas que usan ese insumo.
-- El precio de carta de las recetas NUNCA se toca: lo definis vos.
-- Correr UNA vez en el SQL Editor de Supabase.

-- Los precios se guardaban con 2 decimales; las recetas del Excel usan mas
-- decimales, asi que se amplia para que el costo no se desvie por redondeo.
alter table public.insumos alter column precio_costo_kg type numeric(14,6);

create table if not exists public.historial_precios (
  id uuid primary key default gen_random_uuid(),
  insumo_id uuid not null references public.insumos(id) on delete cascade,
  precio_anterior numeric(14,6) not null,
  precio_nuevo numeric(14,6) not null,
  variacion_pct numeric(8,2),
  origen text not null check (origen in ('factura', 'manual')),
  usuario_id uuid references public.usuarios(id),
  alerta boolean not null default false,
  alerta_resuelta boolean not null default false,
  resuelta_por uuid references public.usuarios(id),
  resuelta_en timestamptz,
  fecha timestamptz not null default now()
);
create index if not exists historial_precios_alertas_idx on public.historial_precios (alerta, alerta_resuelta);
create index if not exists historial_precios_insumo_idx on public.historial_precios (insumo_id, fecha desc);

alter table public.historial_precios enable row level security;
drop policy if exists historial_precios_select on public.historial_precios;
create policy historial_precios_select on public.historial_precios for select
  using (public.rol_actual() in ('admin', 'encargado'));
-- Solo se puede actualizar para marcar una alerta como resuelta.
drop policy if exists historial_precios_update on public.historial_precios;
create policy historial_precios_update on public.historial_precios for update
  using (public.rol_actual() in ('admin', 'encargado'));

-- Recalcula costo_total_calculado (= costo variable, igual a la suma de
-- ingredientes del Excel) de las recetas que usan p_insumo_id (o de todas si
-- es null). 'gramos' = cantidad/1000 x precio; 'unidad' = cantidad x precio.
create or replace function public._recalcular_costo_recetas(p_insumo_id uuid)
returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_filas integer;
begin
  update public.recetas r
     set costo_total_calculado = round(sub.costo, 2)
    from (
      select ri.receta_id,
             sum(case when ri.tipo_medida = 'unidad'
                      then ri.cantidad * i.precio_costo_kg
                      else ri.cantidad / 1000 * i.precio_costo_kg end) as costo
        from public.receta_insumos ri
        join public.insumos i on i.id = ri.insumo_id
       where p_insumo_id is null
          or ri.receta_id in (select receta_id from public.receta_insumos where insumo_id = p_insumo_id)
       group by ri.receta_id
    ) sub
   where r.id = sub.receta_id;
  get diagnostics v_filas = row_count;
  return v_filas;
end;
$$;
revoke all on function public._recalcular_costo_recetas(uuid) from public;

-- Boton "recalcular todo" por si alguna vez hace falta (solo admin).
create or replace function public.recalcular_costos_recetas()
returns integer
language plpgsql security definer set search_path = public as $$
begin
  if public.rol_actual() <> 'admin' then
    raise exception 'Sin permiso';
  end if;
  return public._recalcular_costo_recetas(null);
end;
$$;
grant execute on function public.recalcular_costos_recetas() to authenticated;

create or replace function public.trg_insumo_precio_cambio()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_var numeric;
begin
  -- Los imports masivos desde el SQL Editor pueden apagar el historial con:
  --   select set_config('app.sin_historial', 'on', true);
  if current_setting('app.sin_historial', true) = 'on' then
    return new;
  end if;
  if new.precio_costo_kg is distinct from old.precio_costo_kg then
    if old.precio_costo_kg > 0 then
      v_var := round((new.precio_costo_kg - old.precio_costo_kg) / old.precio_costo_kg * 100, 2);
    end if;
    insert into public.historial_precios
      (insumo_id, precio_anterior, precio_nuevo, variacion_pct, origen, usuario_id, alerta)
    values
      (new.id, old.precio_costo_kg, new.precio_costo_kg, v_var,
       -- sin sesion de usuario = vino de la carga de factura (API con service_role)
       case when auth.uid() is null then 'factura' else 'manual' end,
       auth.uid(),
       coalesce(v_var, 0) > 7);
    update public.stock set valorizacion = cantidad_actual * new.precio_costo_kg where insumo_id = new.id;
    perform public._recalcular_costo_recetas(new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists insumos_precio_cambio on public.insumos;
create trigger insumos_precio_cambio
  after update of precio_costo_kg on public.insumos
  for each row execute function public.trg_insumo_precio_cambio();
