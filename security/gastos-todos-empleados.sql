begin;
-- Eliminar solo las restricciones del piloto; se mantienen las políticas de propiedad y gestión.
drop policy if exists gastos_piloto_notas on public.gastos_notas;
drop policy if exists gastos_piloto_pdf_lectura on storage.objects;
drop policy if exists gastos_piloto_pdf_subida on storage.objects;
drop trigger if exists gastos_piloto_escritura on public.gastos_notas;
commit;
