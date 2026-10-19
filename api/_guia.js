// api/_guia.js
// Guía de uso de la app de Gata Maula para el asistente. Si se cambia o agrega una pantalla,
// hay que actualizar este texto para que la IA explique lo que realmente existe.

export const PANTALLAS_IR = ['mercaderia', 'desperdicio', 'stock', 'pedidos', 'recetas', 'caja', 'ingresos', 'precios', 'ventas', 'alertas', 'eerr', 'calendario'];

export const GUIA = `GUÍA DE LA APP (lo único que existe; no inventes pantallas ni botones que no estén acá)

Entrada: se entra con usuario y contraseña (cada persona tiene la suya). Arriba a la izquierda está "🔓 Salir" y arriba a la derecha "⚙️" (ajustes). Después del ingreso se ve la pantalla de inicio con botones. Cada pantalla tiene un botón "Volver" abajo.
Quién ve qué: el ADMIN ve todo. El ENCARGADO ve todo menos "Estado de resultados" y "Calendario de pagos". COCINA solo ve: Recetas (sin precios; puede crear y editar las suyas), Desperdicio, Stock y Pedidos.

1) REGISTRAR MERCADERÍA (admin y encargado) — [[ir:mercaderia]]
Está en el inicio, en la tarjeta "Registrar mercadería". Sirve para cargar una factura o remito de un proveedor sacándole una foto.
Pasos: tocar Cámara (sacar foto), Galería (elegir una foto), PDF (subir el PDF) o Pegar imagen (en iPhone: en Fotos copiar la imagen de la factura, volver a la app y tocar "Pegar imagen"). Después tocar "Analizar con IA". La IA lee el documento y se abre la pantalla "Revisá los datos".
En "Revisá los datos": controlar el Tipo (factura o remito), el Proveedor, la Fecha, el número, los productos (se pueden corregir o agregar con "+ Agregar producto"), el total de la factura (con IVA incluido, tal cual el papel), el IVA de la factura, si fue pagada (si no, queda pendiente de pago; si sí, elegir el medio de pago) y Observaciones. Al final "Confirmar y guardar".
Al confirmar: se actualizan los precios de costo y se suma la mercadería al stock, y se registra el gasto. La pantalla de resultado avisa si quedaron productos sin mínimo de stock y si alguna línea no se lleva en stock.

2) DESPERDICIO (todos) — [[ir:desperdicio]]
Para anotar mercadería que se tiró o se perdió. Se elige el Insumo (escribir para buscarlo), la Cantidad, el Motivo (ej. se venció, se rompió) y la Fecha, y se toca "Guardar desperdicio". Eso descuenta la cantidad del stock.

3) STOCK (todos) — [[ir:stock]]
Lista de todos los insumos agrupados por categoría (vermut, cerveza y sin alcohol, fiambres, quesos, kutsi, cocina, panes, limpieza, descartables). Cada categoría es un desplegable: tocarla para abrirla. Arriba hay un buscador ("Buscar insumo...").
Para corregir la cantidad que hay (después de contar): cambiar el número que está a la derecha del producto y tocar afuera o apretar Enter; se guarda solo.
Si un producto está en el mínimo o por debajo, aparece en rojo con "⚠️ PEDIR".
Admin y encargado además ven el botón ⚙ en cada producto: ahí se carga el stock mínimo (cuando baje de ese número aparece en Pedidos; con 0 no avisa), si se mide en kilos o unidades, el proveedor al que se le pide, los días de pedido y la cantidad que se suele pedir. También ven arriba la sección "Sin mínimo cargado" con los productos que todavía no tienen mínimo.

4) PEDIDOS (todos) — [[ir:pedidos]]
Muestra lo que hay que pedir, o sea los productos que están en el mínimo o por debajo. Está ordenado por stock (fiambres, quesos, vermut, limpieza, descartables, panes...) y dentro de cada uno por proveedor, con los días de pedido. Cada proveedor tiene "Copiar pedido" y "Mandar por WhatsApp" para armar el mensaje del pedido. El botón Pedidos del inicio muestra un numerito rojo con la cantidad de productos a pedir. Cuando llega la mercadería hay que actualizar el stock (en Stock, o cargando la factura si se es admin/encargado).

5) RECETAS (todos; admin y encargado las editan, cocina solo las mira) — [[ir:recetas]]
Cocina ve la lista de recetas agrupada por categoría, con un buscador (por nombre de receta o ingrediente). Al tocar una receta se ven los ingredientes con la cantidad de cada uno y la preparación paso a paso. No muestra costos ni precios. Cocina puede crear recetas nuevas con el botón "+ Nueva receta" (nombre, categoría, ingredientes con su cantidad en gramos/ml o unidades, y preparación) y modificar con el botón "Editar" solo las que fueron creadas por cocina (llevan la marca "creada por cocina"). Las recetas oficiales no las puede modificar. El costo y el precio de carta los carga el administrador, que revisa las recetas nuevas.
Para admin y encargado: lista de platos y preparaciones con su costo. "+ Nueva receta": nombre del producto, categoría en la carta, preparación (opcional), margen objetivo, merma, insumos de la receta (con "+ Agregar insumo" y la cantidad de cada uno) y el precio en la carta. Se guarda con "Guardar receta". El costo se calcula solo con los precios de los insumos.

6) CAJA DIARIA (admin y encargado) — [[ir:caja]]
Cierre de caja del día: elegir la fecha y cargar lo cobrado en Tarjeta crédito, Tarjeta débito, Transferencia, QR Posnet, QR Mercado Pago y Efectivo. El total se suma solo. "Guardar cierre". Si ya había un cierre para esa fecha, lo reemplaza.

7) INGRESOS / EGRESOS (admin y encargado) — [[ir:ingresos]]
Para cargar a mano un gasto o un ingreso que no vino por factura. "+ Cargar movimiento": fecha, proveedor (opcional), concepto (ej. FIAMBRES Y QUESOS, LUZ, PERSONAL), monto y "¿Cómo se registra?" (A pagar = queda como deuda con el proveedor; Pagado en efectivo; Pagado por banco/transferencia; Otra deuda; Otro ingreso). Opcional: número de factura y observaciones. "Guardar".

8) INSUMOS Y PRECIOS (admin y encargado) — [[ir:precios]]
Es la lista de insumos con su precio de costo. Cuando un proveedor pasa una lista nueva se cambia el precio acá y las recetas se recalculan solas. Si el aumento supera el 7% aparece una alerta. "+ Nuevo insumo" crea un insumo nuevo (categoría, descripción, marca, precio y si se mide en kg o unidad).

9) ALERTAS (admin y encargado) — [[ir:alertas]]
Dos listas: aumentos de precio de más de 7% (después de hablar con el proveedor se toca "Ya lo hablé" para sacar la alerta) y platos con margen bajo (menos de 65%).

10) ESTADO DE RESULTADOS (solo admin) — [[ir:eerr]]
Resultado del negocio por mes o por año, con la pestaña "Resultados" y la pestaña "Estado financiero". El botón "Cargar datos del mes" sirve para los datos que no salen solos de las facturas y la caja.

11) CALENDARIO DE PAGOS (solo admin) — [[ir:calendario]]
Pagos pendientes a proveedores por fecha de vencimiento. "+ Agregar pago" para sumar uno, se marca como pagado confirmando el medio de pago, y "Ver pagados recientes" muestra los ya pagados.

11b) VENTAS POSTBERRY (admin y encargado ven el análisis; solo el admin sube los archivos) — [[ir:ventas]]
Muestra qué se vende en el local, con datos del sistema de ventas Postberry: productos más y menos vendidos, familias (rubros), ventas por día de la semana y por hora, y un control de caja que compara Postberry con el cierre de caja que cargan en la app (marca con ⚠️ los días con diferencia de $500 o más).
Para actualizar los datos (solo el admin): en Postberry exportar a Excel los reportes "ventas_detalle" y "movcaja" del mismo período, y en esta pantalla elegir los dos archivos y tocar "Subir y reemplazar el período". Lo ya cargado en esas fechas se reemplaza, no se duplica. Los datos no se actualizan solos: cubren hasta la última fecha subida.
Para ver el análisis se eligen las fechas Desde y Hasta y se toca "Ver análisis". El día de negocio termina a las 6 de la mañana (lo de madrugada cuenta para el día anterior).

12) ASISTENTE IA
Es este chat: responde dudas de cómo usar la app y, para admin y encargado, también consultas sobre los datos del negocio (stock, ventas por día, márgenes). Solo mira, no cambia nada.

DUDAS FRECUENTES
- "Se me cargó mal una cantidad de stock": corregir el número en Stock.
- "No me aparece un producto en Pedidos": tiene que tener un stock mínimo mayor a 0 y estar en ese mínimo o por debajo. Admin y encargado lo configuran con el ⚙ en Stock.
- "No encuentro un insumo": usar el buscador; si no existe, el admin o encargado puede crearlo en Insumos y precios con "+ Nuevo insumo".
- "Me equivoqué en una factura ya confirmada" o cualquier cosa que no se pueda deshacer desde una pantalla: avisarle al administrador (Lautaro).
`;
