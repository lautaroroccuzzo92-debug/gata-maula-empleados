// api/cron-stock.js
// Lo llama Vercel todas las noches (ver vercel.json) para sacar la "foto" del stock valorizado del dia.
// Se protege con la variable CRON_SECRET (Vercel la manda sola en el encabezado Authorization).

import { supabaseAdmin } from './_auth.js';

export default async function handler(req, res) {
  const secreto = process.env.CRON_SECRET;
  if (!secreto || req.headers['authorization'] !== 'Bearer ' + secreto) {
    return res.status(401).json({ error: 'No autorizado' });
  }
  try {
    const { data, error } = await supabaseAdmin().rpc('registrar_stock_valorizado');
    if (error) return res.status(500).json({ error: error.message });
    return res.status(200).json({ ok: true, total: data?.total });
  } catch (err) {
    return res.status(500).json({ error: err.message || 'Error interno.' });
  }
}
