// api/_auth.js
// Helper compartido por las funciones serverless que necesitan verificar
// quién llama (JWT de Supabase) y su rol, antes de invocar una función RPC
// con la service_role key. Nunca se expone la service_role key al navegador.

import { createClient } from '@supabase/supabase-js';

export function supabaseAdmin() {
  const url = process.env.SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !serviceKey) {
    throw new Error('Faltan las variables de entorno SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY en Vercel.');
  }
  return createClient(url, serviceKey, { auth: { persistSession: false } });
}

// Verifica el Authorization: Bearer <access_token> del pedido y devuelve
// { usuario_id, rol, nombre } si es válido, o lanza con status/message.
export async function requireUsuario(req, admin, rolesPermitidos) {
  const authHeader = req.headers['authorization'] || '';
  const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : null;
  if (!token) {
    const err = new Error('Falta el token de sesión.');
    err.status = 401;
    throw err;
  }

  const { data: userData, error: userErr } = await admin.auth.getUser(token);
  if (userErr || !userData?.user) {
    const err = new Error('Sesión inválida o expirada.');
    err.status = 401;
    throw err;
  }

  const { data: usuario, error: usuarioErr } = await admin
    .from('usuarios')
    .select('id, nombre, rol, activo')
    .eq('id', userData.user.id)
    .single();

  if (usuarioErr || !usuario || !usuario.activo) {
    const err = new Error('Usuario no encontrado o inactivo.');
    err.status = 403;
    throw err;
  }

  if (rolesPermitidos && !rolesPermitidos.includes(usuario.rol)) {
    const err = new Error('No tenés permiso para esta acción.');
    err.status = 403;
    throw err;
  }

  return { usuario_id: usuario.id, rol: usuario.rol, nombre: usuario.nombre };
}
