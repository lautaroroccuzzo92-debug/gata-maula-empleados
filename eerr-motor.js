// Motor del Estado de Resultados de Gata Maula.
// Replica las formulas de la hoja "EERR" del Excel mensual. Recibe los totales ya sumados
// (ventas de la caja, egresos por concepto y forma, y los datos que se cargan a mano) y
// devuelve la lista de lineas en el mismo orden que el Excel.
(function (global) {
  'use strict';

  function normKey(s) {
    return String(s == null ? '' : s).toUpperCase().normalize('NFD').replace(/[̀-ͯ]/g, '')
      .replace(/[^A-Z0-9 ]/g, ' ').replace(/\s+/g, ' ').trim();
  }

  var BASE = ['deuda_proveedores', 'egreso_banco', 'egreso_efectivo'];          // deuda + banco + efectivo
  var BASE_OD = BASE.concat(['otras_deudas']);                                    // ... + otras deudas
  var PAGOS = ['acred_banco', 'egreso_banco', 'egreso_efectivo'];                 // lineas del estado financiero
  var INGRESOS_NH = ['otros_ingresos', 'acred_banco'];

  // Conceptos que suman tambien "otras deudas" (igual que las formulas del Excel)
  var CON_OTRAS_DEUDAS = {
    'ABONO SISTEMA': 1, 'ADICAPIF': 1, 'ADT SECURITY SERVICES': 1, 'AGUA': 1, 'ANTICIPO GANANCIAS': 1, 'AUTONOMOS': 1,
    'BROMATOLOGA': 1, 'CARGAS SOCIALES APORTES Y CONTRIB': 1, 'DESINFECCION': 1, 'GAS': 1, 'GASTOS BANCARIOS': 1,
    'HONORARIOS PROFESIONALES': 1, 'INTERNET TELEFONIA NUBES': 1, 'LUZ': 1, 'PERSONAL': 1, 'RECOLECCION BASURA': 1,
    'SADAIC': 1, 'SEGUROS': 1, 'URGENCIAS': 1
  };

  // Objetivos que figuran en la columna G del Excel
  var OBJETIVOS = { merc_real: 0.36, costos_var: 0.06, laboral_fin: 0.20, alquiler: 0.04, fijos: 0.06, otros: 0.06, iva: 0.02, resultado: 0.25 };

  // d = { caja:{tc,td,tr,qp,mp,efe}, egr:{ 'CONCEPTO NORMALIZADO|forma': monto }, manual:{...}, desperdicios: n|null }
  function calcular(d) {
    var caja = d.caja || {};
    var man = d.manual || {};
    var egr = d.egr || {};
    var n = function (x) { return Number(x) || 0; };

    function suma(concepto, formas) {
      var k = normKey(concepto), t = 0;
      for (var i = 0; i < formas.length; i++) t += n(egr[k + '|' + formas[i]]);
      return t;
    }
    function sumaConcepto(concepto) {
      return suma(concepto, CON_OTRAS_DEUDAS[normKey(concepto)] ? BASE_OD : BASE);
    }

    function sumaForma(forma) {
      var t = 0, suf = '|' + forma;
      for (var k in egr) { if (k.length >= suf.length && k.slice(-suf.length) === suf) t += n(egr[k]); }
      return t;
    }
    var L = [];     // lineas en orden
    var V = {};     // valores por clave (pesos)
    var P = {};     // porcentajes por clave (fraccion de la venta total)
    var ventaTotal = 0;

    function pct(v) { return ventaTotal ? v / ventaTotal : 0; }
    // Agrega una linea. val/pct pueden ser numeros. tipo: 'titulo' | 'linea' | 'total' | 'resultado' | 'dato'
    function add(key, label, tipo, val, opts) {
      opts = opts || {};
      var p = opts.pct != null ? opts.pct : (opts.sinPct ? null : pct(val));
      V[key] = val;
      P[key] = p;
      L.push({ key: key, label: label, tipo: tipo, valor: val, pct: p, objetivo: opts.objetivo != null ? opts.objetivo : null, nota: opts.nota || null, formato: opts.formato || 'pesos', editable: opts.editable || null });
    }
    function titulo(label) { L.push({ key: null, label: label, tipo: 'titulo', valor: null, pct: null }); }

    // ---------- VENTAS ----------
    var qp = n(caja.qp), tc = n(caja.tc), td = n(caja.td), tr = n(caja.tr), efe = n(caja.efe), mp = n(caja.mp);
    // TOTAL VENTAS A = "monto fiscal" de la planilla de caja (si no esta cargado, la suma de los medios electronicos)
    var totalA = (caja.fiscal != null) ? n(caja.fiscal) : (tc + td + tr + qp);
    var totalB = efe + mp;
    ventaTotal = totalA + efe + mp;
    titulo('VENTAS');
    add('qp', 'QR POSNET', 'linea', qp);
    add('tc', 'TARJETA DE CRÉDITO', 'linea', tc);
    add('td', 'TARJETA DE DÉBITO', 'linea', td);
    add('tr', 'TRANSFERENCIA', 'linea', tr);
    add('totalA', 'TOTAL VENTAS A', 'total', totalA);
    add('efe', 'EFECTIVO', 'linea', efe);
    add('mp', 'QR', 'linea', mp);
    add('totalB', 'TOTAL VENTAS B', 'total', totalB);
    add('venta', 'VENTA TOTAL', 'resultado', ventaTotal);

    titulo('VENTAS POR SECTOR');
    add('v_sand', 'SANDWICHES Y PICADA', 'linea', n(man.ventas_sandwiches), { editable: 'ventas_sandwiches' });
    add('v_verm', 'VERMUT Y OTROS', 'linea', n(man.ventas_vermut), { editable: 'ventas_vermut' });

    // ---------- COSTO VARIABLE POR PRODUCTO ----------
    titulo('COSTO VARIABLE · VERMUT Y OTROS');
    var cVerm = 0;
    ['BEBIDA CON ALCOHOL', 'VERMUT', 'INSUMOS BARRA', 'BEBIDA SIN ALCOHOL'].forEach(function (c) {
      var v = suma(c, BASE); cVerm += v; add('c_' + c, c, 'linea', v);
    });
    add('t_verm', 'TOTAL VERMUT Y OTROS', 'total', cVerm, { nota: n(man.ventas_vermut) ? 'Sobre las ventas del sector: ' + (cVerm / n(man.ventas_vermut) * 100).toFixed(1) + '%' : null });

    titulo('COSTO VARIABLE · SANDWICHES Y PICADA');
    var cSand = 0;
    ['COCINA', 'FIAMBRES Y QUESOS', 'PAN', 'VERDULERIA'].forEach(function (c) {
      var v = suma(c, BASE); cSand += v; add('c_' + c, c, 'linea', v);
    });
    add('t_sand', 'TOTAL SANDWICHES Y PICADA', 'total', cSand, { nota: n(man.ventas_sandwiches) ? 'Sobre las ventas del sector: ' + (cSand / n(man.ventas_sandwiches) * 100).toFixed(1) + '%' : null });

    titulo('COSTO DE MERCADERÍA');
    var stockIni = n(man.stock_inicio), stockFin = n(man.stock_fin);
    var dStock = stockFin - stockIni;
    var comprada = cVerm + cSand;
    add('stock_var', 'STOCK DE MERCADERÍA VS CUENTAS CORRIENTES PROVEEDORES', 'linea', dStock, { nota: 'Stock al inicio: ' + Math.round(stockIni) + ' · al final: ' + Math.round(stockFin) + (man._stock_auto ? ' · automático desde el stock de la app' : ''), editable: 'stock' });
    add('comprada', 'COSTO DE MERCADERÍA COMPRADA', 'total', comprada);
    var real = comprada - dStock;
    add('real', 'COSTO DE MERCADERÍA REAL', 'total', real, { pct: pct(comprada) - pct(dStock), objetivo: OBJETIVOS.merc_real });
    var consumos = n(man.consumos_internos);
    add('consumos', 'COSTO CONSUMOS INTERNOS Y DESCUENTOS', 'linea', consumos, { editable: 'consumos_internos' });
    var comidaPers = suma('COMIDA DE PERSONAL', BASE);
    add('comida', 'COMIDA DE PERSONAL', 'linea', comidaPers);
    var pctSinDesp = P.real - P.consumos - P.comida;
    add('sin_desp', 'COSTO REAL SIN DESPERDICIOS', 'total', pctSinDesp * ventaTotal, { pct: pctSinDesp });
    var desp = (man.desperdicios != null) ? n(man.desperdicios) : n(d.desperdicios);
    add('desp', 'DESPERDICIOS REGISTRADOS', 'linea', desp, { editable: 'desperdicios', nota: (man.desperdicios != null) ? 'Cargado a mano' : 'Suma de los desperdicios cargados en la app' });
    var pctTeo = n(man.costo_teorico_pct);
    add('teorico', 'COSTO TEÓRICO SEGÚN FICHA DE PRODUCTO', 'linea', pctTeo * ventaTotal, { pct: pctTeo, editable: 'costo_teorico_pct', formato: 'pct' });
    var pctAhorro = P.sin_desp - P.teorico - P.desp;
    add('ahorro', 'POSIBILIDAD DE AHORRO', 'total', pctAhorro * ventaTotal, { pct: pctAhorro });
    var utilBruta = ventaTotal - comprada;
    add('util_bruta', 'UTILIDAD BRUTA', 'resultado', utilBruta);

    // ---------- COSTOS VARIABLES ----------
    titulo('COSTOS VARIABLES');
    var cv = 0;
    ['ARANCELES POR VTA CON TARJETAS', 'GASTOS BANCARIOS', 'IMPUESTO AL DEBITO Y CREDITO', 'COMISION MERCADO PAGO', 'INGRESOS BRUTOS', 'CONTRIBUCION MUNICIPAL'].forEach(function (c) {
      var v = sumaConcepto(c); cv += v; add('cv_' + c, c, 'linea', v);
    });
    add('t_cv', 'COSTOS VARIABLES', 'total', cv, { objetivo: OBJETIVOS.costos_var });

    // ---------- MASA SALARIAL ----------
    titulo('MASA SALARIAL');
    var personal = sumaConcepto('PERSONAL');
    var cargas = sumaConcepto('CARGAS SOCIALES - APORTES Y CONTRIB.');
    add('personal', 'PERSONAL', 'linea', personal);
    add('cargas', 'CARGAS SOCIALES - APORTES Y CONTRIB.', 'linea', cargas);
    add('sueldos_cargas', 'TOTAL DE SUELDOS Y CARGAS SOCIALES', 'total', personal + cargas);
    var lab = personal + cargas;
    ['SINDICATO', 'AGUINALDOS, VACACIONES', 'LIQUIDACION FINAL', 'ADELANTOS'].forEach(function (c) {
      var v = sumaConcepto(c); lab += v; add('l_' + c, c, 'linea', v);
    });
    add('laboral_fin', 'COSTO LABORAL FINANCIERO', 'total', lab, { objetivo: OBJETIVOS.laboral_fin });
    var laboralReal = (man.costo_laboral_real != null) ? n(man.costo_laboral_real) : personal;
    add('laboral_real', 'COSTO LABORAL REAL', 'total', laboralReal, { editable: 'costo_laboral_real', nota: (man.costo_laboral_real != null) ? 'Cargado a mano (planilla de sueldos)' : 'Igual a PERSONAL' });

    // ---------- ALQUILER ----------
    titulo('ALQUILER');
    var alq = 0;
    ['ALQUILER', 'EXPENSAS / GASTOS COMUNES'].forEach(function (c) {
      var v = sumaConcepto(c); alq += v; add('a_' + c, c, 'linea', v);
    });
    add('alquiler', 'ALQUILER / GASTOS ASOCIADOS', 'total', alq, { objetivo: OBJETIVOS.alquiler });

    // ---------- COSTOS FIJOS ----------
    titulo('COSTOS FIJOS');
    var fijos = 0;
    ['LUZ', 'AGUA', 'GAS', 'INTERNET, TELEFONIA, NUBES', 'ABONO SISTEMA', 'HONORARIOS PROFESIONALES', 'SEGUROS', 'URGENCIAS', 'AUTONOMOS',
     'ANTICIPO GANANCIAS', 'ADT SECURITY SERVICES', 'ADICAPIF', 'SADAIC', 'BROMATOLOGA', 'DESINFECCION', 'RECOLECCION BASURA'].forEach(function (c) {
      var v = sumaConcepto(c); fijos += v; add('f_' + c, c, 'linea', v);
    });
    add('fijos', 'COSTOS FIJOS', 'total', fijos, { objetivo: OBJETIVOS.fijos });

    // ---------- OTROS GASTOS ----------
    titulo('OTROS GASTOS');
    var otros = 0;
    ['MKT - DJ - SONIDO', 'REDES', 'IMPRENTA, LIBRERÍA', 'DESCARTABLES', 'GASTOS DIARIOS NO CLASIFICADOS', 'INSUMOS DE LIMPIEZA',
     'MANO DE OBRA MANTENIMIENTO', 'INSUMOS DE MANTENIMIENTO', 'CALEFACCIONAMIENTO', 'COMISIONISTA', 'VOUCHER CANJE', 'BAZAR', 'UNIFORMES'].forEach(function (c) {
      var v = sumaConcepto(c); otros += v; add('o_' + c, c, 'linea', v);
    });
    add('otros', 'OTROS GASTOS', 'total', otros, { objetivo: OBJETIVOS.otros });

    var iva = sumaConcepto('IVA');
    add('iva', 'IVA', 'total', iva, { objetivo: OBJETIVOS.iva });

    var resultado = utilBruta - cv - lab - fijos - alq - otros - iva;
    add('resultado', 'RESULTADO', 'resultado', resultado, { objetivo: OBJETIVOS.resultado });

    // ---------- ESTADO FINANCIERO ----------
    titulo('ESTADO FINANCIERO');
    var saldoAnt = n(man.saldo_mes_anterior);
    var ingNH = suma('INGRESOS NO HABITUALES', INGRESOS_NH);
    // Deudas generadas en el mes (con proveedores y otras): la planilla actual no las suma; se usan en 'RESULTADO EN PLATA'
    var deudaGen = sumaForma('deuda_proveedores'), otrasDeudasGen = sumaForma('otras_deudas');
    var totalIngMes = saldoAnt + ingNH;
    add('saldo_ant', 'SALDOS MES ANTERIOR (efectivo y bancos)', 'linea', saldoAnt, { sinPct: true, editable: 'saldo_mes_anterior' });
    add('ing_nh', 'INGRESOS NO HABITUALES', 'linea', ingNH, { sinPct: true });
    add('t_ing_mes', 'TOTAL INGRESOS DEL MES', 'total', totalIngMes, { sinPct: true });
    var egFin = 0;
    ['COMPRA DE BIENES DE USO', 'PAGO DEUDA', 'REMODELACIONES', 'RETIRO SOCIO', 'OTROS EGRESOS', 'PAGO DEUDA PROVEEDORES'].forEach(function (c) {
      var formas = (normKey(c) === 'PAGO DEUDA') ? PAGOS.concat(['otras_deudas']) : PAGOS;
      var v = suma(c, formas); egFin += v; add('e_' + c, c, 'linea', v, { sinPct: true });
    });
    add('t_egr_mes', 'TOTAL EGRESOS DEL MES', 'total', egFin, { sinPct: true });
    var otrosIE = egFin - totalIngMes;
    add('otros_ie', 'OTROS INGRESOS Y EGRESOS', 'total', otrosIE, { sinPct: true });
    var resFinal = resultado - otrosIE;
    add('res_final', 'RESULTADO FINAL (criterio de tu planilla)', 'resultado', resFinal);
    add('deuda_prov_gen', 'Deuda con proveedores generada en el mes', 'linea', deudaGen, { sinPct: true });
    add('otras_deudas_gen', 'Otras deudas generadas en el mes', 'linea', otrasDeudasGen, { sinPct: true });
    var resPlata = resFinal + deudaGen + otrasDeudasGen;
    add('res_plata', 'RESULTADO EN PLATA (sumando la deuda generada)', 'resultado', resPlata, { nota: 'Lo que realmente quedÃ³: el resultado menos lo que se pagÃ³, mÃ¡s lo que se comprÃ³ a crÃ©dito y todavÃ­a no se pagÃ³' });

    titulo('SALDOS AL ÚLTIMO DÍA DEL MES');
    var cajaEfe = efe - suma_todo_efectivo();
    function suma_todo_efectivo() {
      var t = 0;
      for (var k in egr) { if (k.slice(-('|egreso_efectivo').length) === '|egreso_efectivo') t += n(egr[k]); }
      return t;
    }
    add('s_mp', 'MERCADO PAGO', 'linea', n(man.saldo_mercado_pago), { sinPct: true, editable: 'saldo_mercado_pago' });
    add('s_banco', 'BANCO NACIÓN', 'linea', n(man.saldo_banco), { sinPct: true, editable: 'saldo_banco' });
    add('s_caja', 'HAY EN CAJA AL ÚLTIMO DÍA DEL MES', 'linea', cajaEfe, { sinPct: true, nota: 'Efectivo de ventas menos egresos en efectivo' });
    add('s_tarjetas', 'A COBRAR TARJETAS (aprox.)', 'linea', n(man.a_cobrar_tarjetas), { sinPct: true, editable: 'a_cobrar_tarjetas' });
    add('s_banco2', 'SALDO EN EL BANCO AL ÚLTIMO DÍA DEL MES', 'linea', n(man.saldo_banco_fin), { sinPct: true, editable: 'saldo_banco_fin' });
    add('s_fondo', 'FONDO DE INVERSIÓN', 'linea', n(man.fondo_inversion), { sinPct: true, editable: 'fondo_inversion' });
    var sumaSaldos = n(man.saldo_mercado_pago) + n(man.saldo_banco) + cajaEfe + n(man.a_cobrar_tarjetas) + n(man.saldo_banco_fin) + n(man.fondo_inversion);
    add('s_dif', 'DIFERENCIA (saldos vs resultado final)', 'linea', sumaSaldos - resFinal, { sinPct: true });

    // ---------- INDICADORES ----------
    titulo('INDICADORES');
    var margenContrib = 1 - P.real;
    var peq = margenContrib ? (iva + otros + fijos + alq + lab + cv) / margenContrib : 0;
    add('equilibrio', 'PUNTO DE EQUILIBRIO', 'linea', peq, { pct: margenContrib, nota: 'Margen de contribución: ' + (margenContrib * 100).toFixed(1) + '%' });
    var rentReal = ((ventaTotal - peq) * margenContrib) + (lab - laboralReal);
    add('rent_real', 'RENTABILIDAD REAL', 'linea', rentReal);
    var rentNH = rentReal + ingNH;
    add('rent_nh', 'RENTABILIDAD CON INGRESOS NO HABITUALES', 'linea', rentNH);
    var rentObj = rentNH + (pctAhorro * ventaTotal);
    add('rent_obj', 'RENTABILIDAD OBJETIVO', 'linea', rentObj);
    add('rent_dif', 'DIFERENCIA', 'linea', rentNH - rentObj, { sinPct: true });

    return { lineas: L, v: V, p: P, ventaTotal: ventaTotal };
  }

  // Suma varios meses (para el estado de resultados anual): flujos se suman; stock inicial = el del primer mes,
  // stock final y saldos = los del ultimo mes; costo teorico = promedio ponderado por ventas.
  function combinarMeses(meses) {
    var out = { caja: { tc: 0, td: 0, tr: 0, qp: 0, mp: 0, efe: 0 }, egr: {}, manual: {}, desperdicios: 0 };
    var sumKeys = ['ventas_sandwiches', 'ventas_vermut', 'consumos_internos', 'desperdicios', 'costo_laboral_real'];
    var teoNum = 0, teoDen = 0, algunaManualDesp = false, algunLaboral = false;
    meses.forEach(function (m, i) {
      var c = m.caja || {};
      ['tc', 'td', 'tr', 'qp', 'mp', 'efe'].forEach(function (k) { out.caja[k] += Number(c[k]) || 0; });
      for (var k in (m.egr || {})) out.egr[k] = (out.egr[k] || 0) + (Number(m.egr[k]) || 0);
      out.desperdicios += Number(m.desperdicios) || 0;
      var man = m.manual || {};
      sumKeys.forEach(function (k) { if (man[k] != null) out.manual[k] = (out.manual[k] || 0) + Number(man[k]); });
      if (man.desperdicios != null) algunaManualDesp = true;
      if (man.costo_laboral_real != null) algunLaboral = true;
      var venta = (Number(c.tc) || 0) + (Number(c.td) || 0) + (Number(c.tr) || 0) + (Number(c.qp) || 0) + (Number(c.mp) || 0) + (Number(c.efe) || 0);
      if (man.costo_teorico_pct != null) { teoNum += Number(man.costo_teorico_pct) * venta; teoDen += venta; }
      if (i === 0) { out.manual.stock_inicio = man.stock_inicio; out.manual.saldo_mes_anterior = man.saldo_mes_anterior; }
      if (i === meses.length - 1) {
        ['stock_fin', 'saldo_mercado_pago', 'saldo_banco', 'a_cobrar_tarjetas', 'saldo_banco_fin', 'fondo_inversion'].forEach(function (k) { out.manual[k] = man[k]; });
      }
    });
    if (teoDen) out.manual.costo_teorico_pct = teoNum / teoDen;
    if (!algunaManualDesp) delete out.manual.desperdicios;
    if (!algunLaboral) delete out.manual.costo_laboral_real;
    return out;
  }

  global.GM_EERR = { calcular: calcular, combinarMeses: combinarMeses, normKey: normKey };
})(typeof window !== 'undefined' ? window : globalThis);
