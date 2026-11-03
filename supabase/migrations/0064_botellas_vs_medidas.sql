-- Gata Maula: corrige como se descuentan las botellas de vermut.
--   * "MEDIDA X" (el vaso)                           -> descuenta una medida (ml del vaso + merma) y la soda por ticket
--   * "X VERMUT" / "BOTELLA X" (para llevar)         -> descuenta 1 botella y nada mas
--   * "X + SIFON DE SODA + CITRICOS" / "BOTELLA X + HIELO + SODA" (para tomar en el local) -> 1 botella + 1 soda grande (SODA 1250 CC)
--   * "VERMUT GATA MAULA" es la botella de Gata Maula (no la medida): 1 botella; con "+ SIFON SODA + CITRICO", 1 botella + 1 soda grande
-- La 0061 trataba como medida a los que no empezaban con "MEDIDA"; aca se corrige y se vuelven a vincular.
-- Correr UNA vez en el SQL Editor (despues de la 0063). Es seguro correrlo mas de una vez.

-- ============================================================ vinculacion automatica corregida
create or replace function public._pos_autovincular() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  r record; nom text; v_ins uuid; n_v int := 0; n_o int := 0; n_p int := 0;
  v_gm uuid := (select valor::uuid from public.pos_config where clave = 'insumo_gm');
  v_soda uuid := (select valor::uuid from public.pos_config where clave = 'insumo_soda');
  v_grande uuid := (select valor::uuid from public.pos_config where clave = 'insumo_soda_grande');
begin
  for r in select p.producto, p.familia from (select producto, max(familia) as familia from public.pos_lineas group by producto) p
            where not exists (select 1 from public.pos_vinculo v where v.producto = p.producto)
              and not exists (select 1 from public.pos_producto x where x.producto = p.producto and x.omitir is not null)
  loop
    nom := public.normalizar_texto(r.producto);
    v_ins := null;
    if nom like '%HAPPY HOUR%' then
      insert into public.pos_producto (producto, familia, omitir, nota) values (r.producto, r.familia, 'sin_stock', 'Las 3 medidas se descuentan cuando se usa cada Gata Coin')
        on conflict (producto) do update set omitir = excluded.omitir, nota = excluded.nota;
      n_o := n_o + 1;
    elsif (nom like '%GATA COIN%' or nom ~ '^GM +MEDIDA') and v_gm is not null then
      insert into public.pos_vinculo (producto, insumo_id, modo, valor, lleva_soda) values (r.producto, v_gm, 'medida', 1, true) on conflict (producto, insumo_id) do nothing;
      n_v := n_v + 1;
    elsif nom like '%PINGUINO%' and v_gm is not null then
      insert into public.pos_vinculo (producto, insumo_id, modo, valor, lleva_soda) values (r.producto, v_gm, 'ml', 740, false) on conflict (producto, insumo_id) do nothing;
      if v_soda is not null then
        insert into public.pos_vinculo (producto, insumo_id, modo, valor, lleva_soda) values (r.producto, v_soda, 'unidad', 1, false) on conflict (producto, insumo_id) do nothing;
      end if;
      n_v := n_v + 1;
    elsif nom like 'SIFONCITO%' and v_soda is not null then
      insert into public.pos_vinculo (producto, insumo_id, modo, valor, lleva_soda) values (r.producto, v_soda, 'unidad', 1, false) on conflict (producto, insumo_id) do nothing;
      n_v := n_v + 1;
    elsif nom ~ '^MEDIDD?A ' then
      v_ins := public._pos_match_insumo(r.producto, array['vermut', 'cerveza y sin alcohol']);
      if v_ins is not null then
        insert into public.pos_vinculo (producto, insumo_id, modo, valor, lleva_soda) values (r.producto, v_ins, 'medida', 1, nom not like '%SIN ALCOHOL%') on conflict (producto, insumo_id) do nothing;
        n_v := n_v + 1;
      else n_p := n_p + 1; end if;
    elsif nom like 'BOTELLA %' or nom like 'VERMUT GATA MAULA%' or coalesce(r.familia, '') in ('VERMOUTH', 'MEDIDA VERMUT') then
      -- botella entera (para llevar, o para tomar en el local si el nombre dice soda/sifon)
      v_ins := public._pos_match_insumo(r.producto, array['vermut', 'cerveza y sin alcohol']);
      if v_ins is not null then
        insert into public.pos_vinculo (producto, insumo_id, modo, valor, lleva_soda) values (r.producto, v_ins, 'unidad', 1, false) on conflict (producto, insumo_id) do nothing;
        if nom ~ '(SODA|SIFON)' and v_grande is not null then
          insert into public.pos_vinculo (producto, insumo_id, modo, valor, lleva_soda) values (r.producto, v_grande, 'unidad', 1, false) on conflict (producto, insumo_id) do nothing;
        end if;
        n_v := n_v + 1;
      else n_p := n_p + 1; end if;
    elsif coalesce(r.familia, '') = 'AGUAS, GASEOSAS Y CERVEZAS' then
      v_ins := public._pos_match_insumo(r.producto, array['cerveza y sin alcohol']);
      if v_ins is not null then
        insert into public.pos_vinculo (producto, insumo_id, modo, valor, lleva_soda) values (r.producto, v_ins, 'unidad', 1, false) on conflict (producto, insumo_id) do nothing;
        n_v := n_v + 1;
      else n_p := n_p + 1; end if;
    else
      insert into public.pos_producto (producto, familia, omitir, nota) values (r.producto, r.familia, 'comida', 'Comida: se descuenta en la etapa de recetas')
        on conflict (producto) do update set omitir = excluded.omitir, nota = excluded.nota;
      n_o := n_o + 1;
    end if;
  end loop;
  return jsonb_build_object('vinculados', n_v, 'no_descuentan', n_o, 'sin_encontrar', n_p);
end;
$$;
revoke all on function public._pos_autovincular() from public;

-- ============================================================ extras (aperitivo, fernet, soda de las botellas)
create or replace function public._pos_soda_aperitivo() returns int
language plpgsql security definer set search_path = public as $$
declare
  v_grande uuid := (select valor::uuid from public.pos_config where clave = 'insumo_soda_grande');
  v_chica uuid := (select valor::uuid from public.pos_config where clave = 'insumo_soda');
  v_pepsi uuid := (select valor::uuid from public.pos_config where clave = 'insumo_pepsi');
  n int := 0; r record;
begin
  if v_grande is not null then
    -- aperitivo sin alcohol: 115 ml de soda grande (y nada de soda por ticket)
    for r in select distinct producto from public.pos_vinculo where public.normalizar_texto(producto) like 'MEDIDA APERITIVO%' loop
      if v_chica is not null then delete from public.pos_vinculo where producto = r.producto and insumo_id = v_chica; end if;
      update public.pos_vinculo set lleva_soda = false where producto = r.producto;
      insert into public.pos_vinculo (producto, insumo_id, modo, valor, lleva_soda) values (r.producto, v_grande, 'ml', 115, false)
        on conflict (producto, insumo_id) do update set modo = 'ml', valor = 115, lleva_soda = false;
      n := n + 1;
    end loop;
    -- botellas de vermut: soda grande solo si se venden "para tomar en el local" (el nombre dice soda o sifon)
    delete from public.pos_vinculo v
     where v.insumo_id = v_grande and v.modo = 'unidad'
       and public.normalizar_texto(v.producto) !~ '(SODA|SIFON)';
    for r in select distinct v.producto from public.pos_vinculo v join public.insumos i on i.id = v.insumo_id
              where v.modo = 'unidad' and i.subcategoria::text = 'vermut' and v.insumo_id <> v_grande
                and public.normalizar_texto(v.producto) ~ '(SODA|SIFON)' and public.normalizar_texto(v.producto) !~ '^MEDIDD?A ' loop
      insert into public.pos_vinculo (producto, insumo_id, modo, valor, lleva_soda) values (r.producto, v_grande, 'unidad', 1, false)
        on conflict (producto, insumo_id) do update set modo = 'unidad', valor = 1, lleva_soda = false;
      n := n + 1;
    end loop;
  end if;
  -- fernet sin alcohol: 1 Pepsi entera
  if v_pepsi is not null then
    for r in select distinct producto from public.pos_vinculo where public.normalizar_texto(producto) like 'MEDIDA FERNET%' and insumo_id <> v_pepsi loop
      update public.pos_vinculo set lleva_soda = false where producto = r.producto;
      insert into public.pos_vinculo (producto, insumo_id, modo, valor, lleva_soda) values (r.producto, v_pepsi, 'unidad', 1, false)
        on conflict (producto, insumo_id) do update set modo = 'unidad', valor = 1, lleva_soda = false;
      n := n + 1;
    end loop;
    for r in select p.producto from (select distinct producto from public.pos_lineas) p
              where public.normalizar_texto(p.producto) = 'PEPSI 354CC'
                and not exists (select 1 from public.pos_vinculo v where v.producto = p.producto)
                and not exists (select 1 from public.pos_producto x where x.producto = p.producto and x.omitir is not null) loop
      insert into public.pos_vinculo (producto, insumo_id, modo, valor, lleva_soda) values (r.producto, v_pepsi, 'unidad', 1, false) on conflict (producto, insumo_id) do nothing;
      n := n + 1;
    end loop;
  end if;
  return n;
end;
$$;
revoke all on function public._pos_soda_aperitivo() from public;

-- ============================================================ corregir lo que la 0061 vinculo mal
-- productos que no empiezan con "MEDIDA" y quedaron como medida (eran botellas); se desvinculan y se vuelven a vincular bien
delete from public.pos_vinculo v
 where v.modo = 'medida'
   and public.normalizar_texto(v.producto) !~ '^MEDIDD?A '
   and public.normalizar_texto(v.producto) not like '%GATA COIN%'
   and public.normalizar_texto(v.producto) !~ '^GM +MEDIDA';

select public._pos_autovincular() as autovinculacion;
select public._pos_soda_aperitivo() as vinculos_extra;
do $$
declare a timestamp; b timestamp;
begin
  select min(fecha), max(fecha) into a, b from public.pos_lineas;
  if a is not null then perform public._pos_aplicar(a, b); end if;
end
$$;

-- ============================================================ resultado: vermut (botellas y medidas) y como descuenta cada uno
select p.familia, p.producto, coalesce((select string_agg(i.nombre || ' [' || v.modo || ' ' || v.valor || ']', ' + ' order by v.id) from public.pos_vinculo v join public.insumos i on i.id = v.insumo_id where v.producto = p.producto),
       (select 'NO DESCUENTA: ' || x.omitir from public.pos_producto x where x.producto = p.producto and x.omitir is not null), 'SIN VINCULAR') as descuenta
  from (select producto, max(familia) as familia from public.pos_lineas group by producto) p
 where p.familia in ('VERMOUTH', 'MEDIDA VERMUT') order by 1, 2;
