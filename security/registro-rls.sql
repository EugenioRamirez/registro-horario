-- Aplicar solo después de verificar Microsoft como proveedor y probar la aplicación.
begin;
alter table public.registro_horario enable row level security;
drop policy if exists acceso_publico on public.registro_horario;
create policy registro_empleado_select on public.registro_horario for select to authenticated using (
  (auth.jwt() -> 'app_metadata' ->> 'provider') = 'azure'
  and (lower(empleado) = lower(auth.jwt() ->> 'email') or lower(auth.jwt() ->> 'email') in ('eugenio.ramirez@xpecializa.com','susan.matildo@xpecializa.com'))
);
create policy registro_empleado_insert on public.registro_horario for insert to authenticated with check (
  (auth.jwt() -> 'app_metadata' ->> 'provider') = 'azure' and lower(empleado) = lower(auth.jwt() ->> 'email') and lower(auth.jwt() ->> 'email') like '%@xpecializa.com'
);
create policy registro_empleado_update on public.registro_horario for update to authenticated using (
  (auth.jwt() -> 'app_metadata' ->> 'provider') = 'azure' and lower(empleado) = lower(auth.jwt() ->> 'email') and lower(auth.jwt() ->> 'email') like '%@xpecializa.com'
) with check (
  (auth.jwt() -> 'app_metadata' ->> 'provider') = 'azure' and lower(empleado) = lower(auth.jwt() ->> 'email') and lower(auth.jwt() ->> 'email') like '%@xpecializa.com'
);
commit;
