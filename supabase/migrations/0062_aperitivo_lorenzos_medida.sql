-- Gata Maula: medida del aperitivo sin alcohol de Lorenzos = 40 ml de aperitivo + 115 ml de soda (y 90 gr de hielo, que no se controla).
--   * el aperitivo (tinto y bianco) pasa a tener medida de 40 ml (la botella sigue siendo de 750 ml)
--   * cada "MEDIDA APERITIVO SIN ALCOHOL ..." de Postberry descuenta ademas 115 ml de soda (0,23 de sifon de 500 ml), en vez de la soda por ticket
-- Correr UNA vez en el SQL Editor (despues de la 0061). Es seguro correrlo mas de una vez.

update public.insumos set ml_medida = 40
 where public.normalizar_texto(trim(coalesce(marca || ' ', '') || nombre)) like '%APERITIVO%'
   and public.normalizar_texto(trim(coalesce(marca || ' ', '') || nombre)) like '%LORENZO%';

create or replace function public._pos_soda_aperitivo() returns int
language plpgsql security definer set search_path = public as $$
declare v_soda uuid := (select valor::uuid from public.pos_config where clave = 'insumo_soda'); n int := 0; r record;
begin
  if v_soda is null then return 0; end if;
  for r in select distinct v.producto from public.pos_vinculo v
            where public.normalizar_texto(v.producto) like 'MEDIDA APERITIVO%' and v.insumo_id <> v_soda
  loop
    update public.pos_vinculo set lleva_soda = false where producto = r.producto;
    insert into public.pos_vinculo (producto, insumo_id, modo, valor, lleva_soda) values (r.producto, v_soda, 'ml', 115, false)
      on conflict (producto, insumo_id) do update set modo = 'ml', valor = 115, lleva_soda = false;
    n := n + 1;
  end loop;
  return n;
end;
$$;
revoke all on function public._pos_soda_aperitivo() from public;

-- la vinculacion automatica tambien agrega la soda del aperitivo
create or replace function public.pos_autovincular() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v jsonb;
begin
  if public.rol_actual() not in ('admin', 'encargado') then raise exception 'Sin permiso'; end if;
  v := public._pos_autovincular();
  perform public._pos_soda_aperitivo();
  perform public.pos_recalcular_todo();
  return v;
end;
$$;
grant execute on function public.pos_autovincular() to authenticated;

select public._pos_soda_aperitivo() as productos_con_soda_de_aperitivo;
do $$
declare a timestamp; b timestamp;
begin
  select min(fecha), max(fecha) into a, b from public.pos_lineas;
  if a is not null then perform public._pos_aplicar(a, b); end if;
end
$$;

-- resultado: como quedaron los productos del aperitivo
select p.producto, coalesce((select string_agg(i.nombre || ' [' || v.modo || ' ' || v.valor || ']', ' + ') from public.pos_vinculo v join public.insumos i on i.id = v.insumo_id where v.producto = p.producto), 'SIN VINCULAR') as descuenta
  from (select distinct producto from public.pos_lineas) p
 where public.normalizar_texto(p.producto) like '%APERITIVO%' order by 1;
