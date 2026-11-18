// Edge Function: gestionar-usuario
// Solo un usuario activo con perfil SISTEMAS puede invocarla.
// accion "crear" o "reset": deja al usuario con la contraseña temporal indicada y obliga a cambiarla en su primer ingreso.
// No envía correos. La contraseña temporal no se guarda en ninguna tabla.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};
const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const url = Deno.env.get('SUPABASE_URL')!;
    const anon = Deno.env.get('SUPABASE_ANON_KEY')!;
    const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const auth = req.headers.get('Authorization') ?? '';

    const caller = createClient(url, anon, { global: { headers: { Authorization: auth } } });
    const { data: u } = await caller.auth.getUser();
    if (!u?.user?.email) return json({ error: 'No autenticado' }, 401);

    const admin = createClient(url, service);
    const { data: me } = await admin.from('docs').select('data').eq('coll', 'usuarios')
      .filter('data->>email', 'ilike', u.user.email).maybeSingle();
    if (!me || me.data.perfil !== 'sistemas' || me.data.activo !== true) return json({ error: 'Sin permiso' }, 403);

    const { accion, email, nombre, password } = await req.json();
    const mail = String(email ?? '').trim().toLowerCase();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(mail)) return json({ error: 'Correo inválido' }, 400);
    if (mail === u.user.email.toLowerCase()) return json({ error: 'No puede restablecer su propia cuenta desde aquí' }, 400);
    if (typeof password !== 'string' || password.length < 10) return json({ error: 'La contraseña temporal debe tener al menos 10 caracteres' }, 400);
    if (accion !== 'crear' && accion !== 'reset') return json({ error: 'Acción inválida' }, 400);

    const { data: reg } = await admin.from('docs').select('id').eq('coll', 'usuarios')
      .filter('data->>email', 'ilike', mail).maybeSingle();
    if (!reg) return json({ error: 'El correo no está registrado en Usuarios y permisos' }, 400);

    const meta = { nombre: nombre ?? '', must_change: true };
    const created = await admin.auth.admin.createUser({ email: mail, password, email_confirm: true, user_metadata: meta });
    if (created.error) {
      // Ya existe en Auth: se le asigna la nueva contraseña temporal
      const list = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });
      const ex = list.data?.users?.find((x) => x.email?.toLowerCase() === mail);
      if (!ex) return json({ error: created.error.message }, 400);
      const upd = await admin.auth.admin.updateUserById(ex.id, { password, user_metadata: { ...ex.user_metadata, ...meta } });
      if (upd.error) return json({ error: upd.error.message }, 400);
      await admin.auth.admin.signOut(ex.id).catch(() => {});
    }
    return json({ ok: true });
  } catch (e) {
    return json({ error: String((e as Error).message ?? e) }, 500);
  }
});
