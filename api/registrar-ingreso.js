// api/registrar-ingreso.js
// Reemplaza el POST a Apps Script (action:'registrarIngreso'). Verifica la
// sesión de Supabase del usuario, resuelve su usuario_id/rol, y delega toda
// la escritura transaccional (proveedor + insumos + stock + movimientos +
// ingresos_egresos) a la función RPC registrar_ingreso_factura, que corre
// con la service_role key para poder escribir en varias tablas atómicamente.

import { supabaseAdmin, requireUsuario } from './_auth.js';

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'Método no permitido' });

  try {
    const admin = supabaseAdmin();
    const { usuario_id } = await requireUsuario(req, admin, ['admin', 'encargado']);

    const payload = req.body;
    if (!payload || !Array.isArray(payload.productos) || payload.productos.length === 0) {
      return res.status(400).json({ error: 'Faltan productos en el pedido.' });
    }

    const { data, error } = await admin.rpc('registrar_ingreso_factura', {
      p_usuario_id: usuario_id,
      p_payload: payload
    });

    if (error) {
      return res.status(400).json({ error: error.message });
    }

    return res.status(200).json({ success: true, resultado: data });
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Error interno.' });
  }
}
