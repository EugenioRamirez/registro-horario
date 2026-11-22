begin;
create table public.gastos_notas (
 id uuid primary key default gen_random_uuid(), empleado text not null references public.empleados_fichas(email), propietario uuid not null references auth.users(id),
 descripcion text not null default '' check(length(descripcion)<=300), estado text not null default 'borrador' check(estado in ('borrador','pendiente','devuelta','aprobada','abonada')),
 total numeric(12,2) not null default 0 check(total>=0), justificante_path text, motivo text, fecha_aprobacion timestamptz, fecha_abono date,
 creada_en timestamptz not null default now(), actualizada_en timestamptz not null default now()
);
create table public.gastos_lineas (
 id uuid primary key default gen_random_uuid(), nota_id uuid not null references public.gastos_notas(id) on delete cascade,
 fecha date not null, concepto text not null check(length(trim(concepto)) between 1 and 250), importe numeric(12,2) not null check(importe>0), observaciones text check(length(observaciones)<=1000)
);
create table public.gastos_historial (
 id bigint generated always as identity primary key, nota_id uuid not null references public.gastos_notas(id) on delete cascade,
 estado text not null, actor text not null, detalle text, creado_en timestamptz not null default now()
);
alter table public.gastos_notas enable row level security;
alter table public.gastos_lineas enable row level security;
alter table public.gastos_historial enable row level security;
create policy gastos_notas_lectura on public.gastos_notas for select to authenticated using (empleado=public.empleados_email() or (estado<>'borrador' and public.empleados_es_gestor()));
create policy gastos_lineas_lectura on public.gastos_lineas for select to authenticated using (exists(select 1 from public.gastos_notas n where n.id=nota_id and (n.empleado=public.empleados_email() or (n.estado<>'borrador' and public.empleados_es_gestor()))));
create policy gastos_historial_lectura on public.gastos_historial for select to authenticated using (exists(select 1 from public.gastos_notas n where n.id=nota_id and (n.empleado=public.empleados_email() or (n.estado<>'borrador' and public.empleados_es_gestor()))));
revoke all on public.gastos_notas,public.gastos_lineas,public.gastos_historial from public,anon,authenticated;
grant select on public.gastos_notas,public.gastos_lineas,public.gastos_historial to authenticated;
create function public.gastos_crear() returns uuid language plpgsql security definer set search_path=public as $$
declare v_email text:=public.empleados_email(); v_id uuid;
begin
 if v_email is null or not exists(select 1 from public.empleados_fichas where email=v_email) then raise exception 'No existe una ficha asociada a tu cuenta.'; end if;
 insert into public.gastos_notas(empleado,propietario) values(v_email,auth.uid()) returning id into v_id;
 insert into public.gastos_historial(nota_id,estado,actor) values(v_id,'borrador',v_email);
 return v_id;
end $$;
create function public.gastos_guardar(p_id uuid,p_descripcion text,p_lineas jsonb,p_justificante text,p_enviar boolean) returns void language plpgsql security definer set search_path=public,storage as $$
declare v_n public.gastos_notas%rowtype; v_total numeric(12,2); v_num integer; v_estado text; v_path text; v_email text:=public.empleados_email();
begin
 select * into v_n from public.gastos_notas where id=p_id for update;
 if not found or v_email is null or v_n.empleado<>v_email or v_n.propietario<>auth.uid() then raise exception 'Nota no disponible.'; end if;
 if v_n.estado not in ('borrador','devuelta') then raise exception 'La nota no se puede modificar en este estado.'; end if;
 if p_enviar is null or p_lineas is null or jsonb_typeof(p_lineas)<>'array' or jsonb_array_length(p_lineas)>100 or length(coalesce(p_descripcion,''))>300 then raise exception 'Datos de la nota no válidos.'; end if;
 v_path:=coalesce(nullif(p_justificante,''),v_n.justificante_path);
 if v_path is not null and (v_path !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.pdf$' or split_part(v_path,'/',1)<>auth.uid()::text or split_part(v_path,'/',2)<>p_id::text or not exists(select 1 from storage.objects o where o.bucket_id='gastos-justificantes' and o.name=v_path)) then raise exception 'Justificante no válido o no disponible.'; end if;
 if exists(select 1 from jsonb_to_recordset(p_lineas) as x(importe numeric) where x.importe is null or x.importe<>round(x.importe,2)) then raise exception 'Los importes deben tener como máximo dos decimales.'; end if;
 delete from public.gastos_lineas where nota_id=p_id;
 insert into public.gastos_lineas(nota_id,fecha,concepto,importe,observaciones)
 select p_id,x.fecha,trim(x.concepto),x.importe,nullif(trim(x.observaciones),'') from jsonb_to_recordset(p_lineas) as x(fecha date,concepto text,importe numeric,observaciones text);
 select count(*),coalesce(sum(importe),0) into v_num,v_total from public.gastos_lineas where nota_id=p_id;
 if p_enviar and (length(trim(coalesce(p_descripcion,'')))=0 or v_num=0 or v_path is null) then raise exception 'Para enviar, añade una descripción, al menos un gasto y un PDF de justificantes.'; end if;
 v_estado:=case when p_enviar then 'pendiente' else v_n.estado end;
 update public.gastos_notas set descripcion=trim(coalesce(p_descripcion,'')),total=v_total,justificante_path=v_path,estado=v_estado,actualizada_en=now() where id=p_id;
 if p_enviar then insert into public.gastos_historial(nota_id,estado,actor,detalle) values(p_id,v_estado,v_email,'Nota enviada para revisión'); end if;
end $$;
create function public.gastos_resolver(p_id uuid,p_accion text,p_motivo text default null,p_fecha_abono date default null) returns void language plpgsql security definer set search_path=public as $$
declare n public.gastos_notas%rowtype; v_email text:=public.empleados_email(); v_estado text;
begin
 if not public.empleados_es_gestor() then raise exception 'No autorizado.'; end if;
 select * into n from public.gastos_notas where id=p_id for update;
 if not found then raise exception 'Nota no disponible.'; end if;
 if n.empleado=v_email and not (v_email='eugenio.ramirez@xpecializa.com' and p_accion='aprobar') then raise exception 'No puedes realizar esta acción sobre tu propia nota.'; end if;
 if p_accion='aprobar' and n.estado='pendiente' then v_estado:='aprobada';
 elsif p_accion='devolver' and n.estado='pendiente' and length(trim(coalesce(p_motivo,''))) between 1 and 1000 then v_estado:='devuelta';
 elsif p_accion='abonar' and n.estado='aprobada' and p_fecha_abono is not null then v_estado:='abonada';
 else raise exception 'Acción no permitida o falta el motivo o fecha de abono.'; end if;
 update public.gastos_notas set estado=v_estado,motivo=case when v_estado='devuelta' then trim(p_motivo) else motivo end,fecha_aprobacion=case when v_estado='aprobada' then now() else fecha_aprobacion end,fecha_abono=case when v_estado='abonada' then p_fecha_abono else fecha_abono end,actualizada_en=now() where id=p_id;
 insert into public.gastos_historial(nota_id,estado,actor,detalle) values(p_id,v_estado,v_email,case when v_estado='devuelta' then trim(p_motivo) when v_estado='abonada' then p_fecha_abono::text else null end);
end $$;
revoke all on function public.gastos_crear() from public,anon;
revoke all on function public.gastos_guardar(uuid,text,jsonb,text,boolean) from public,anon;
revoke all on function public.gastos_resolver(uuid,text,text,date) from public,anon;
grant execute on function public.gastos_crear() to authenticated;
grant execute on function public.gastos_guardar(uuid,text,jsonb,text,boolean) to authenticated;
grant execute on function public.gastos_resolver(uuid,text,text,date) to authenticated;
create policy gastos_pdf_insertar on storage.objects for insert to authenticated with check (
 bucket_id='gastos-justificantes' and name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.pdf$' and split_part(name,'/',1)=auth.uid()::text and
 exists(select 1 from public.gastos_notas n where n.id::text=split_part(name,'/',2) and n.propietario=auth.uid() and n.empleado=public.empleados_email() and n.estado in ('borrador','devuelta'))
);
create policy gastos_pdf_leer on storage.objects for select to authenticated using (
 bucket_id='gastos-justificantes' and exists(select 1 from public.gastos_notas n where n.id::text=split_part(name,'/',2) and
 ((n.propietario=auth.uid() and n.empleado=public.empleados_email() and split_part(name,'/',1)=auth.uid()::text) or (public.empleados_es_gestor() and n.estado<>'borrador' and n.justificante_path=name)))
);
commit;
