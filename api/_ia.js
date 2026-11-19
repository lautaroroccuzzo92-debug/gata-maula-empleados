// api/_ia.js
// Ayudas compartidas por las funciones que usan la IA de Anthropic (lectura de facturas y gatito):
// detectar cuando falla porque se acabo el credito de la cuenta, dejar un aviso para el administrador
// (se ve en rojo en la pantalla de inicio) y borrarlo solo cuando la IA vuelve a funcionar.

const TIPO_SIN_CREDITO = 'ia_sin_credito';

// Mensajes de la API de Anthropic que significan "no hay credito"
export function esErrorSinCredito(mensaje) {
  return /credit balance is too low|purchase credits|plans\s*&\s*billing|insufficient.{0,20}credit/i.test(String(mensaje || ''));
}

export const MSG_SIN_CREDITO_USUARIO =
  'La inteligencia artificial está sin crédito en este momento. Avisale a Lautaro para que cargue crédito. ' +
  'Mientras tanto la app sigue funcionando normal, salvo la lectura de facturas con foto y el gatito.';

// Deja (o actualiza) el aviso para el administrador. Nunca rompe la respuesta: si falla, se ignora.
export async function avisarSinCredito(admin, origen) {
  try {
    await admin.rpc('aviso_sistema_registrar', {
      p_tipo: TIPO_SIN_CREDITO,
      p_mensaje: 'La inteligencia artificial se quedó sin crédito (lectura de facturas con foto y gatito). Cargá crédito en console.anthropic.com → Billing y activá la recarga automática.',
      p_origen: origen
    });
  } catch (e) { /* sin aviso, pero el usuario igual ve el mensaje en español */ }
}

// La IA respondio bien: si habia un aviso abierto, se cierra solo.
export async function avisoSinCreditoResuelto(admin) {
  try { await admin.rpc('aviso_sistema_resolver_tipo', { p_tipo: TIPO_SIN_CREDITO }); } catch (e) { /* nada */ }
}
