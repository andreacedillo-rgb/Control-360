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
    when 'requisiciones'      then p in ('direccion','administracion','compras') or (p='residente' and d->>'creatorId' = me)
    when 'nominas'            then p in ('direccion','administracion') or (p='residente' and d->>'creatorId' = me)
    when 'proveedores'        then p in ('direccion','administracion','compras','residente')
    when 'empleados'          then p in ('direccion','administracion','residente')
    when 'auditoria_reportes' then p in ('direccion','administracion','compras')
    else false end;
end $$;

create or replace function public.c360_can_write(c text, d jsonb) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare p text := public.c360_perfil(); me text := auth.uid()::text; em text := lower(coalesce(auth.jwt()->>'email',''));
begin
  if auth.uid() is null then return false; end if;
  return case c
    when 'usuarios'           then p = 'sistemas' or lower(d->>'email') = em   -- el propio registro: un trigger limita los campos
    when 'bitacora_seguridad' then false
    when 'requisiciones'      then p in ('direccion','administracion','compras') or (p='residente' and d->>'creatorId' = me)
    when 'nominas'            then p in ('direccion','administracion') or (p='residente' and d->>'creatorId' = me)
    when 'proveedores'        then p in ('direccion','administracion','compras','residente')
    when 'empleados'          then p in ('direccion','administracion')
    when 'auditoria_reportes' then p in ('direccion','administracion','compras')
    else false end;
end $$;

drop policy if exists docs_select on public.docs;
drop policy if exists docs_insert on public.docs;
drop policy if exists docs_update on public.docs;
drop policy if exists docs_bit_ins on public.docs;

create policy docs_select on public.docs for select to authenticated
  using ( public.c360_can_read(coll, data) );

-- Altas: usuarios solo por SISTEMAS; bitácora la escribe cualquier usuario activo (solo inserción)
create policy docs_insert on public.docs for insert to authenticated
  with check (
    case when coll='usuarios' then public.c360_perfil()='sistemas'
         else public.c360_can_write(coll, data) end
  );
create policy docs_bit_ins on public.docs for insert to authenticated
  with check ( coll='bitacora_seguridad' and public.c360_perfil() is not null );

create policy docs_update on public.docs for update to authenticated
  using ( public.c360_can_write(coll, data) )
  with check ( public.c360_can_write(coll, data) );
-- No hay política DELETE: nada se borra (el historial se conserva).

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
            public.c360_perfil() in ('direccion','administracion','compras')
            or (storage.foldername(name))[1] = auth.uid()::text ) );

-- ============================================================
-- PRIMER USUARIO (SISTEMAS). CAMBIE EL CORREO por el suyo antes de ejecutar.
-- Después cree ese mismo usuario en Authentication → Users (ver README).
-- ============================================================
insert into public.docs (coll, id, data) values ('usuarios','admin-inicial', jsonb_build_object(
  'id','admin-inicial','nombre','Administrador de Sistemas','email','CAMBIE@SUCORREO.COM',
  'perfil','sistemas','activo',true,'creado',(extract(epoch from now())*1000)::bigint,
  'creadoPor','seed','uid','','ultimoAcceso',0,'sesionV',0))
on conflict do nothing;
