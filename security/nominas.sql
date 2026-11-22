begin;
create table public.nominas_documentos (
 id uuid primary key default gen_random_uuid(),
 empleado text not null references public.empleados_fichas(email),
 ano integer not null check(ano between 2000 and 2100),
 mes integer not null check(mes between 1 and 12),
 blob_key text not null unique check(blob_key ~ '^[a-f0-9]{32}/[0-9]{4}-[0-9]{2}\.pdf$'),
 sha256 text not null check(sha256 ~ '^[a-f0-9]{64}$'),
 creada_en timestamptz not null default now(),
 unique(empleado,ano,mes)
);
alter table public.nominas_documentos enable row level security;
create policy nominas_propias on public.nominas_documentos for select to authenticated using (
 (auth.jwt()->'app_metadata'->>'provider')='azure' and lower(auth.jwt()->>'email')=empleado and empleado like '%@xpecializa.com'
);
revoke all on public.nominas_documentos from anon, authenticated;
grant select on public.nominas_documentos to authenticated;
commit;
