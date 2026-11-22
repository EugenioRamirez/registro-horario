begin;
-- Solo los gestores pueden consultar periodos registrados o incorporar documentos nuevos.
create or replace function public.nominas_periodos(p_ano integer,p_mes integer)
returns table(empleado text) language plpgsql stable security definer set search_path=public as $$
begin
 if not public.empleados_es_gestor() then raise exception 'No autorizado'; end if;
 if p_ano not between 2000 and 2100 or p_mes not between 1 and 12 then raise exception 'Periodo no válido'; end if;
 return query select n.empleado from public.nominas_documentos n where n.ano=p_ano and n.mes=p_mes;
end $$;
create or replace function public.nominas_registrar(p_empleado text,p_ano integer,p_mes integer,p_blob_key text,p_sha256 text)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
 if not public.empleados_es_gestor() then raise exception 'No autorizado'; end if;
 if p_empleado is null or p_empleado<>lower(p_empleado) or not exists(select 1 from public.empleados_fichas where email=p_empleado) then raise exception 'Empleado no válido'; end if;
 if p_ano not between 2000 and 2100 or p_mes not between 1 and 12 or p_blob_key !~ '^[a-f0-9]{32}/[0-9]{4}-[0-9]{2}\.pdf$' or right(p_blob_key,11) <> p_ano::text||'-'||lpad(p_mes::text,2,'0')||'.pdf' or p_sha256 !~ '^[a-f0-9]{64}$' then raise exception 'Documento no válido'; end if;
 insert into public.nominas_documentos(empleado,ano,mes,blob_key,sha256) values(p_empleado,p_ano,p_mes,p_blob_key,p_sha256) returning id into v_id;
 return v_id;
end $$;
revoke all on function public.nominas_periodos(integer,integer) from public,anon;
revoke all on function public.nominas_registrar(text,integer,integer,text,text) from public,anon;
grant execute on function public.nominas_periodos(integer,integer) to authenticated;
grant execute on function public.nominas_registrar(text,integer,integer,text,text) to authenticated;
commit;
