// api/analyze.js
// Proxy serverless (Vercel) hacia la API de Anthropic.
// La API key NUNCA se hardcodea acá: la manda el navegador en el
// header "x-api-key" (el usuario la carga en Ajustes, se guarda en
// localStorage del teléfono, y viaja en cada request).

export const config = {
  api: {
    bodyParser: {
      sizeLimit: '15mb'
    }
  }
};

const SYSTEM_PROMPT = `Sos un asistente que lee facturas y remitos de proveedores de un bar de fiambres y vermut en Argentina (Gata Maula).

Tu única tarea es devolver un JSON con la información del documento. No agregues texto antes ni después, no uses bloques de código markdown, devolvé SOLO el JSON.

Reglas importantes (Argentina):
- Los precios en el documento usan PUNTO para miles y COMA para decimales (ej: "$3.426,63" = 3426.63). Convertí SIEMPRE a número JSON estándar con punto decimal.
- Si el documento tiene datos de AFIP/ARCA (CUIT del emisor, CAE, "Factura A/B/C"), es tipo "FACTURA" y el número de comprobante va en "numero_factura".
- Si el documento es un remito u orden de carga (sin CAE/CUIT de AFIP, solo detalle de mercadería entregada), es tipo "REMITO" y el número va en "numero_remito".
- Fecha en formato YYYY-MM-DD.
- Para cada línea de producto, separá "marca" (marca comercial, ej: "Grasetto", "Zecor") de "descripcion" (el producto en sí, ej: "Mortadela", "Bondiola ahumada"). Si no podés distinguir marca, dejá "marca" vacío y poné todo en "descripcion".
- "categoria" es una categoría comercial general del producto (ej: "FIAMBRES Y QUESOS", "BEBIDAS", "PANIFICADOS", "VERDULERÍA", "LIMPIEZA", "OTROS").
- "kg_litros" es la cantidad en kilogramos o litros si el documento lo especifica así; si el producto se vende por unidad (ej: botellas, cajones) dejá "kg_litros" en null y completá "unidades".
- "precio_unitario" es el precio por kg/litro o por unidad (el que corresponda a como está expresado en el documento).
- "total" es el importe total de esa línea.
- Si un campo no aparece en el documento, usá null (nunca inventes datos).

Formato de salida exacto:
{
  "tipo": "FACTURA" | "REMITO",
  "proveedor": "string",
  "fecha": "YYYY-MM-DD",
  "numero_factura": "string o null",
  "numero_remito": "string o null",
  "productos": [
    {
      "categoria": "string",
      "marca": "string o null",
      "descripcion": "string",
      "kg_litros": number o null,
      "unidades": number o null,
      "precio_unitario": number,
      "total": number
    }
  ]
}`;

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, x-api-key');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Método no permitido' });
  }

  try {
    const apiKey = req.headers['x-api-key'];
    if (!apiKey) {
      return res.status(400).json({ error: 'Falta la API key de Anthropic (header x-api-key).' });
    }

    const { files } = req.body; // [{ mediaType: 'image/jpeg' | 'application/pdf', base64: '...' }]
    if (!files || !Array.isArray(files) || files.length === 0) {
      return res.status(400).json({ error: 'No se recibieron archivos para analizar.' });
    }

    const contentBlocks = files.map((f) => {
      if (f.mediaType === 'application/pdf') {
        return {
          type: 'document',
          source: { type: 'base64', media_type: 'application/pdf', data: f.base64 }
        };
      }
      return {
        type: 'image',
        source: { type: 'base64', media_type: f.mediaType || 'image/jpeg', data: f.base64 }
      };
    });

    contentBlocks.push({
      type: 'text',
      text: 'Analizá este documento (factura o remito) y devolvé el JSON según las instrucciones.'
    });

    const anthropicResp = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01'
      },
      body: JSON.stringify({
        model: 'claude-sonnet-5',
        max_tokens: 4096,
        system: SYSTEM_PROMPT,
        messages: [{ role: 'user', content: contentBlocks }]
      })
    });

    const data = await anthropicResp.json();

    if (!anthropicResp.ok) {
      return res.status(anthropicResp.status).json({
        error: data.error?.message || 'Error llamando a la API de Anthropic'
      });
    }

    const textBlock = (data.content || []).find((b) => b.type === 'text');
    if (!textBlock) {
      return res.status(502).json({ error: 'La IA no devolvió texto.' });
    }

    let cleaned = textBlock.text.trim()
      .replace(/^```json/i, '')
      .replace(/^```/, '')
      .replace(/```$/, '')
      .trim();

    let parsed;
    try {
      parsed = JSON.parse(cleaned);
    } catch (e) {
      return res.status(502).json({ error: 'No se pudo interpretar la respuesta de la IA.', raw: cleaned });
    }

    return res.status(200).json({ success: true, extraido: parsed });
  } catch (err) {
    return res.status(500).json({ error: 'Error interno del proxy: ' + err.message });
  }
}
