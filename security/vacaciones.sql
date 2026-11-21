begin;
create table if not exists public.vacaciones_responsables (email text primary key check (email = lower(email)));
create table if not exists public.vacaciones_calendarios (ano integer primary key check (ano between 2000 and 2100), configurado boolean not null default false);
create table if not exists public.vacaciones_festivos (fecha date primary key);
create table if not exists public.vacaciones_saldos (
 empleado text not null check (empleado=lower(empleado) and empleado like '%@xpecializa.com'), ano integer not null,
 asignados numeric(6,2) not null check (asignados between 0 and 366), disfrutados_iniciales numeric(6,2) not null default 0 check (disfrutados_iniciales between 0 and asignados),
 primary key (empleado,ano));
create table if not exists public.vacaciones_solicitudes (
 id bigint generated always as identity primary key, empleado text not null, inicio date not null, fin date not null,
 dias integer not null check (dias>0), comentario text not null default '', estado text not null default 'pendiente' check (estado in ('pendiente','aprobada','rechazada','cancelada')),
 creada_en timestamptz not null default now(), resuelta_en timestamptz, resuelta_por text, check (fin>=inicio), check (extract(year from inicio)=extract(year from fin)));
create or replace function public.vacaciones_email() returns text language sql stable set search_path=public as $$
 select case when auth.jwt()->'app_metadata'->>'provider' = 'azure' and lower(auth.jwt()->>'email') like '%@xpecializa.com' then lower(auth.jwt()->>'email') end $$;
create or replace function public.vacaciones_es_responsable() returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.vacaciones_responsables where email=public.vacaciones_email()) $$;
alter table public.vacaciones_responsables enable row level security;
alter table public.vacaciones_saldos enable row level security;
alter table public.vacaciones_solicitudes enable row level security;
alter table public.vacaciones_calendarios enable row level security;
alter table public.vacaciones_festivos enable row level security;
create policy vacaciones_responsables_leer on public.vacaciones_responsables for select to authenticated using(email=public.vacaciones_email());
create policy vacaciones_saldos_leer on public.vacaciones_saldos for select to authenticated using(empleado=public.vacaciones_email() or public.vacaciones_es_responsable());
create policy vacaciones_solicitudes_leer on public.vacaciones_solicitudes for select to authenticated using(empleado=public.vacaciones_email() or public.vacaciones_es_responsable());
create policy vacaciones_calendarios_leer on public.vacaciones_calendarios for select to authenticated using(public.vacaciones_email() is not null);
create policy vacaciones_festivos_leer on public.vacaciones_festivos for select to authenticated using(public.vacaciones_email() is not null);
revoke all on public.vacaciones_responsables,public.vacaciones_saldos,public.vacaciones_solicitudes,public.vacaciones_calendarios,public.vacaciones_festivos from anon, authenticated;
grant select on public.vacaciones_responsables,public.vacaciones_saldos,public.vacaciones_solicitudes,public.vacaciones_calendarios,public.vacaciones_festivos to authenticated;
create or replace function public.vacaciones_fecha_alta(p_empleado text) returns date language plpgsql stable security definer set search_path=public as $$
declare resultado date;
begin
 if not public.vacaciones_es_responsable() then raise exception 'No autorizado'; end if;
 select fecha_alta into resultado from public.empleados_fichas where email=lower(trim(p_empleado));
 return resultado;
end $$;
revoke all on function public.vacaciones_fecha_alta(text) from public,anon;
grant execute on function public.vacaciones_fecha_alta(text) to authenticated;
create or replace function public.vacaciones_guardar_saldo(p_empleado text,p_ano integer,p_asignados numeric,p_inicial numeric) returns void language plpgsql security definer set search_path=public as $$
declare v_ocupados integer; v_fecha_alta date;
begin
 if not public.vacaciones_es_responsable() then raise exception 'No autorizado'; end if;
 perform 1 from public.vacaciones_saldos where empleado=lower(trim(p_empleado)) and ano=p_ano for update;
 select coalesce(sum(dias),0) into v_ocupados from public.vacaciones_solicitudes where empleado=lower(trim(p_empleado)) and extract(year from inicio)=p_ano and estado in ('pendiente','aprobada');
 if p_asignados < p_inicial + v_ocupados then raise exception 'El saldo no puede ser inferior a los días ya reservados y disfrutados'; end if;
 select fecha_alta into v_fecha_alta from public.empleados_fichas where email=lower(trim(p_empleado));
 if v_fecha_alta is null or v_fecha_alta > make_date(p_ano,12,31) then raise exception 'Configura primero la fecha de incorporación en la ficha del empleado'; end if;
 if lower(trim(p_empleado)) not like '%@xpecializa.com' or p_ano not between 2000 and 2100 or p_asignados not between 0 and 366 or p_inicial not between 0 and p_asignados then raise exception 'Datos de saldo no válidos'; end if;
 insert into public.vacaciones_saldos(empleado,ano,asignados,disfrutados_iniciales) values(lower(trim(p_empleado)),p_ano,p_asignados,p_inicial)
 on conflict(empleado,ano) do update set asignados=excluded.asignados,disfrutados_iniciales=excluded.disfrutados_iniciales;
end $$;
create or replace function public.vacaciones_guardar_calendario(p_ano integer,p_festivos date[]) returns void language plpgsql security definer set search_path=public as $$
begin
 if not public.vacaciones_es_responsable() then raise exception 'No autorizado'; end if;
 if p_ano not between 2000 and 2100 or exists(select 1 from unnest(p_festivos) f where extract(year from f) <> p_ano) then raise exception 'Las fechas deben corresponder al año seleccionado'; end if;
 insert into public.vacaciones_calendarios(ano,configurado) values(p_ano,false) on conflict(ano) do nothing;
 perform 1 from public.vacaciones_calendarios where ano=p_ano for update;
 if exists(select 1 from public.vacaciones_solicitudes where extract(year from inicio)=p_ano) then raise exception 'No se puede modificar un calendario con solicitudes registradas'; end if;
 delete from public.vacaciones_festivos where extract(year from fecha)=p_ano;
 insert into public.vacaciones_festivos(fecha) select distinct f from unnest(p_festivos) f;
 insert into public.vacaciones_calendarios(ano,configurado) values(p_ano,true) on conflict(ano) do update set configurado=true;
end $$;
create or replace function public.vacaciones_solicitar(p_inicio date,p_fin date,p_comentario text default '') returns bigint language plpgsql security definer set search_path=public as $$
declare v_email text:=public.vacaciones_email(); v_ano int; v_saldo public.vacaciones_saldos%rowtype; v_fecha_alta date; v_dias int; v_ocupados int; v_id bigint;
begin
 if v_email is null then raise exception 'Cuenta corporativa requerida'; end if;
 if p_inicio is null or p_fin is null or p_fin<p_inicio or p_inicio < (now() at time zone 'Europe/Madrid')::date or extract(year from p_inicio)<>extract(year from p_fin) then raise exception 'Selecciona fechas futuras del mismo año'; end if;
 v_ano:=extract(year from p_inicio)::int;
 select * into v_saldo from public.vacaciones_saldos where empleado=v_email and ano=v_ano for update;
 if not found then raise exception 'Tu saldo anual todavía no está configurado'; end if;
 select fecha_alta into v_fecha_alta from public.empleados_fichas where email=v_email;
 if v_fecha_alta is null then raise exception 'Tu ficha todavía no tiene fecha de incorporación'; end if;
 if p_inicio < v_fecha_alta then raise exception 'Las vacaciones no pueden comenzar antes de la incorporación'; end if;
 perform 1 from public.vacaciones_calendarios where ano=v_ano and configurado for share;
 if not found then raise exception 'El calendario de festivos todavía no está configurado'; end if;
 if exists(select 1 from public.vacaciones_solicitudes where empleado=v_email and estado in ('pendiente','aprobada') and daterange(inicio,fin,'[]') && daterange(p_inicio,p_fin,'[]')) then raise exception 'Ya existe una solicitud para esas fechas'; end if;
 select count(*) into v_dias from generate_series(p_inicio::timestamp,p_fin::timestamp,interval '1 day') d where extract(isodow from d)<6 and not exists(select 1 from public.vacaciones_festivos f where f.fecha=d::date);
 if v_dias=0 then raise exception 'El intervalo no contiene días laborables'; end if;
 select coalesce(sum(dias),0) into v_ocupados from public.vacaciones_solicitudes where empleado=v_email and extract(year from inicio)=v_ano and estado in ('pendiente','aprobada');
 if v_dias > v_saldo.asignados-v_saldo.disfrutados_iniciales-v_ocupados then raise exception 'La solicitud supera tu saldo disponible'; end if;
 insert into public.vacaciones_solicitudes(empleado,inicio,fin,dias,comentario) values(v_email,p_inicio,p_fin,v_dias,left(coalesce(p_comentario,''),1000)) returning id into v_id;
 return v_id;
end $$;
create or replace function public.vacaciones_resolver(p_id bigint,p_estado text) returns void language plpgsql security definer set search_path=public as $$
declare r public.vacaciones_solicitudes%rowtype; v_email text:=public.vacaciones_email();
begin
 select * into r from public.vacaciones_solicitudes where id=p_id for update;
 if not found or r.estado<>'pendiente' then raise exception 'La solicitud ya no está pendiente'; end if;
 if p_estado='cancelada' then
   if r.empleado<>v_email or v_email is null then raise exception 'No autorizado'; end if;
 elsif p_estado in ('aprobada','rechazada') then
   if not public.vacaciones_es_responsable() or r.empleado=v_email then raise exception 'No puedes resolver esta solicitud'; end if;
 else raise exception 'Estado no válido'; end if;
 update public.vacaciones_solicitudes set estado=p_estado,resuelta_por=v_email,resuelta_en=now() where id=p_id;
end $$;
revoke all on function public.vacaciones_guardar_saldo(text,integer,numeric,numeric),public.vacaciones_guardar_calendario(integer,date[]),public.vacaciones_solicitar(date,date,text),public.vacaciones_resolver(bigint,text) from public,anon;
grant execute on function public.vacaciones_guardar_saldo(text,integer,numeric,numeric),public.vacaciones_guardar_calendario(integer,date[]),public.vacaciones_solicitar(date,date,text),public.vacaciones_resolver(bigint,text) to authenticated;
commit;

