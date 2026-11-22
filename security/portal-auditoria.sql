begin;
-- Eventos de auditoría: solo identidad, momento, área y acción; no almacena contenido.
create extension if not exists pg_cron with schema pg_catalog;
create table public.portal_eventos (
 id bigint generated always as identity primary key,
 ocurrido_en timestamptz not null default clock_timestamp(),
 actor_id uuid not null,
 actor text not null,
 accion text not null,
 area text not null,
 origen text not null check (origen in ('portal','base_datos'))
);
create index portal_eventos_fecha_idx on public.portal_eventos (ocurrido_en desc,id desc);
create index portal_eventos_actor_fecha_idx on public.portal_eventos (actor,ocurrido_en desc);
alter table public.portal_eventos enable row level security;
revoke all on public.portal_eventos from public,anon,authenticated;
grant select on public.portal_eventos to authenticated;
create policy portal_eventos_admin_lectura on public.portal_eventos for select to authenticated using (
 public.empleados_es_gestor() and public.empleados_email() in ('eugenio.ramirez@xpecializa.com','susan.matildo@xpecializa.com')
);
create function public.portal_evento(p_accion text,p_area text) returns void
language plpgsql security definer set search_path=public as $$
declare v_email text:=public.empleados_email();
begin
 if auth.uid() is null or v_email is null then raise exception 'No autorizado'; end if;
 if not ((p_accion='Acceso al portal' and p_area='Portal') or
         (p_accion='Consulta' and p_area in ('Inicio','Actividad','Mi ficha','Vacaciones','Nóminas','Gastos','Administración')) or
         (p_accion='Nómina abierta' and p_area='Nóminas') or
         (p_accion='Registro guardado' and p_area='Actividad')) then raise exception 'Evento no válido'; end if;
 insert into public.portal_eventos(actor_id,actor,accion,area,origen) values(auth.uid(),v_email,p_accion,p_area,'portal');
end $$;
revoke all on function public.portal_evento(text,text) from public,anon;
grant execute on function public.portal_evento(text,text) to authenticated;
create function public.portal_evento_cambios() returns trigger
language plpgsql security definer set search_path=public as $$
declare v_actor text:=public.empleados_email(); v_action text; v_area text;
begin
 if auth.uid() is null or v_actor is null then return new; end if;
 if tg_table_name='vacaciones_solicitudes' then
  v_area:='Vacaciones';
  if tg_op='INSERT' then v_action:='Solicitud enviada';
  elsif new.estado is distinct from old.estado then v_action:=case new.estado when 'aprobada' then 'Solicitud aprobada' when 'rechazada' then 'Solicitud rechazada' when 'cancelada' then 'Solicitud cancelada' end; end if;
 elsif tg_table_name='gastos_notas' then
  v_area:='Gastos';
  if tg_op='INSERT' then v_action:='Borrador creado';
  elsif new.estado is distinct from old.estado then v_action:=case new.estado when 'pendiente' then 'Nota enviada' when 'devuelta' then 'Nota devuelta' when 'aprobada' then 'Nota aprobada' when 'abonada' then 'Nota abonada' end; end if;
 end if;
 if v_action is not null then insert into public.portal_eventos(actor_id,actor,accion,area,origen) values(auth.uid(),v_actor,v_action,v_area,'base_datos'); end if;
 return new;
end $$;
revoke all on function public.portal_evento_cambios() from public,anon,authenticated;
create trigger portal_eventos_vacaciones after insert or update on public.vacaciones_solicitudes for each row execute function public.portal_evento_cambios();
create trigger portal_eventos_gastos after insert or update on public.gastos_notas for each row execute function public.portal_evento_cambios();
select cron.schedule('portal-eventos-retencion-12-meses','15 3 * * *', $cron$delete from public.portal_eventos where ocurrido_en < now() - interval '12 months'$cron$);
commit;
