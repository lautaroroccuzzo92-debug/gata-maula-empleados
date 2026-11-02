-- Gata Maula: valores hora actuales (de tu planilla de sueldos de septiembre 2026) y usuario de Rocio.
--   * Valor hora: Manu 5900, Facu 5500, Basti 5150, Lucas 4900 (rigen desde el 1/9/2026, o sea que valen para octubre).
--     Rocio cobra lo mismo que Lucas (4900). Alex tambien cobra 4900.
--   * Usuario de Rocio: primero hay que crearlo en Supabase (Authentication > Users > Add user > Create new user,
--     email rocio@gatamaula.local, una contrasena, y tildar "Auto Confirm User"). Despues se corre este archivo.
--     Si todavia no esta creado, esa parte se saltea y no pasa nada: se puede volver a correr.
-- Es seguro correrlo mas de una vez.

insert into public.empleado_tarifas (empleado_id, desde, valor_hora)
select e.id, '2026-09-01'::date, v.valor
  from (values ('manu', 5900), ('facu', 5500), ('basti', 5150), ('lucas', 4900), ('rocio', 4900), ('alex', 4900)) as v(nombre, valor)
  join public.empleados e on translate(lower(e.nombre), 'í', 'i') = v.nombre
on conflict (empleado_id, desde) do update set valor_hora = excluded.valor_hora;

do $$
declare v_uid uuid;
begin
  select id into v_uid from auth.users where lower(email) = 'rocio@gatamaula.local';
  if v_uid is null then
    raise notice 'Todavia no existe el usuario rocio@gatamaula.local en Authentication. Crealo y volve a correr este archivo.';
    return;
  end if;
  insert into public.usuarios (id, nombre, rol) values (v_uid, 'Rocío', 'cocina') on conflict (id) do nothing;
  update public.empleados set usuario_id = v_uid where translate(lower(nombre), 'í', 'i') = 'rocio' and usuario_id is distinct from v_uid;
end
$$;

select e.nombre, u.nombre as usuario, (select t.valor_hora from public.empleado_tarifas t where t.empleado_id = e.id order by t.desde desc limit 1) as valor_hora
  from public.empleados e left join public.usuarios u on u.id = e.usuario_id
 where e.activo order by e.nombre;
