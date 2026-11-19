-- Ejecutar UNA VEZ en Supabase → SQL Editor (instalaciones que ya corrieron schema.sql)
-- Da a SISTEMAS lectura y eliminación de registros operativos (requisiciones, nóminas, empleados, proveedores, auditoría).
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
    else false end;
end $$;

-- SISTEMAS puede modificar requisiciones (necesario para eliminar órdenes de compra)
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
    else false end;
end $$;

drop policy if exists docs_delete on public.docs;
create policy docs_delete on public.docs for delete to authenticated
  using ( (coll='proveedores' and public.c360_perfil() in ('compras','sistemas'))
       or (coll in ('requisiciones','nominas','empleados','auditoria_reportes') and public.c360_perfil()='sistemas') );
