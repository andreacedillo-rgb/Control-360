-- Ejecutar UNA VEZ en Supabase → SQL Editor (instalaciones que ya corrieron schema.sql)
drop policy if exists docs_delete on public.docs;
create policy docs_delete on public.docs for delete to authenticated
  using ( coll='proveedores' and public.c360_perfil()='compras' );
