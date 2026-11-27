begin;
create table public.registro_reaperturas (
 id bigint generated always as identity primary key,
 empleado text not null, ano integer not null, mes integer not null,
 motivo text not null, actor text not null, ocurrido_en timestamptz not null default now(),
 validacion_anterior timestamptz
);
alter table public.registro_reaperturas enable row level security;
revoke all on public.registro_reaperturas from public, anon, authenticated;
grant select on public.registro_reaperturas to authenticated;
create policy registro_reaperturas_lectura on public.registro_reaperturas for select to authenticated
 using (public.empleados_es_gestor() and public.vacaciones_es_responsable());

create function public.registro_proteger_validacion() returns trigger language plpgsql set search_path=public as $$
begin
 perform pg_advisory_xact_lock(hashtextextended(lower(new.empleado)||':'||new.ano||':'||new.mes,0));
 if current_user = 'authenticated' then
  if tg_op='UPDATE' and (old.empleado is distinct from new.empleado or old.ano is distinct from new.ano or old.mes is distinct from new.mes or old.dia is distinct from new.dia) then raise exception 'No se puede cambiar la identidad del registro'; end if;
  if tg_op='UPDATE' and coalesce(old.validado,false) then raise exception 'El mes está validado. Solicita su reapertura a Administración'; end if;
  if tg_op='INSERT' and exists(select 1 from public.registro_horario r where lower(r.empleado)=lower(new.empleado) and r.ano=new.ano and r.mes=new.mes and r.validado) then raise exception 'El mes está validado. Solicita su reapertura a Administración'; end if;
  if coalesce(new.validado,false) and (now() at time zone 'Europe/Madrid')::date < (make_date(new.ano,new.mes,1)+interval '1 month')::date then raise exception 'El mes solo puede validarse una vez finalizado'; end if;
 end if;
 return new;
end $$;
create trigger registro_proteger_validacion before insert or update on public.registro_horario for each row execute function public.registro_proteger_validacion();

create function public.registro_reabrir_mes(p_empleado text,p_ano integer,p_mes integer,p_motivo text) returns void
language plpgsql security definer set search_path=public as $$
declare v_actor text:=public.vacaciones_email(); v_fecha timestamptz;
begin
 if not public.empleados_es_gestor() or not public.vacaciones_es_responsable() then raise exception 'No autorizado'; end if;
 if p_mes not between 1 and 12 or p_ano not between 2000 and 2100 or length(trim(coalesce(p_motivo,'')))<5 or length(p_motivo)>500 then raise exception 'Indica un motivo de entre 5 y 500 caracteres'; end if;
 perform pg_advisory_xact_lock(hashtextextended(lower(p_empleado)||':'||p_ano||':'||p_mes,0));
 select max(fecha_validacion) into v_fecha from public.registro_horario where lower(empleado)=lower(p_empleado) and ano=p_ano and mes=p_mes and validado;
 if not exists(select 1 from public.registro_horario where lower(empleado)=lower(p_empleado) and ano=p_ano and mes=p_mes and validado) then raise exception 'Este mes no está validado'; end if;
 insert into public.registro_reaperturas(empleado,ano,mes,motivo,actor,validacion_anterior) values(lower(p_empleado),p_ano,p_mes,trim(p_motivo),v_actor,v_fecha);
 update public.registro_horario set validado=false,fecha_validacion=null where lower(empleado)=lower(p_empleado) and ano=p_ano and mes=p_mes and validado;
 insert into public.portal_eventos(actor_id,actor,accion,area,origen) values(auth.uid(),v_actor,'Mes reabierto','Actividad','base_datos');
end $$;
revoke all on function public.registro_reabrir_mes(text,integer,integer,text) from public,anon;
grant execute on function public.registro_reabrir_mes(text,integer,integer,text) to authenticated;
select cron.schedule('registro-reaperturas-retencion-12-meses','25 3 * * *', $cron$delete from public.registro_reaperturas where ocurrido_en < now() - interval '12 months'$cron$);
commit;
