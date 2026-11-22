begin;
-- Restringe el piloto sin eliminar notas ni justificantes existentes.
create or replace function public.gastos_piloto_autorizado() returns boolean
language sql stable set search_path=public as $$
  select coalesce(public.empleados_email() in (
    'eugenio.ramirez@xpecializa.com',
    'susan.matildo@xpecializa.com',
    'joseignacio.hernandez@xpecializa.com'
  ), false)
$$;
revoke all on function public.gastos_piloto_autorizado() from public,anon;
grant execute on function public.gastos_piloto_autorizado() to authenticated;
create policy gastos_piloto_notas on public.gastos_notas as restrictive
for select to authenticated using (public.gastos_piloto_autorizado());
create policy gastos_piloto_pdf_lectura on storage.objects as restrictive
for select to authenticated using (bucket_id <> 'gastos-justificantes' or public.gastos_piloto_autorizado());
create policy gastos_piloto_pdf_subida on storage.objects as restrictive
for insert to authenticated with check (bucket_id <> 'gastos-justificantes' or public.gastos_piloto_autorizado());
create function public.gastos_piloto_controlar_escritura() returns trigger
language plpgsql set search_path=public as $$
begin
  if not public.gastos_piloto_autorizado() then
    raise exception 'Las notas de gastos están disponibles para el grupo piloto.';
  end if;
  return new;
end $$;
create trigger gastos_piloto_escritura before insert or update on public.gastos_notas
for each row execute function public.gastos_piloto_controlar_escritura();
commit;
