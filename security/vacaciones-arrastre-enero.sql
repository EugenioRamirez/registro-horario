begin;
-- Preserve calendar-year parts and record separately the entitlement used for each working day.
create table public.vacaciones_imputaciones (
 solicitud_id bigint not null references public.vacaciones_solicitudes(id) on delete cascade,
 fecha date not null,
 ano_saldo integer not null,
 primary key (solicitud_id, fecha),
 check (ano_saldo=extract(year from fecha)::integer or (ano_saldo=extract(year from fecha)::integer-1 and extract(month from fecha)=1 and extract(day from fecha)<=30))
);
alter table public.vacaciones_imputaciones enable row level security;
create policy vacaciones_imputaciones_leer on public.vacaciones_imputaciones for select to authenticated using (exists(select 1 from public.vacaciones_solicitudes s where s.id=solicitud_id));
revoke all on public.vacaciones_imputaciones from public, anon, authenticated;
grant select on public.vacaciones_imputaciones to authenticated;
-- Never silently invent dates for historical totals.
do $$ begin
 if exists (select 1 from public.vacaciones_partes p where p.dias<>(select count(*) from generate_series(p.inicio::timestamp,p.fin::timestamp,interval '1 day') d where extract(isodow from d)<6 and not exists(select 1 from public.vacaciones_festivos f where f.fecha=d::date))) then
  raise exception 'Hay solicitudes históricas que no coinciden con el calendario; revisar antes de migrar';
 end if;
end $$;
insert into public.vacaciones_imputaciones(solicitud_id,fecha,ano_saldo)
select p.solicitud_id,d::date,p.ano from public.vacaciones_partes p cross join lateral generate_series(p.inicio::timestamp,p.fin::timestamp,interval '1 day') d
where extract(isodow from d)<6 and not exists(select 1 from public.vacaciones_festivos f where f.fecha=d::date);
create view public.vacaciones_imputaciones_resumen with (security_invoker=true) as
select solicitud_id, ano_saldo as ano, min(fecha) as inicio, max(fecha) as fin, count(*)::integer as dias
from public.vacaciones_imputaciones group by solicitud_id,ano_saldo;
grant select on public.vacaciones_imputaciones_resumen to authenticated;
create or replace function public.vacaciones_solicitar(p_inicio date,p_fin date,p_comentario text default '') returns bigint language plpgsql security definer set search_path=public as $$
declare v_email text:=public.vacaciones_email(); v_ano integer; v_primero integer; v_ultimo integer; v_fecha_alta date; v_fecha date; v_asignados numeric; v_inicial numeric; v_ocupados integer; v_libres integer; v_saldo_ano integer; v_total integer:=0; v_id bigint; v_inicio date; v_fin date; v_dias integer;
begin
 if v_email is null then raise exception 'Cuenta corporativa requerida'; end if;
 if p_inicio is null or p_fin is null or p_fin<p_inicio or p_inicio<(now() at time zone 'Europe/Madrid')::date or p_fin-p_inicio>370 or extract(year from p_fin)-extract(year from p_inicio)>1 then raise exception 'Selecciona un periodo futuro de hasta dos años consecutivos'; end if;
 v_primero:=extract(year from p_inicio)::integer; v_ultimo:=extract(year from p_fin)::integer;
 select fecha_alta into v_fecha_alta from public.empleados_fichas where email=v_email;
 if v_fecha_alta is null then raise exception 'Tu ficha todavía no tiene fecha de incorporación'; end if;
 if p_inicio<v_fecha_alta then raise exception 'Las vacaciones no pueden comenzar antes de la incorporación'; end if;
 -- Serialize all entitlement years in a consistent order, including carryover.
 for v_ano in v_primero-1..v_ultimo loop
  perform 1 from public.vacaciones_saldos where empleado=v_email and ano=v_ano for update;
 end loop;
 for v_ano in v_primero..v_ultimo loop
  perform 1 from public.vacaciones_calendarios where ano=v_ano and configurado for share;
  if not found then raise exception 'El calendario de festivos de % todavía no está configurado',v_ano; end if;
 end loop;
 if exists(select 1 from public.vacaciones_solicitudes where empleado=v_email and estado in ('pendiente','aprobada') and daterange(inicio,fin,'[]') && daterange(p_inicio,p_fin,'[]')) then raise exception 'Ya existe una solicitud para esas fechas'; end if;
 select count(*) into v_total from generate_series(p_inicio::timestamp,p_fin::timestamp,interval '1 day') d where extract(isodow from d)<6 and not exists(select 1 from public.vacaciones_festivos f where f.fecha=d::date);
 if v_total=0 then raise exception 'El intervalo no contiene días laborables'; end if;
 insert into public.vacaciones_solicitudes(empleado,inicio,fin,dias,comentario) values(v_email,p_inicio,p_fin,v_total,left(coalesce(p_comentario,''),1000)) returning id into v_id;
 for v_fecha in select d::date from generate_series(p_inicio::timestamp,p_fin::timestamp,interval '1 day') d where extract(isodow from d)<6 and not exists(select 1 from public.vacaciones_festivos f where f.fecha=d::date) order by d loop
  v_ano:=extract(year from v_fecha)::integer;
  v_saldo_ano:=v_ano;
  if extract(month from v_fecha)=1 and extract(day from v_fecha)<=30 and v_fecha_alta<make_date(v_ano,1,1) then
   select asignados,disfrutados_iniciales into v_asignados,v_inicial from public.vacaciones_saldos where empleado=v_email and ano=v_ano-1;
   if not found then raise exception 'Tu saldo de % debe configurarse antes de solicitar vacaciones en enero',v_ano-1; end if;
   select count(*) into v_ocupados from public.vacaciones_imputaciones i join public.vacaciones_solicitudes s on s.id=i.solicitud_id where s.empleado=v_email and i.ano_saldo=v_ano-1 and s.estado in ('pendiente','aprobada');
   if v_asignados-v_inicial-v_ocupados>0 then v_saldo_ano:=v_ano-1; end if;
  end if;
  select asignados,disfrutados_iniciales into v_asignados,v_inicial from public.vacaciones_saldos where empleado=v_email and ano=v_saldo_ano;
  if not found then raise exception 'Tu saldo de % todavía no está configurado',v_saldo_ano; end if;
  select count(*) into v_ocupados from public.vacaciones_imputaciones i join public.vacaciones_solicitudes s on s.id=i.solicitud_id where s.empleado=v_email and i.ano_saldo=v_saldo_ano and s.estado in ('pendiente','aprobada');
  if v_asignados-v_inicial-v_ocupados<1 then raise exception 'La solicitud supera tu saldo disponible de %',v_saldo_ano; end if;
  insert into public.vacaciones_imputaciones(solicitud_id,fecha,ano_saldo) values(v_id,v_fecha,v_saldo_ano);
 end loop;
 for v_ano in v_primero..v_ultimo loop
  v_inicio:=greatest(p_inicio,make_date(v_ano,1,1)); v_fin:=least(p_fin,make_date(v_ano,12,31));
  select count(*) into v_dias from public.vacaciones_imputaciones where solicitud_id=v_id and extract(year from fecha)=v_ano;
  if v_dias>0 then insert into public.vacaciones_partes(solicitud_id,ano,inicio,fin,dias) values(v_id,v_ano,v_inicio,v_fin,v_dias); end if;
 end loop;
 return v_id;
end $$;
create or replace function public.vacaciones_guardar_saldo(p_empleado text,p_ano integer,p_asignados numeric,p_inicial numeric,p_confirmado boolean) returns void language plpgsql security definer set search_path=public as $$
declare v_ocupados integer; v_fecha_alta date;
begin
 if not public.vacaciones_es_responsable() then raise exception 'No autorizado'; end if;
 perform 1 from public.vacaciones_saldos where empleado=lower(trim(p_empleado)) and ano=p_ano for update;
 select count(*) into v_ocupados from public.vacaciones_imputaciones i join public.vacaciones_solicitudes s on s.id=i.solicitud_id where s.empleado=lower(trim(p_empleado)) and i.ano_saldo=p_ano and s.estado in ('pendiente','aprobada');
 if p_asignados is null or p_inicial is null or p_asignados<>floor(p_asignados) or p_inicial<>floor(p_inicial) then raise exception 'Los días deben ser números enteros'; end if;
 if p_asignados<p_inicial+v_ocupados then raise exception 'El saldo no puede ser inferior a los días ya reservados y disfrutados'; end if;
 select fecha_alta into v_fecha_alta from public.empleados_fichas where email=lower(trim(p_empleado));
 if v_fecha_alta is null or v_fecha_alta>make_date(p_ano,12,31) then raise exception 'Configura primero la fecha de incorporación en la ficha del empleado'; end if;
 if lower(trim(p_empleado)) not like '%@xpecializa.com' or p_ano not between 2000 and 2100 or p_asignados not between 0 and 366 or p_inicial not between 0 and p_asignados then raise exception 'Datos de saldo no válidos'; end if;
 insert into public.vacaciones_saldos(empleado,ano,asignados,disfrutados_iniciales,provisional) values(lower(trim(p_empleado)),p_ano,p_asignados,p_inicial,not coalesce(p_confirmado,false)) on conflict(empleado,ano) do update set asignados=excluded.asignados,disfrutados_iniciales=excluded.disfrutados_iniciales,provisional=excluded.provisional;
end $$;
commit;
