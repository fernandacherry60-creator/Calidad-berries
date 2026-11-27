import { createClient } from 'npm:@supabase/supabase-js@2.57.0';

Deno.serve(async (req: Request) => {
  const headers = { 'Content-Type': 'application/json' };
  const respond = (status: number, message: string) =>
    new Response(JSON.stringify({ error: message }), { status, headers });

  if (req.method !== 'POST') return respond(405, 'Método no permitido');

  const token = req.headers.get('Authorization')?.replace(/^Bearer\s+/i, '');
  if (!token) return respond(401, 'Inicia sesión como administradora');

  const url = Deno.env.get('SUPABASE_URL');
  const publishable = Deno.env.get('SUPABASE_ANON_KEY');
  const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !publishable || !service) {
    return respond(500, 'Falta configuración interna de Supabase');
  }

  const admin = createClient(url, service, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const caller = createClient(url, publishable, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data: { user }, error: authError } = await caller.auth.getUser(token);
  if (authError || !user) return respond(401, 'Sesión no válida');

  const { data: profile, error: profileError } = await admin
    .from('cb_profiles')
    .select('role,active')
    .eq('user_id', user.id)
    .maybeSingle();

  if (profileError || profile?.role !== 'admin' || profile.active !== true) {
    return respond(403, 'Solo la administradora puede invitar trabajadores');
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return respond(400, 'Solicitud inválida');
  }

  const email = String(body.email || '').trim().toLowerCase();
  const name = String(body.name || '').trim();
  const puesto = String(body.puesto || '').trim();

  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ||
      name.length < 2 || name.length > 120 ||
      puesto.length < 2 || puesto.length > 100) {
    return respond(400, 'Verifica nombre, puesto y correo');
  }

  const { data: invited, error: inviteError } = await admin.auth.admin.inviteUserByEmail(email, {
    redirectTo: 'calidadberriespro://auth-callback',
    data: { display_name: name, puesto, invited_by: user.id },
  });

  if (inviteError) return respond(400, inviteError.message);
  if (!invited.user) return respond(500, 'No se creó la invitación');

  const { error: saveError } = await admin.from('cb_profiles').upsert({
    user_id: invited.user.id,
    email,
    display_name: name,
    puesto,
    role: 'trabajador',
    active: true,
  }, { onConflict: 'user_id' });

  if (saveError) {
    return respond(500, 'Se envió la invitación, pero no se pudo guardar el perfil: ' + saveError.message);
  }

  return new Response(JSON.stringify({ ok: true, email }), { status: 200, headers });
});
