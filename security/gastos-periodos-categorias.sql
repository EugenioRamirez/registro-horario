begin;
alter table public.gastos_notas add column ano smallint, add column mes smallint;
alter table public.gastos_notas add constraint gastos_periodo_valido check ((ano is null and mes is null) or (ano is not null and mes is not null and ano between 2000 and 2100 and mes between 1 and 12));
create unique index gastos_una_nota_por_mes on public.gastos_notas (empleado,ano,mes) where ano is not null and mes is not null;
alter table public.gastos_lineas add column categoria text check (categoria is null or categoria in ('Dieta diaria','Kilómetros','Transporte','Invitaciones','Alojamiento','Taxi','Parking y peajes','Carburante','Teléfono','Otro'));
create function public.gastos_crear_periodo(p_ano integer,p_mes integer) returns uuid language plpgsql security definer set search_path=public as $$
declare v_email text:=public.empleados_email(); v_id uuid;
begin
 if v_email is null or not exists(select 1 from public.empleados_fichas where email=v_email) then raise exception 'No existe una ficha asociada a tu cuenta.'; end if;
 if p_ano is null or p_ano not between 2000 and 2100 or p_mes is null or p_mes not between 1 and 12 then raise exception 'Selecciona un mes y año válidos.'; end if;
 begin insert into public.gastos_notas(empleado,propietario,ano,mes) values(v_email,auth.uid(),p_ano,p_mes) returning id into v_id;
 exception when unique_violation then raise exception 'Ya existe una nota de gastos para ese mes. Abre la nota existente.'; end;
 insert into public.gastos_historial(nota_id,estado,actor) values(v_id,'borrador',v_email);
 return v_id;
end $$;
create function public.gastos_fijar_periodo(p_id uuid,p_ano integer,p_mes integer) returns void language plpgsql security definer set search_path=public as $$
declare n public.gastos_notas%rowtype; v_email text:=public.empleados_email();
begin
 select * into n from public.gastos_notas where id=p_id for update;
 if not found or v_email is null or n.empleado<>v_email or n.propietario<>auth.uid() or n.estado not in ('borrador','devuelta') then raise exception 'Nota no disponible.'; end if;
 if n.ano is not null or n.mes is not null then raise exception 'El período de una nota ya asignada no se puede cambiar.'; end if;
 if p_ano is null or p_ano not between 2000 and 2100 or p_mes is null or p_mes not between 1 and 12 then raise exception 'Selecciona un mes y año válidos.'; end if;
 begin update public.gastos_notas set ano=p_ano,mes=p_mes,actualizada_en=now() where id=p_id;
 exception when unique_violation then raise exception 'Ya existe una nota de gastos para ese mes. Abre la nota existente.'; end;
end $$;
revoke all on function public.gastos_crear() from authenticated;
revoke all on function public.gastos_crear_periodo(integer,integer) from public,anon;
revoke all on function public.gastos_fijar_periodo(uuid,integer,integer) from public,anon;
grant execute on function public.gastos_crear_periodo(integer,integer) to authenticated;
grant execute on function public.gastos_fijar_periodo(uuid,integer,integer) to authenticated;
create or replace function public.gastos_guardar(p_id uuid,p_descripcion text,p_lineas jsonb,p_justificante text,p_enviar boolean) returns void language plpgsql security definer set search_path=public,storage as $$
declare v_n public.gastos_notas%rowtype; v_total numeric(12,2); v_num integer; v_estado text; v_path text; v_email text:=public.empleados_email();
begin
 select * into v_n from public.gastos_notas where id=p_id for update;
 if not found or v_email is null or v_n.empleado<>v_email or v_n.propietario<>auth.uid() then raise exception 'Nota no disponible.'; end if;
 if v_n.ano is null or v_n.mes is null then raise exception 'Selecciona el mes y el año de la nota.'; end if;
 if v_n.estado not in ('borrador','devuelta') then raise exception 'La nota no se puede modificar en este estado.'; end if;
 if p_enviar is null or p_lineas is null or jsonb_typeof(p_lineas)<>'array' or jsonb_array_length(p_lineas)>100 or length(coalesce(p_descripcion,''))>300 then raise exception 'Datos de la nota no válidos.'; end if;
 v_path:=coalesce(nullif(p_justificante,''),v_n.justificante_path);
 if v_path is not null and (v_path !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.pdf$' or split_part(v_path,'/',1)<>auth.uid()::text or split_part(v_path,'/',2)<>p_id::text or not exists(select 1 from storage.objects o where o.bucket_id='gastos-justificantes' and o.name=v_path)) then raise exception 'Justificante no válido o no disponible.'; end if;
 if exists(select 1 from jsonb_to_recordset(p_lineas) as x(categoria text) where x.categoria is null or x.categoria not in ('Dieta diaria','Kilómetros','Transporte','Invitaciones','Alojamiento','Taxi','Parking y peajes','Carburante','Teléfono','Otro')) then raise exception 'Selecciona una categoría válida para cada gasto.'; end if;
 if exists(select 1 from jsonb_to_recordset(p_lineas) as x(importe numeric) where x.importe is null or x.importe<>round(x.importe,2)) then raise exception 'Los importes deben tener como máximo dos decimales.'; end if;
 delete from public.gastos_lineas where nota_id=p_id;
 insert into public.gastos_lineas(nota_id,fecha,concepto,importe,observaciones,categoria)
 select p_id,x.fecha,trim(x.concepto),x.importe,nullif(trim(x.observaciones),''),x.categoria from jsonb_to_recordset(p_lineas) as x(fecha date,concepto text,importe numeric,observaciones text,categoria text);
 select count(*),coalesce(sum(importe),0) into v_num,v_total from public.gastos_lineas where nota_id=p_id;
 if p_enviar and (length(trim(coalesce(p_descripcion,'')))=0 or v_num=0 or v_path is null) then raise exception 'Para enviar, añade una descripción, al menos un gasto y un PDF de justificantes.'; end if;
 v_estado:=case when p_enviar then 'pendiente' else v_n.estado end;
 update public.gastos_notas set descripcion=trim(coalesce(p_descripcion,'')),total=v_total,justificante_path=v_path,estado=v_estado,actualizada_en=now() where id=p_id;
 if p_enviar then insert into public.gastos_historial(nota_id,estado,actor,detalle) values(p_id,v_estado,v_email,'Nota enviada para revisión'); end if;
end $$;
commit;
