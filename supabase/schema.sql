-- ============================================================
-- CONTROL 360 · Esquema Supabase (ejecutar completo en SQL Editor)
-- ============================================================

create table if not exists public.docs (
  coll       text not null,
  id         text not null,
  data       jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (coll, id)
);
create index if not exists docs_creator_idx on public.docs (coll, (data->>'creatorId'));
create index if not exists docs_uid_idx     on public.docs (coll, (data->>'uid'));
create index if not exists docs_email_idx   on public.docs (coll, (lower(data->>'email')));

alter table public.docs enable row level security;

-- Perfil ACTIVO del usuario autenticado (null si no está registrado o está desactivado)
create or replace function public.c360_perfil() returns text
language sql stable security definer set search_path = public as $$
  select data->>'perfil' from public.docs
   where coll='usuarios'
     and lower(data->>'email') = lower(coalesce(auth.jwt()->>'email',''))
     and coalesce((data->>'activo')::boolean,false)
   limit 1
$$;

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

drop policy if exists docs_select on public.docs;
drop policy if exists docs_insert on public.docs;
drop policy if exists docs_update on public.docs;
drop policy if exists docs_bit_ins on public.docs;
drop policy if exists docs_notif_acceso on public.docs;

create policy docs_select on public.docs for select to authenticated
  using ( public.c360_can_read(coll, data) );

-- Altas: usuarios solo por SISTEMAS; bitácora la escribe cualquier usuario activo (solo inserción)
create policy docs_insert on public.docs for insert to authenticated
  with check (
    case when coll='usuarios' then public.c360_perfil()='sistemas'
         else public.c360_can_write(coll, data) end
  );
create policy docs_notif_acceso on public.docs for insert to authenticated
  with check ( coll='notificaciones' and data->>'ev'='acceso_denegado' and data->>'mod'='Sistemas' );
create policy docs_bit_ins on public.docs for insert to authenticated
  with check ( coll='bitacora_seguridad' and public.c360_perfil() is not null );

create policy docs_update on public.docs for update to authenticated
  using ( coll not in ('documentos','notificaciones') and public.c360_can_write(coll, data) )
  with check ( coll not in ('documentos','notificaciones') and public.c360_can_write(coll, data) );
-- DELETE: Compras elimina proveedores; SISTEMAS elimina requisiciones, nóminas, empleados, proveedores y reportes de auditoría. Usuarios y bitácora nunca se borran.
drop policy if exists docs_delete on public.docs;
create policy docs_delete on public.docs for delete to authenticated
  using ( (coll='proveedores' and public.c360_perfil() in ('compras','sistemas'))
       or (coll in ('requisiciones','nominas','empleados','auditoria_reportes','reposiciones') and public.c360_perfil()='sistemas') );

-- Protección de la tabla de usuarios
create or replace function public.c360_guard_usuarios() returns trigger
language plpgsql security definer set search_path = public as $$
declare p text := public.c360_perfil(); em text := lower(coalesce(auth.jwt()->>'email',''));
        own boolean := lower(old.data->>'email') = em; allowed jsonb;
begin
  if new.coll <> 'usuarios' then return new; end if;
  if auth.uid() is null then return new; end if; -- SQL Editor / service role
  -- correo único
  if exists (select 1 from public.docs d where d.coll='usuarios' and d.id <> new.id
             and lower(d.data->>'email') = lower(new.data->>'email')) then
    raise exception 'Ese correo ya tiene una cuenta';
  end if;
  if own then
    -- nadie cambia su propio perfil, estado ni correo; solo vinculación y último acceso
    new.data := old.data || coalesce((select jsonb_object_agg(k,v) from jsonb_each(new.data) t(k,v)
                 where k in ('uid','ultimoAcceso','primerAcceso')), '{}'::jsonb);
  elsif p is distinct from 'sistemas' then
    raise exception 'Sin permiso';
  end if;
  return new;
end $$;
drop trigger if exists c360_guard_usuarios_t on public.docs;
create trigger c360_guard_usuarios_t before update on public.docs
  for each row when (old.coll='usuarios') execute function public.c360_guard_usuarios();

create or replace function public.c360_guard_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.coll='usuarios' and auth.uid() is not null and exists (
     select 1 from public.docs d where d.coll='usuarios' and lower(d.data->>'email')=lower(new.data->>'email')) then
    raise exception 'Ese correo ya tiene una cuenta';
  end if;
  return new;
end $$;
drop trigger if exists c360_guard_insert_t on public.docs;
create trigger c360_guard_insert_t before insert on public.docs
  for each row execute function public.c360_guard_insert();

-- Tiempo real
alter table public.docs replica identity full;
do $$ begin
  alter publication supabase_realtime add table public.docs;
exception when duplicate_object then null; end $$;

-- Archivos (comprobantes): bucket privado
insert into storage.buckets (id, name, public) values ('comprobantes','comprobantes',false)
on conflict (id) do nothing;

drop policy if exists c360_files_ins on storage.objects;
drop policy if exists c360_files_sel on storage.objects;
create policy c360_files_ins on storage.objects for insert to authenticated
  with check ( bucket_id='comprobantes' and public.c360_perfil() is not null
               and (storage.foldername(name))[1] = auth.uid()::text );
create policy c360_files_sel on storage.objects for select to authenticated
  using ( bucket_id='comprobantes' and (
            (storage.foldername(name))[1] = auth.uid()::text
            or (public.c360_perfil() in ('direccion','administracion'))
            or (public.c360_perfil() in ('compras','auditor') and coalesce((storage.foldername(name))[2],'') <> 'rh') ) );

-- ============================================================
-- PRIMER USUARIO (SISTEMAS). CAMBIE EL CORREO por el suyo antes de ejecutar.
-- Después cree ese mismo usuario en Authentication → Users (ver README).
-- ============================================================
insert into public.docs (coll, id, data) values ('usuarios','admin-inicial', jsonb_build_object(
  'id','admin-inicial','nombre','Administrador de Sistemas','email','CAMBIE@SUCORREO.COM',
  'perfil','sistemas','activo',true,'creado',(extract(epoch from now())*1000)::bigint,
  'creadoPor','seed','uid','','ultimoAcceso',0,'sesionV',0))
on conflict do nothing;
