-- Ejecutar UNA VEZ en Supabase → SQL Editor (instalaciones que ya corrieron schema.sql y las migraciones 002 y 003)
-- Habilita: documentos adjuntos en requisiciones y Centro de Notificaciones.

create or replace function public.c360_can_read(c text, d jsonb) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare p text := public.c360_perfil(); me text := auth.uid()::text; em text := lower(coalesce(auth.jwt()->>'email',''));
begin
  if auth.uid() is null then return false; end if;
  return case c
    when 'usuarios'           then p in ('sistemas','direccion','administracion','compras') or lower(d->>'email') = em
    when 'bitacora_seguridad' then p = 'sistemas'
    when 'requisiciones'      then p in ('direccion','administracion','compras','sistemas') or (p='residente' and d->>'creatorId' = me)
    when 'nominas'            then p in ('direccion','administracion','sistemas') or (p='residente' and d->>'creatorId' = me)
    when 'proveedores'        then p in ('direccion','administracion','compras','residente','sistemas')
    when 'empleados'          then p in ('direccion','administracion','residente','sistemas')
    when 'auditoria_reportes' then p in ('direccion','administracion','compras','sistemas')
    -- Documentos adjuntos: Dirección, Administración y Compras ven todos; el residente solo los de sus requisiciones; Sistemas ninguno
    when 'documentos'         then p in ('direccion','administracion','compras') or (p='residente' and d->>'creatorReqId' = me)
    -- Notificaciones: Sistemas solo las del módulo Sistemas; el resto nunca las de Sistemas, solo las dirigidas a su usuario o a su perfil
    when 'notificaciones'     then case
        when p = 'sistemas'            then d->>'mod' = 'Sistemas'
        when d->>'mod' = 'Sistemas'    then false
        when p = 'residente'           then d->>'uid' = me
        else coalesce(d->>'uid','') = me or (coalesce(d->>'uid','') = '' and coalesce(d->'roles','[]'::jsonb) ? p)
      end
    when 'notif_lecturas'     then d->>'uid' = me
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
    when 'nominas'            then p in ('direccion','administracion') or (p='residente' and d->>'creatorId' = me)
    when 'proveedores'        then p in ('direccion','administracion','compras','residente')
    when 'empleados'          then p in ('direccion','administracion')
    when 'auditoria_reportes' then p in ('direccion','administracion','compras')
    -- Adjuntan Compras, Administración y el residente (solo en sus requisiciones). Dirección solo consulta.
    when 'documentos'         then p in ('administracion','compras') or (p='residente' and d->>'creatorReqId' = me)
    when 'notificaciones'     then p is not null and ((p = 'sistemas') = (d->>'mod' = 'Sistemas'))
    when 'notif_lecturas'     then p is not null and d->>'uid' = me
    else false end;
end $$;

-- Intentos de acceso no autorizado: cualquier sesión válida puede dejar la alerta para Sistemas (solo inserción)
drop policy if exists docs_notif_acceso on public.docs;
create policy docs_notif_acceso on public.docs for insert to authenticated
  with check ( coll='notificaciones' and data->>'ev'='acceso_denegado' and data->>'mod'='Sistemas' );

-- Documentos y notificaciones son evidencia: no se modifican ni se borran (las sustituciones crean una versión nueva)
drop policy if exists docs_update on public.docs;
create policy docs_update on public.docs for update to authenticated
  using ( coll not in ('documentos','notificaciones') and public.c360_can_write(coll, data) )
  with check ( coll not in ('documentos','notificaciones') and public.c360_can_write(coll, data) );
