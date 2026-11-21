begin;
create table public.empleados_gestores (email text primary key check (email=lower(email)));
create table public.empleados_fichas (
 email text primary key check (email=lower(email) and email like '%@xpecializa.com'),
 nombre text not null check (length(trim(nombre)) between 1 and 200),
 fecha_alta date not null,
 actualizado_en timestamptz not null default now(),
 actualizado_por text not null
);
create function public.empleados_email() returns text language sql stable set search_path=public as $$
 select case when auth.jwt()->'app_metadata'->>'provider'='azure' and lower(auth.jwt()->>'email') like '%@xpecializa.com' then lower(auth.jwt()->>'email') end $$;
create function public.empleados_es_gestor() returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.empleados_gestores where email=public.empleados_email()) $$;
alter table public.empleados_gestores enable row level security;
alter table public.empleados_fichas enable row level security;
create policy empleados_gestores_lectura on public.empleados_gestores for select to authenticated using (email=public.empleados_email());
create policy empleados_fichas_lectura on public.empleados_fichas for select to authenticated using (email=public.empleados_email() or public.empleados_es_gestor());
revoke all on public.empleados_gestores,public.empleados_fichas from anon, authenticated;
grant select on public.empleados_gestores,public.empleados_fichas to authenticated;
create function public.empleados_guardar_ficha(p_email text,p_nombre text,p_fecha_alta date) returns void language plpgsql security definer set search_path=public as $$
begin
 if not public.empleados_es_gestor() then raise exception 'No autorizado'; end if;
 if p_email is null or lower(trim(p_email)) not like '%@xpecializa.com' or p_nombre is null or length(trim(p_nombre)) not between 1 and 200 or p_fecha_alta is null then raise exception 'Datos de ficha no válidos'; end if;
 insert into public.empleados_fichas(email,nombre,fecha_alta,actualizado_por) values(lower(trim(p_email)),trim(p_nombre),p_fecha_alta,public.empleados_email())
 on conflict(email) do update set nombre=excluded.nombre,fecha_alta=excluded.fecha_alta,actualizado_en=now(),actualizado_por=excluded.actualizado_por;
end $$;
revoke all on function public.empleados_guardar_ficha(text,text,date) from public,anon;
grant execute on function public.empleados_guardar_ficha(text,text,date) to authenticated;
commit;
