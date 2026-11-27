begin;
alter table public.vacaciones_imputaciones drop constraint vacaciones_imputaciones_check;
alter table public.vacaciones_imputaciones add constraint vacaciones_imputaciones_check check (
 ano_saldo=extract(year from fecha)::integer
 or (ano_saldo=extract(year from fecha)::integer-1 and extract(month from fecha)=1 and extract(day from fecha)<=30)
 or ano_saldo=extract(year from fecha)::integer+1
);
create table public.vacaciones_anticipos (
 id bigint generated always as identity primary key,
 empleado text not null, inicio date not null, fin date not null, max_dias integer not null check(max_dias between 1 and 366),
 motivo text not null, autorizado_por text not null, autorizado_en timestamptz not null default now(),
 unique(empleado,inicio,fin), check(fin>=inicio and extract(year from fin)-extract(year from inicio) between 0 and 1)
);
alter table public.vacaciones_anticipos enable row level security;
revoke all on public.vacaciones_anticipos from public,anon,authenticated;
grant select on public.vacaciones_anticipos to authenticated;
create policy vacaciones_anticipos_lectura on public.vacaciones_anticipos for select to authenticated using (
 empleado=public.vacaciones_email() or (public.empleados_es_gestor() and public.vacaciones_es_responsable())
);
create function public.vacaciones_autorizar_anticipo(p_empleado text,p_inicio date,p_fin date,p_dias integer,p_motivo text) returns void
language plpgsql security definer set search_path=public as $$
declare v_actor text:=public.vacaciones_email();
begin
 if not public.empleados_es_gestor() or not public.vacaciones_es_responsable() then raise exception 'No autorizado'; end if;
 if p_inicio is null or p_fin is null or p_fin<p_inicio or extract(year from p_fin)-extract(year from p_inicio) not between 0 and 1 or p_dias not between 1 and 366 or length(trim(coalesce(p_motivo,'')))<5 or length(p_motivo)>500 then raise exception 'Revisa las fechas, los días y el motivo'; end if;
 if not exists(select 1 from public.empleados_fichas where email=lower(trim(p_empleado))) then raise exception 'Empleado no encontrado'; end if;
 if exists(select 1 from public.vacaciones_solicitudes where empleado=lower(trim(p_empleado)) and inicio=p_inicio and fin=p_fin and estado in ('pendiente','aprobada')) then raise exception 'La solicitud ya existe'; end if;
 insert into public.vacaciones_anticipos(empleado,inicio,fin,max_dias,motivo,autorizado_por) values(lower(trim(p_empleado)),p_inicio,p_fin,p_dias,trim(p_motivo),v_actor);
 insert into public.portal_eventos(actor_id,actor,accion,area,origen) values(auth.uid(),v_actor,'Anticipo autorizado','Vacaciones','base_datos');
end $$;
revoke all on function public.vacaciones_autorizar_anticipo(text,date,date,integer,text) from public,anon;
grant execute on function public.vacaciones_autorizar_anticipo(text,date,date,integer,text) to authenticated;

create or replace function public.vacaciones_solicitar(p_inicio date,p_fin date,p_comentario text default '') returns bigint language plpgsql security definer set search_path=public as $$
declare v_email text:=public.vacaciones_email(); v_ano integer; v_primero integer; v_ultimo integer; v_fecha_alta date; v_fecha date; v_asignados numeric; v_inicial numeric; v_ocupados integer; v_libres integer; v_saldo_ano integer; v_total integer:=0; v_id bigint; v_inicio date; v_fin date; v_dias integer; v_anticipo integer; v_usados_anticipo integer;
begin
 if v_email is null then raise exception 'Cuenta corporativa requerida'; end if;
 if p_inicio is null or p_fin is null or p_fin<p_inicio or p_inicio<(now() at time zone 'Europe/Madrid')::date or p_fin-p_inicio>370 or extract(year from p_fin)-extract(year from p_inicio)>1 then raise exception 'Selecciona un periodo futuro de hasta dos años consecutivos'; end if;
 v_primero:=extract(year from p_inicio)::integer; v_ultimo:=extract(year from p_fin)::integer;
 select fecha_alta into v_fecha_alta from public.empleados_fichas where email=v_email;
 if v_fecha_alta is null then raise exception 'Tu ficha todavía no tiene fecha de incorporación'; end if;
 if p_inicio<v_fecha_alta then raise exception 'Las vacaciones no pueden comenzar antes de la incorporación'; end if;
 -- Serialize all entitlement years in a consistent order, including carryover.
 for v_ano in v_primero-1..v_ultimo+1 loop
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
  if v_asignados-v_inicial-v_ocupados<1 then
   select max_dias into v_anticipo from public.vacaciones_anticipos where empleado=v_email and inicio=p_inicio and fin=p_fin;
   select count(*) into v_usados_anticipo from public.vacaciones_imputaciones where solicitud_id=v_id and extract(year from fecha)=v_ano and ano_saldo=v_ano+1;
   if v_saldo_ano<>v_ano or v_anticipo is null or v_usados_anticipo>=v_anticipo then raise exception 'La solicitud supera tu saldo disponible de %',v_saldo_ano; end if;
   v_saldo_ano:=v_ano+1;
   select asignados,disfrutados_iniciales into v_asignados,v_inicial from public.vacaciones_saldos where empleado=v_email and ano=v_saldo_ano;
   if not found then raise exception 'Tu saldo de % todavía no está configurado',v_saldo_ano; end if;
   select count(*) into v_ocupados from public.vacaciones_imputaciones i join public.vacaciones_solicitudes s on s.id=i.solicitud_id where s.empleado=v_email and i.ano_saldo=v_saldo_ano and s.estado in ('pendiente','aprobada');
   if v_asignados-v_inicial-v_ocupados<1 then raise exception 'La solicitud supera tu saldo disponible de %',v_saldo_ano; end if;
  end if;
  insert into public.vacaciones_imputaciones(solicitud_id,fecha,ano_saldo) values(v_id,v_fecha,v_saldo_ano);
 end loop;
 for v_ano in v_primero..v_ultimo loop
  v_inicio:=greatest(p_inicio,make_date(v_ano,1,1)); v_fin:=least(p_fin,make_date(v_ano,12,31));
  select count(*) into v_dias from public.vacaciones_imputaciones where solicitud_id=v_id and extract(year from fecha)=v_ano;
  if v_dias>0 then insert into public.vacaciones_partes(solicitud_id,ano,inicio,fin,dias) values(v_id,v_ano,v_inicio,v_fin,v_dias); end if;
 end loop;
 return v_id;
end $$;

commit;
