begin;
create table if not exists public.portal_notificaciones (
 id bigint generated always as identity primary key,
 tipo text not null check(tipo in ('vacaciones','gastos')),
 referencia text not null,
 destinatario text not null check(destinatario = lower(destinatario) and destinatario like '%@xpecializa.com'),
 datos jsonb not null,
 estado text not null default 'pendiente' check(estado in ('pendiente','enviando','aceptada','incierta','error')),
 creada_en timestamptz not null default now(), actualizada_en timestamptz not null default now(),
 unique(tipo,referencia)
);
alter table public.portal_notificaciones enable row level security;
revoke all on public.portal_notificaciones from public, anon, authenticated;
create or replace function public.portal_encolar_aprobacion() returns trigger
language plpgsql security definer set search_path=public as $$
begin
 if old.estado <> 'aprobada' and new.estado = 'aprobada' then
  if tg_table_name='vacaciones_solicitudes' then
   insert into public.portal_notificaciones(tipo,referencia,destinatario,datos)
   values('vacaciones',new.id::text,lower(new.empleado),jsonb_build_object('inicio',new.inicio,'fin',new.fin,'dias',new.dias)) on conflict do nothing;
  elsif tg_table_name='gastos_notas' then
   insert into public.portal_notificaciones(tipo,referencia,destinatario,datos)
   values('gastos',new.id::text,lower(new.empleado),jsonb_build_object('ano',new.ano,'mes',new.mes,'total',new.total)) on conflict do nothing;
  end if;
 end if;
 return new;
end $$;
revoke all on function public.portal_encolar_aprobacion() from public, anon, authenticated;
drop trigger if exists portal_notificar_vacaciones on public.vacaciones_solicitudes;
create trigger portal_notificar_vacaciones after update of estado on public.vacaciones_solicitudes for each row execute function public.portal_encolar_aprobacion();
drop trigger if exists portal_notificar_gastos on public.gastos_notas;
create trigger portal_notificar_gastos after update of estado on public.gastos_notas for each row execute function public.portal_encolar_aprobacion();
create table if not exists public.portal_notificaciones_config (id boolean primary key default true check(id), token_sha256 text not null check(token_sha256 ~ '^[0-9a-f]{64}$'));
alter table public.portal_notificaciones_config enable row level security;
revoke all on public.portal_notificaciones_config from public, anon, authenticated;
create or replace function public.portal_notificaciones_verificar(p_secreto text) returns boolean
language sql stable security definer set search_path=public,extensions as $$
 select coalesce((select token_sha256=encode(digest(p_secreto,'sha256'),'hex') from public.portal_notificaciones_config where id=true),false)
$$;
revoke all on function public.portal_notificaciones_verificar(text) from public, anon, authenticated;
create or replace function public.portal_notificaciones_tomar(p_secreto text) returns setof public.portal_notificaciones
language plpgsql security definer set search_path=public as $$
begin
 if not public.portal_notificaciones_verificar(p_secreto) then raise exception 'No autorizado'; end if;
 return query update public.portal_notificaciones n set estado='enviando',actualizada_en=now()
 where n.id=(select id from public.portal_notificaciones where estado='pendiente' order by id for update skip locked limit 1)
 returning n.*;
end $$;
create or replace function public.portal_notificaciones_finalizar(p_id bigint,p_estado text,p_secreto text) returns void
language plpgsql security definer set search_path=public as $$
begin
 if not public.portal_notificaciones_verificar(p_secreto) then raise exception 'No autorizado'; end if;
 if p_estado not in ('aceptada','incierta','error') then raise exception 'Estado no válido'; end if;
 update public.portal_notificaciones set estado=p_estado,actualizada_en=now() where id=p_id and estado='enviando';
 if not found then raise exception 'Notificación no disponible'; end if;
end $$;
revoke all on function public.portal_notificaciones_tomar(text) from public, anon, authenticated;
revoke all on function public.portal_notificaciones_finalizar(bigint,text,text) from public, anon, authenticated;
grant execute on function public.portal_notificaciones_tomar(text) to anon;
grant execute on function public.portal_notificaciones_finalizar(bigint,text,text) to anon;
commit;
