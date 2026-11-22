begin;
create table if not exists public.empleados_retribucion (empleado text not null references public.empleados_fichas(email), ano smallint not null check (ano between 2000 and 2100), sba_fijo numeric(12,2) check (sba_fijo >= 0), variable_anual numeric(12,2) check (variable_anual >= 0), pagas smallint check (pagas between 1 and 24), observacion text, primary key (empleado, ano));
alter table public.empleados_retribucion enable row level security;
revoke all on public.empleados_retribucion from public, anon, authenticated;
grant select on public.empleados_retribucion to authenticated;
create policy retribucion_gestores_lectura on public.empleados_retribucion for select to authenticated using (public.empleados_es_gestor());
create function public.nominas_admin_listar(p_empleado text) returns table(id uuid,ano integer,mes integer) language plpgsql stable security definer set search_path=public as $$
begin
 if not public.empleados_es_gestor() then raise exception 'No autorizado'; end if;
 return query select n.id,n.ano,n.mes from public.nominas_documentos n where n.empleado=lower(trim(p_empleado)) order by n.ano desc,n.mes desc;
end $$;
create function public.nominas_admin_documento(p_id uuid) returns table(empleado text,ano integer,mes integer,blob_key text,sha256 text) language plpgsql stable security definer set search_path=public as $$
begin
 if not public.empleados_es_gestor() then raise exception 'No autorizado'; end if;
 return query select n.empleado,n.ano,n.mes,n.blob_key,n.sha256 from public.nominas_documentos n where n.id=p_id;
end $$;
revoke all on function public.nominas_admin_listar(text) from public,anon;
revoke all on function public.nominas_admin_documento(uuid) from public,anon;
grant execute on function public.nominas_admin_listar(text) to authenticated;
grant execute on function public.nominas_admin_documento(uuid) to authenticated;
commit;
