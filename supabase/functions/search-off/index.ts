import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// Ricerca nel catalogo esterno (Open Food Facts), usata quando il catalogo
// locale non basta. Restituisce prodotti NORMALIZZATI con le stesse chiavi
// di public.foods: il client li mostra accanto ai risultati locali e, se
// l'utente ne sceglie uno, chiama import-off-barcode con il `barcode`.
//
// La versione precedente restituiva i prodotti grezzi di OFF (dove il
// codice si chiama `code`): il client, cercando `barcode`, li scartava
// tutti e la sezione risultava vuota.
//
// Secret opzionali: OFF_BASE_URI, OFF_USER_AGENT, OFF_USERNAME, OFF_PASSWORD.

const OFF_BASE_URI_DEV = 'https://world.openfoodfacts.net';
const OFF_BASE_URI_PROD = 'https://world.openfoodfacts.org';
const PROD_PROJECT_REF = 'ynnlfxgehbtlneiknrfr';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const json = (body: unknown, status = 200, extraHeaders: Record<string, string> = {}) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, ...extraHeaders, 'Content-Type': 'application/json' },
  });

function offConfig() {
  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const isProd = supabaseUrl.includes(PROD_PROJECT_REF);
  const baseUri = (Deno.env.get('OFF_BASE_URI') ?? (isProd ? OFF_BASE_URI_PROD : OFF_BASE_URI_DEV)).replace(/\/+$/, '');
  const userAgent = Deno.env.get('OFF_USER_AGENT') ?? (isProd ? 'Nutrimind/0.1' : 'Nutrimind/0.1-dev');

  // Il server di staging (.net) è protetto da basic auth (off/off)
  const isStaging = new URL(baseUri).hostname.endsWith('openfoodfacts.net');
  const username = Deno.env.get('OFF_USERNAME') ?? (isStaging ? 'off' : undefined);
  const password = Deno.env.get('OFF_PASSWORD') ?? (isStaging ? 'off' : undefined);

  const headers: Record<string, string> = { 'User-Agent': userAgent, Accept: 'application/json' };
  if (username && password) headers.Authorization = `Basic ${btoa(`${username}:${password}`)}`;
  return { baseUri, headers };
}

const FIELDS = [
  'code', 'product_name', 'product_name_it', 'generic_name', 'brands', 'quantity',
  'serving_size', 'serving_quantity', 'nutriments', 'nutriscore_grade', 'nova_group',
  'image_front_small_url', 'image_front_url',
].join(',');

const num = (v: unknown): number | null => {
  const n = typeof v === 'number' ? v : Number(v);
  return Number.isFinite(n) && n >= 0 ? Math.round(n * 100) / 100 : null;
};

/// Il catalogo esterno scrive spesso la porzione in inglese
/// ("1 serving (47.5 g)"): la si riscrive in italiano quando è solo
/// quella formula, lasciando stare le porzioni descrittive.
function servingLabel(raw: unknown, servingG: number | null): string | null {
  const label = typeof raw === 'string' && raw.trim() ? raw.trim().slice(0, 60) : null;
  if (label === null || /^\s*\d*[.,]?\d*\s*servings?\b/i.test(label)) {
    return servingG === null ? null : `Porzione ${servingG} g`;
  }
  return label;
}

/// Prodotto OFF -> stesse chiavi di public.foods
function mapProduct(product: Record<string, any>) {
  const n = product.nutriments ?? {};
  const name = (product.product_name_it || product.product_name || product.generic_name || '').toString().trim();
  const kcal = num(n['energy-kcal_100g']) ??
    (num(n['energy_100g']) != null ? Math.round(num(n['energy_100g'])! / 4.184) : null);
  return {
    barcode: (product.code ?? '').toString(),
    name,
    brand: (product.brands ?? '').toString().split(',')[0].trim() || null,
    kcal: kcal ?? 0,
    protein_g: num(n.proteins_100g) ?? 0,
    carbs_g: num(n.carbohydrates_100g) ?? 0,
    fat_g: num(n.fat_100g) ?? 0,
    fiber_g: num(n.fiber_100g),
    sugars_g: num(n.sugars_100g),
    saturated_fat_g: num(n['saturated-fat_100g']),
    salt_g: num(n.salt_100g),
    serving_g: num(product.serving_quantity),
    serving_label: servingLabel(product.serving_size, num(product.serving_quantity)),
    quantity_text: (product.quantity ?? null) || null,
    nutriscore_grade: (product.nutriscore_grade ?? null) || null,
    nova_group: num(product.nova_group),
    image_front_url: product.image_front_small_url || product.image_front_url || null,
  };
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const admin = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '');

    const bearer = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
    if (!bearer) return json({ error: 'Unauthorized', code: 'unauthorized' }, 401);
    const { data: { user }, error: userError } = await admin.auth.getUser(bearer);
    if (userError || !user) return json({ error: 'Unauthorized', code: 'unauthorized' }, 401);

    const body = await req.json().catch(() => null);
    const query = (body?.query ?? '').toString().trim();
    const limit = Math.min(Math.max(Number(body?.limit) || 10, 1), 30);
    if (query.length < 2) {
      return json({ error: 'query must be at least 2 characters', code: 'invalid_request' }, 400);
    }

    const { baseUri, headers } = offConfig();
    // Ricerca testuale: /api/v2/search ignora search_terms (restituisce
    // prodotti casuali su tutto il database), quindi serve cgi/search.pl.
    // È l'unico endpoint full-text disponibile anche sullo staging .net;
    // l'alternativa (search.openfoodfacts.org) esiste solo in produzione.
    const url = `${baseUri}/cgi/search.pl?search_terms=${encodeURIComponent(query)}` +
      `&search_simple=1&action=process&json=1&page_size=${limit}&fields=${FIELDS}`;

    let res: Response;
    try {
      res = await fetch(url, { headers, signal: AbortSignal.timeout(12_000) });
    } catch (e) {
      console.error('OFF unreachable:', e instanceof Error ? e.message : e);
      return json({ error: 'Catalogo esterno non raggiungibile', code: 'upstream_unavailable' }, 503);
    }

    if (res.status === 429 || res.status === 502 || res.status === 503 || res.status === 504) {
      const retryAfter = res.headers.get('retry-after');
      return json(
        { error: 'Catalogo esterno momentaneamente non disponibile', code: res.status === 429 ? 'upstream_rate_limited' : 'upstream_unavailable' },
        res.status,
        retryAfter ? { 'Retry-After': retryAfter } : {},
      );
    }
    if (!res.ok) {
      console.error('OFF unexpected status:', res.status, url);
      return json({ error: 'Catalogo esterno non disponibile', code: 'upstream_error' }, 502);
    }

    let data: any;
    try {
      data = await res.json();
    } catch {
      return json({ error: 'Risposta non valida dal catalogo esterno', code: 'upstream_error' }, 502);
    }

    // Senza barcode o senza nome il prodotto non è importabile
    const results = (Array.isArray(data?.products) ? data.products : [])
      .map(mapProduct)
      .filter((p: { barcode: string; name: string }) => p.barcode.length >= 8 && p.name.length > 0);

    // Chi è già in catalogo non viene riproposto: il client lo trova già
    // tra i risultati locali
    const codes = results.map((p: { barcode: string }) => p.barcode);
    let known = new Set<string>();
    if (codes.length) {
      const { data: rows } = await admin.from('foods').select('barcode').in('barcode', codes).eq('is_active', true);
      known = new Set((rows ?? []).map((r: { barcode: string | null }) => r.barcode ?? ''));
    }

    return json({
      results: results.filter((p: { barcode: string }) => !known.has(p.barcode)),
      count: Number(data?.count) || results.length,
    });
  } catch (error) {
    console.error('Error searching catalog:', error instanceof Error ? error.message : error);
    return json({ error: 'Internal error', code: 'internal_error' }, 500);
  }
});
