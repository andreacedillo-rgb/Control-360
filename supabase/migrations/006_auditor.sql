-- 006 · Perfil AUDITOR
-- Valida conceptos, cantidades y justificación ANTES de Compras. Ejecutar en Supabase → SQL Editor.
-- Lee requisiciones no borrador; solo escribe las que están en Auditoría (estado 'auditoria') o que ya revisó (revision.auditor).
-- No accede a proveedores, nóminas, empleados, reposiciones ni usuarios. Ve documentos adjuntos y archivos de las requisiciones.

create or replace function public.c360_can_read(c text, d jsonb) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare p text := public.c360_perfil(); me text := auth.uid()::text; em text := lower(coalesce(auth.jwt()->>'email',''));
begin
  if auth.uid() is null then return false; end if;
  return case c
    when 'usuarios'           then p in ('sistemas','direccion','administracion','compras') or lower(d->>'email') = em
    when 'bitacora_seguridad' then p = 'sistemas'
    when 'requisiciones'      then p in ('direccion','administracion','compras','sistemas') or (p='residente' and d->>'creatorId' = me)
      or (p='auditor' and d->>'estado' <> 'elaboracion')
    when 'nominas'            then p in ('direccion','administracion','sistemas') or (p='residente' and d->>'creatorId' = me)
    when 'proveedores'        then p in ('direccion','administracion','compras','residente','sistemas')
    when 'empleados'          then p in ('direccion','administracion','residente','sistemas')
    when 'auditoria_reportes' then p in ('direccion','administracion','compras','sistemas')
    -- Documentos adjuntos: Dirección, Administración y Compras ven todos; el residente solo los de sus requisiciones; Sistemas ninguno
    when 'documentos'         then p in ('direccion','administracion','compras','auditor') or (p='residente' and d->>'creatorReqId' = me)
    -- Notificaciones: Sistemas solo las del módulo Sistemas; el resto nunca las de Sistemas, solo las dirigidas a su usuario o a su perfil
    when 'notificaciones'     then case
        when p = 'sistemas'            then d->>'mod' = 'Sistemas'
        when d->>'mod' = 'Sistemas'    then false
        when p = 'residente'           then d->>'uid' = me
        else coalesce(d->>'uid','') = me or (coalesce(d->>'uid','') = '' and coalesce(d->'roles','[]'::jsonb) ? p)
      end
    when 'notif_lecturas'     then d->>'uid' = me
    -- Reposiciones: el residente solo las suyas; borradores solo del autor; Compras/Administración las de su flujo; Dirección todas; Sistemas (depuración)
    when 'reposiciones'       then case
        when p = 'sistemas'            then true
        when p = 'residente'           then d->>'creatorId' = me
        when d->>'creatorId' = me      then true
        when d->>'estado' in ('borrador','incompleta') then false
        when p = 'direccion'           then true
        when p = 'compras'             then d->>'destino' = 'compras'
        when p = 'administracion'      then d->>'destino' = 'administracion' or d->>'estado' in ('autorizada','programada','pagada')
        else false end
    else false end;
end $$;

create or replace function public.c360_can_write(c text, d jsonb) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare p text := public.c360_perfil(); me text := auth.uid()::text; em text := lower(coalesce(auth.jwt()->>'email',''));
begin
  if auth.uid() is null then return false; end if;
  return case c
    when 'usuarios'           then p = 'sistemas' or lower(d->>'email') = em
    when 'bitacora_seguridad' then false
    when 'requisiciones'      then p in ('direccion','administracion','compras','sistemas') or (p='residente' and d->>'creatorId' = me)
      or (p='auditor' and (d->>'estado'='auditoria' or (d->'revision') ? 'auditor'))
    when 'nominas'            then p in ('direccion','administracion') or (p='residente' and d->>'creatorId' = me)
    when 'proveedores'        then p in ('direccion','administracion','compras','residente')
    when 'empleados'          then p in ('direccion','administracion')
    when 'auditoria_reportes' then p in ('direccion','administracion','compras')
    -- Adjuntan Compras, Administración y el residente (solo en sus requisiciones). Dirección solo consulta.
    when 'documentos'         then p in ('administracion','compras') or (p='residente' and d->>'creatorReqId' = me)
    when 'notificaciones'     then p is not null and ((p = 'sistemas') = (d->>'mod' = 'Sistemas'))
    when 'notif_lecturas'     then p is not null and d->>'uid' = me
    when 'reposiciones'       then case
        when p = 'residente'           then d->>'creatorId' = me
        when p = 'administracion'      then d->>'destino' = 'administracion' or d->>'estado' in ('autorizada','programada','pagada') or d->>'creatorId' = me
        when p = 'compras'             then d->>'destino' = 'compras'
        when p = 'direccion'           then true
        else false end
    else false end;
end $$;

drop policy if exists c360_files_sel on storage.objects;
create policy c360_files_sel on storage.objects for select to authenticated
  using ( bucket_id='comprobantes' and (
            public.c360_perfil() in ('direccion','administracion','compras','auditor')
            or (storage.foldername(name))[1] = auth.uid()::text ) );
