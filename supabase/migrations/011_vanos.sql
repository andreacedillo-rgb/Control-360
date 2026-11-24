-- 011 · LEVANTAMIENTO DE VANOS EN SUPABASE
-- Colecciones nuevas: vanos (un documento por levantamiento) y vanos_cfg (proyectos y datos compartidos).
-- PRIVADO POR USUARIO: cada persona ve, edita y elimina SOLAMENTE lo que ella misma sube (nadie más, ni siquiera Dirección o Sistemas).
-- Las fotografías se guardan en el bucket privado "comprobantes" (carpeta <usuario>/vanos/).
-- Ejecutar en Supabase → SQL Editor (después de 001–010). Es seguro repetirla.

-- Perfil ACTIVO del usuario autenticado (se incluye aquí por si aún no existe; es idéntica a la de schema.sql)
create or replace function public.c360_perfil() returns text
language sql stable security definer set search_path = public as $$
  select data->>'perfil' from public.docs
   where coll='usuarios'
     and lower(data->>'email') = lower(coalesce(auth.jwt()->>'email',''))
     and coalesce((data->>'activo')::boolean,false)
   limit 1
$$;

-- Quién puede asignar tareas: el perfil Auditor y las cuentas listadas aquí (para agregar a alguien, añada su correo en minúsculas).
create or replace function public.c360_asigna_tareas() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.c360_perfil() = 'auditor', false)
      or lower(coalesce(auth.jwt()->>'email','')) in ('julio.estrada@catraar.com')
$$;

create or replace function public.c360_can_read(c text, d jsonb) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare p text := public.c360_perfil(); me text := auth.uid()::text; em text := lower(coalesce(auth.jwt()->>'email',''));
begin
  if auth.uid() is null then return false; end if;
  return case c
    when 'usuarios'           then p in ('sistemas','direccion','administracion','compras','auditor') or public.c360_asigna_tareas() or lower(d->>'email') = em
    when 'bitacora_seguridad' then p = 'sistemas'
    when 'requisiciones'      then p in ('direccion','administracion','compras','sistemas') or (p='residente' and d->>'creatorId' = me)
      or (p='auditor' and d->>'estado' <> 'elaboracion')
    when 'nominas'            then p in ('direccion','administracion','sistemas') or (p='residente' and d->>'creatorId' = me)
    when 'proveedores'        then p in ('direccion','administracion','compras','residente','sistemas')
    when 'empleados'          then p in ('direccion','administracion','residente','sistemas')
    when 'proyectos'          then p = 'administracion'
    when 'anuncios'           then p is not null
    when 'vanos'              then p is not null and d->>'uid' = me
    when 'vanos_cfg'          then p is not null and d->>'uid' = me
    when 'tareas'             then p in ('auditor','direccion') or public.c360_asigna_tareas() or (p is not null and lower(d->>'asigEmail') = em)
    when 'anuncios_enterados' then p = 'sistemas' or d->>'uid' = me or d->>'uid' like me || ':%'
    when 'altas_trabajadores' then p in ('direccion','administracion') or (p='residente' and d->>'creatorId' = me)
    when 'expedientes_trabajadores' then p in ('direccion','administracion')
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
    when 'proyectos'          then p = 'administracion'
    when 'anuncios'           then p = 'sistemas'
    when 'vanos'              then p is not null and d->>'uid' = me
    when 'vanos_cfg'          then p is not null and d->>'uid' = me
    when 'tareas'             then public.c360_asigna_tareas() or (p is not null and lower(d->>'asigEmail') = em)
    when 'anuncios_enterados' then p is not null and (d->>'uid' = me or d->>'uid' like me || ':%')
    when 'altas_trabajadores' then p = 'administracion' or (p='residente' and d->>'creatorId' = me and d->>'estado' <> 'aceptada')
    when 'expedientes_trabajadores' then p = 'administracion'
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
            (storage.foldername(name))[1] = auth.uid()::text
            or (public.c360_perfil() in ('direccion','administracion'))
            or (public.c360_perfil() in ('compras','auditor') and coalesce((storage.foldername(name))[2],'') <> 'rh') ) );

-- Borrado: se conserva lo anterior y se agrega vanos (solo el propietario del levantamiento)
drop policy if exists docs_delete on public.docs;
create policy docs_delete on public.docs for delete to authenticated
  using ( (coll='proveedores' and public.c360_perfil() in ('compras','sistemas'))
       or (coll in ('requisiciones','nominas','empleados','auditoria_reportes','reposiciones') and public.c360_perfil()='sistemas')
       or (coll in ('vanos','vanos_cfg') and public.c360_perfil() is not null and data->>'uid' = auth.uid()::text) );
