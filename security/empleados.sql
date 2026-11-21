begin;
create table public.empleados_gestores (email text primary key check (email=lower(email)));
create table public.empleados_fichas (
 email text primary key check (email=lower(email) and email like '%@xpecializa.com'),
 nombre text not null check (length(trim(nombre)) between 1 and 200),
 fecha_alta date not null, puesto text check (length(puesto)<=200),
 dni_nie text check(length(dni_nie)<=30), fecha_nacimiento date, num_seguridad_social text check(length(num_seguridad_social)<=30),
 direccion_via text check(length(direccion_via)<=250), direccion_numero text check(length(direccion_numero)<=30),
 direccion_piso text check(length(direccion_piso)<=60), codigo_postal text check(length(codigo_postal)<=20),
 localidad text check(length(localidad)<=120), provincia text check(length(provincia)<=120), pais text check(length(pais)<=120),
 movil text check(length(movil)<=40), correo_personal text check(length(correo_personal)<=254),
 iban text check (iban is null or iban ~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$'),
 reconocimiento text not null default 'pendiente' check (reconocimiento in ('pendiente','acepta','renuncia')),
 fecha_decision date,
 check ((reconocimiento='pendiente' and fecha_decision is null) or (reconocimiento in ('acepta','renuncia') and fecha_decision is not null)),
 actualizado_en timestamptz not null default now(), actualizado_por text not null
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
create function public.empleados_guardar_ficha(p_datos jsonb,p_actualizar boolean) returns void language plpgsql security definer set search_path=public as $$
declare v_email text:=lower(trim(p_datos->>'email')); v_nombre text:=trim(p_datos->>'nombre');
 v_iban text:=nullif(regexp_replace(upper(coalesce(p_datos->>'iban','')), '[[:space:]]', '', 'g'),'');
 v_reconocimiento text:=p_datos->>'reconocimiento';
begin
 if not public.empleados_es_gestor() then raise exception 'No autorizado'; end if;
 if v_email is null or v_email not like '%@xpecializa.com' or v_nombre is null or length(v_nombre) not between 1 and 200 or nullif(p_datos->>'fecha_alta','') is null or v_reconocimiento is null or v_reconocimiento not in ('pendiente','acepta','renuncia') then raise exception 'Datos de ficha no válidos'; end if;
 if p_actualizar is null then raise exception 'Modo de edición no válido'; end if;
 if not p_actualizar and exists(select 1 from public.empleados_fichas where email=v_email) then raise exception 'Ya existe una ficha con ese correo. Usa Editar para modificarla'; end if;
 if p_actualizar and not exists(select 1 from public.empleados_fichas where email=v_email) then raise exception 'No existe la ficha que quieres editar'; end if;
 if v_iban is not null and v_iban !~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$' then raise exception 'Comprueba el formato de la cuenta bancaria (IBAN)'; end if;
 if (v_reconocimiento='pendiente' and nullif(p_datos->>'fecha_decision','') is not null) or (v_reconocimiento<>'pendiente' and nullif(p_datos->>'fecha_decision','') is null) then raise exception 'Indica la fecha de la decisión; si está pendiente, déjala vacía'; end if;
 insert into public.empleados_fichas(email,nombre,fecha_alta,puesto,dni_nie,fecha_nacimiento,num_seguridad_social,direccion_via,direccion_numero,direccion_piso,codigo_postal,localidad,provincia,pais,movil,correo_personal,iban,reconocimiento,fecha_decision,actualizado_por)
 values(v_email,v_nombre,(p_datos->>'fecha_alta')::date,nullif(trim(p_datos->>'puesto'),''),nullif(trim(p_datos->>'dni_nie'),''),nullif(p_datos->>'fecha_nacimiento','')::date,nullif(trim(p_datos->>'num_seguridad_social'),''),nullif(trim(p_datos->>'direccion_via'),''),nullif(trim(p_datos->>'direccion_numero'),''),nullif(trim(p_datos->>'direccion_piso'),''),nullif(trim(p_datos->>'codigo_postal'),''),nullif(trim(p_datos->>'localidad'),''),nullif(trim(p_datos->>'provincia'),''),nullif(trim(p_datos->>'pais'),''),nullif(trim(p_datos->>'movil'),''),nullif(trim(p_datos->>'correo_personal'),''),v_iban,v_reconocimiento,nullif(p_datos->>'fecha_decision','')::date,public.empleados_email())
 on conflict(email) do update set nombre=excluded.nombre,fecha_alta=excluded.fecha_alta,puesto=excluded.puesto,dni_nie=excluded.dni_nie,fecha_nacimiento=excluded.fecha_nacimiento,num_seguridad_social=excluded.num_seguridad_social,direccion_via=excluded.direccion_via,direccion_numero=excluded.direccion_numero,direccion_piso=excluded.direccion_piso,codigo_postal=excluded.codigo_postal,localidad=excluded.localidad,provincia=excluded.provincia,pais=excluded.pais,movil=excluded.movil,correo_personal=excluded.correo_personal,iban=excluded.iban,reconocimiento=excluded.reconocimiento,fecha_decision=excluded.fecha_decision,actualizado_en=now(),actualizado_por=excluded.actualizado_por;
end $$;
revoke all on function public.empleados_guardar_ficha(jsonb,boolean) from public,anon;
grant execute on function public.empleados_guardar_ficha(jsonb,boolean) to authenticated;
commit;
