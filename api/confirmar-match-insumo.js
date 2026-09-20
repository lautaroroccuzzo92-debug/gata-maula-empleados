// api/confirmar-match-insumo.js
// Fusiona dos insumos (ej. un duplicado creado por typo en la descripción de
// una factura) en uno solo, reasignando stock/movimientos/recetas. Reemplaza
// el flujo manual "confirmarMatchPpto" del Apps Script viejo — ver la nota
// en supabase/migrations/0001_init.sql sobre esta simplificación de Fase 1.

import { supabaseAdmin, requireUsuario } from './_auth.js';

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'Método no permitido' });

  try {
    const admin = supabaseAdmin();
    await requireUsuario(req, admin, ['admin', 'encargado']);

    const { insumo_origen_id, insumo_destino_id } = req.body || {};
    if (!insumo_origen_id || !insumo_destino_id) {
      return res.status(400).json({ error: 'Faltan insumo_origen_id / insumo_destino_id.' });
    }

    const { data, error } = await admin.rpc('confirmar_match_insumo', {
      p_insumo_origen_id: insumo_origen_id,
      p_insumo_destino_id: insumo_destino_id
    });

    if (error) return res.status(400).json({ error: error.message });
    return res.status(200).json({ success: true, resultado: data });
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Error interno.' });
  }
}
