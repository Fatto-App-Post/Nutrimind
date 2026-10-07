import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// Supabase PROD project ref: every other project (DEV, local) talks to the OFF staging server.
const PROD_PROJECT_REF = 'ynnlfxgehbtlneiknrfr';
const OFF_BASE_URI_DEV = 'https://world.openfoodfacts.net';
const OFF_BASE_URI_PROD = 'https://world.openfoodfacts.org';
const OFF_TIMEOUT_MS = 10_000;
const BARCODE_RE = /^[0-9]{8,14}$/; // same as the foods_barcode_check constraint
const SOURCE = 'openfoodfacts';

class HttpError extends Error {
  constructor(public status: number, public code: string, message: string, public headers: Record<string, string> = {}) {
    super(message);
  }
}

const json = (body: unknown, status = 200, extraHeaders: Record<string, string> = {}) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, ...extraHeaders, 'Content-Type': 'application/json' },
  });

// ---------------------------------------------------------------------------
// Open Food Facts
// ---------------------------------------------------------------------------

function offConfig() {
  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const isProd = supabaseUrl.includes(PROD_PROJECT_REF);
  const baseUri = (Deno.env.get('OFF_BASE_URI') ?? (isProd ? OFF_BASE_URI_PROD : OFF_BASE_URI_DEV)).replace(/\/+$/, '');
  const userAgent = Deno.env.get('OFF_USER_AGENT') ?? (isProd ? 'Nutrimind/0.1' : 'Nutrimind/0.1-dev');

  // The staging server (.net) sits behind HTTP basic auth (off/off).
  const isStaging = new URL(baseUri).hostname.endsWith('openfoodfacts.net');
  const username = Deno.env.get('OFF_USERNAME') ?? (isStaging ? 'off' : undefined);
  const password = Deno.env.get('OFF_PASSWORD') ?? (isStaging ? 'off' : undefined);

  const headers: Record<string, string> = { 'User-Agent': userAgent, Accept: 'application/json' };
  if (username && password) {
    headers.Authorization = `Basic ${btoa(`${username}:${password}`)}`;
  }
  return { baseUri, headers };
}

async function fetchOffProduct(barcode: string) {
  const { baseUri, headers } = offConfig();
  const url = `${baseUri}/api/v2/product/${barcode}`;

  let res: Response;
  try {
    res = await fetch(url, { headers, signal: AbortSignal.timeout(OFF_TIMEOUT_MS) });
  } catch (err) {
    console.error('OFF request failed:', url, err);
    throw new HttpError(503, 'upstream_unavailable', 'OpenFoodFacts is unreachable, retry later');
  }

  // v2 answers 404 (with status: 0) for unknown barcodes.
  if (res.status === 404) {
    await res.body?.cancel();
    throw new HttpError(404, 'product_not_found', 'Product not found on OpenFoodFacts');
  }
  if (res.status === 429 || res.status === 502 || res.status === 503 || res.status === 504) {
    await res.body?.cancel();
    const retryAfter = res.headers.get('Retry-After');
    throw new HttpError(
      res.status,
      res.status === 429 ? 'upstream_rate_limited' : 'upstream_unavailable',
      `OpenFoodFacts temporarily unavailable (HTTP ${res.status}), retry later`,
      retryAfter ? { 'Retry-After': retryAfter } : {},
    );
  }
  if (!res.ok) {
    await res.body?.cancel();
    console.error('OFF unexpected status:', url, res.status);
    throw new HttpError(502, 'upstream_error', `OpenFoodFacts error (HTTP ${res.status})`);
  }

  let data: any;
  try {
    data = await res.json();
  } catch {
    throw new HttpError(502, 'upstream_error', 'OpenFoodFacts returned an invalid response');
  }
  if (data?.status !== 1 || !data.product) {
    throw new HttpError(404, 'product_not_found', 'Product not found on OpenFoodFacts');
  }
  return { product: data.product, status: data.status as number, statusVerbose: (data.status_verbose ?? null) as string | null };
}

// ---------------------------------------------------------------------------
// Mapping OFF product -> public.foods row (respecting the table's CHECK constraints)
// ---------------------------------------------------------------------------

const num = (v: unknown): number | null => {
  const n = typeof v === 'string' ? parseFloat(v) : v;
  return typeof n === 'number' && Number.isFinite(n) ? n : null;
};
const inRange = (v: number | null, min: number, max: number) => (v !== null && v >= min && v <= max ? v : null);
const text = (v: unknown, max?: number): string | null => {
  if (typeof v !== 'string') return null;
  const s = v.trim();
  if (!s) return null;
  return max ? s.slice(0, max) : s;
};
const round = (v: number | null, digits: number) => (v === null ? null : Number(v.toFixed(digits)));

// I nomi dei 14 allergeni obbligatori nell'UE. Il catalogo esterno li
// espone come tag canonici ("en:milk"), indipendenti dalla lingua in cui
// il prodotto è stato inserito: tradurli dai tag è l'unico modo
// affidabile di mostrarli in italiano. Il campo di testo libero, invece,
// resta nella lingua di chi ha inserito il prodotto (per la Nutella si
// leggeva "lait, fruits à coque, soja").
const ALLERGEN_IT: Record<string, string> = {
  gluten: 'glutine',
  crustaceans: 'crostacei',
  eggs: 'uova',
  fish: 'pesce',
  peanuts: 'arachidi',
  soybeans: 'soia',
  milk: 'latte',
  nuts: 'frutta a guscio',
  celery: 'sedano',
  mustard: 'senape',
  'sesame-seeds': 'sesamo',
  sulphur: 'solfiti',
  'sulphur-dioxide-and-sulphites': 'solfiti',
  lupin: 'lupini',
  molluscs: 'molluschi',
};

/// Allergeni in italiano a partire dai tag; se non ci sono tag si usa il
/// testo libero, preferendo la versione italiana quando esiste.
function allergenText(tags: unknown, localized: unknown, fallback: unknown): string | null {
  const list = Array.isArray(tags) ? tags.filter((t): t is string => typeof t === 'string') : [];
  const names = [
    ...new Set(
      list.map((tag) => {
        const slug = tag.includes(':') ? tag.slice(tag.indexOf(':') + 1) : tag;
        // Un tag "it:..." è già in italiano: si usa così, con i trattini
        // sostituiti dagli spazi.
        return ALLERGEN_IT[slug] ?? slug.replace(/-/g, ' ');
      }),
    ),
  ];
  if (names.length > 0) return names.join(', ');
  return text(localized) ?? text(fallback);
}

/// Il catalogo esterno scrive spesso la porzione in inglese
/// ("1 serving (47.5 g)"): in quel caso la si riscrive in italiano usando
/// la quantità già normalizzata. Le porzioni descrittive ("1 vasetto da
/// 125 g") si lasciano come sono.
function servingLabel(raw: unknown, servingG: number | null): string | null {
  const label = text(raw, 60);
  if (label === null) return servingG === null ? null : `Porzione ${servingG} g`;
  if (/^\s*\d*[.,]?\d*\s*servings?\b/i.test(label)) {
    return servingG === null ? null : `Porzione ${servingG} g`;
  }
  return label;
}

function mapProduct(barcode: string, product: any, status: number, statusVerbose: string | null, payloadHash: string) {
  const n = product.nutriments ?? {};

  let kcal = num(n['energy-kcal_100g']);
  if (kcal === null) {
    const kj = num(n['energy-kj_100g']) ?? num(n['energy_100g']);
    if (kj !== null) kcal = kj / 4.184;
  }
  const protein = inRange(num(n.proteins_100g), 0, 100);
  const carbs = inRange(num(n.carbohydrates_100g), 0, 100);
  const fat = inRange(num(n.fat_100g), 0, 100);
  kcal = inRange(kcal, 0, 900);

  // kcal/protein/carbs/fat are NOT NULL: never store invented zeros for a product without nutrition data.
  if (kcal === null || protein === null || carbs === null || fat === null || protein + carbs + fat > 100.5) {
    throw new HttpError(404, 'incomplete_product', 'Product on OpenFoodFacts has missing or invalid nutrition data');
  }

  let sugars = inRange(num(n.sugars_100g), 0, 100);
  if (sugars !== null && sugars > carbs) sugars = null; // foods_sugars_le_carbs

  const name =
    text(product.product_name_it, 160) ??
    text(product.product_name, 160) ??
    text(product.product_name_en, 160) ??
    text(product.generic_name, 160) ??
    `Prodotto ${barcode}`;
  const brand = text(typeof product.brands === 'string' ? product.brands.split(',')[0] : null, 120);
  const servingG = num(product.serving_quantity);
  const code = text(product.code, 64) ?? barcode;

  return {
    name: name.length >= 2 ? name : `Prodotto ${barcode}`,
    brand,
    barcode,
    source: SOURCE,
    source_id: code,
    verification: 'unverified',
    kcal: round(kcal, 2),
    protein_g: round(protein, 2),
    carbs_g: round(carbs, 2),
    fat_g: round(fat, 2),
    fiber_g: round(inRange(num(n.fiber_100g), 0, 100), 2),
    sugars_g: round(sugars, 2),
    saturated_fat_g: round(inRange(num(n['saturated-fat_100g']), 0, 100), 2),
    salt_g: round(inRange(num(n.salt_100g), 0, 100), 3),
    serving_g: servingG !== null && servingG > 0 && servingG <= 5000 ? round(servingG, 2) : null,
    serving_label: servingLabel(
      product.serving_size,
      servingG !== null && servingG > 0 && servingG <= 5000 ? round(servingG, 2) : null,
    ),
    is_active: true,
    external_code: code,
    external_api_version: 'v2',
    external_last_synced_at: new Date().toISOString(),
    external_payload_hash: payloadHash,
    external_last_status: status,
    external_last_status_verbose: statusVerbose,
    external_raw_data: product,
    generic_name: text(product.generic_name),
    quantity_text: text(product.quantity),
    serving_size_text: text(product.serving_size),
    product_quantity: num(product.product_quantity),
    product_quantity_unit: text(product.product_quantity_unit),
    ingredients_text: text(product.ingredients_text_it) ?? text(product.ingredients_text),
    allergens_text: allergenText(product.allergens_tags, product.allergens_text_it, product.allergens),
    traces_text: allergenText(product.traces_tags, product.traces_text_it, product.traces),
    labels_text: text(product.labels),
    categories_text: text(product.categories),
    main_category: text(product.main_category),
    countries_text: text(product.countries),
    origins_text: text(product.origins),
    packaging_text: text(product.packaging),
    completeness: num(product.completeness),
    nutriscore_grade: text(product.nutriscore_grade),
    ecoscore_grade: text(product.ecoscore_grade),
    nova_group: inRange(num(product.nova_group), 1, 4),
  };
}

async function sha256(value: unknown) {
  const bytes = new TextEncoder().encode(JSON.stringify(value));
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

// Best effort: the food row is already usable, so failures here are only logged.
async function writeNormalizedData(admin: SupabaseClient, foodId: string, sourceCode: string, product: any, payloadHash: string) {
  const tagGroups: [string, unknown][] = [
    ['category', product.categories_tags], ['brand', product.brands_tags], ['label', product.labels_tags],
    ['allergen', product.allergens_tags], ['trace', product.traces_tags], ['additive', product.additives_tags],
    ['country', product.countries_tags], ['origin', product.origins_tags], ['packaging', product.packaging_tags],
  ];
  const tagRows = tagGroups.flatMap(([tagType, values]) =>
    [...new Set(Array.isArray(values) ? values.filter((t): t is string => typeof t === 'string') : [])]
      .map((tag, position) => ({ food_id: foodId, tag_type: tagType, tag, position })),
  );

  const n = product.nutriments ?? {};
  const nutrientRows = Object.entries(n)
    .filter(([key, value]) => typeof value === 'number' && !/_(100g|100ml|serving|unit|value|prepared.*)$/.test(key))
    .map(([key, value]) => ({
      food_id: foodId,
      nutrient_key: key,
      value: value as number,
      unit: text(n[`${key}_unit`]),
      per_100g: num(n[`${key}_100g`]),
      per_100ml: num(n[`${key}_100ml`]),
      per_serving: num(n[`${key}_serving`]),
    }));

  const writes: PromiseLike<{ error: unknown }>[] = [
    admin.from('food_snapshots').upsert(
      { food_id: foodId, source: SOURCE, source_code: sourceCode, api_version: 'v2', response_hash: payloadHash, http_status: 200, payload: product },
      { onConflict: 'food_id,response_hash' },
    ),
  ];
  if (tagRows.length) writes.push(admin.from('food_tags').insert(tagRows));
  if (nutrientRows.length) writes.push(admin.from('food_nutrients').upsert(nutrientRows, { onConflict: 'food_id,nutrient_key' }));

  for (const result of await Promise.allSettled(writes)) {
    const error = result.status === 'rejected' ? result.reason : result.value.error;
    if (error) console.error('Normalized OFF data write failed:', foodId, error);
  }
}

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------

async function findExisting(admin: SupabaseClient, barcode: string) {
  const { data, error } = await admin
    .from('foods')
    .select('id')
    .eq('barcode', barcode)
    .eq('is_active', true)
    .order('trust_level', { ascending: false })
    .order('created_at', { ascending: true })
    .limit(1)
    .maybeSingle();
  if (error) throw error;
  return data as { id: string } | null;
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    if (req.method !== 'POST') {
      throw new HttpError(405, 'method_not_allowed', 'Use POST');
    }

    // Service-role client: bypasses RLS, so it must only be used after the caller's JWT is validated.
    const admin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      { auth: { persistSession: false, autoRefreshToken: false } },
    );

    const jwt = req.headers.get('Authorization')?.replace(/^Bearer\s+/i, '');
    if (!jwt) throw new HttpError(401, 'unauthorized', 'Unauthorized');
    const { data: { user }, error: userError } = await admin.auth.getUser(jwt);
    if (userError || !user) throw new HttpError(401, 'unauthorized', 'Unauthorized');

    const body = await req.json().catch(() => null);
    const barcode = typeof body?.barcode === 'string' ? body.barcode.trim() : '';
    if (!BARCODE_RE.test(barcode)) {
      throw new HttpError(400, 'invalid_barcode', 'Barcode must be 8-14 digits');
    }

    const existing = await findExisting(admin, barcode);
    if (existing) {
      return json({ food_id: existing.id, imported: false });
    }

    const { product, status, statusVerbose } = await fetchOffProduct(barcode);
    const payloadHash = await sha256(product);
    const row = { ...mapProduct(barcode, product, status, statusVerbose, payloadHash), created_by: user.id };

    const { data: newFood, error: insertError } = await admin.from('foods').insert(row).select('id').single();

    if (insertError) {
      // Concurrent import of the same barcode: return the row the other request created.
      if (insertError.code === '23505') {
        const winner = await findExisting(admin, barcode);
        if (winner) return json({ food_id: winner.id, imported: false });
        throw new HttpError(409, 'conflict', 'A food with this OpenFoodFacts code already exists but is inactive');
      }
      if (insertError.code === '54000') {
        throw new HttpError(429, 'rate_limited', 'Too many foods created in the last 24 hours');
      }
      throw insertError;
    }

    await writeNormalizedData(admin, newFood.id, row.source_id, product, payloadHash);

    return json({ food_id: newFood.id, imported: true });
  } catch (error) {
    if (error instanceof HttpError) {
      if (error.status >= 500) console.error('Error importing from OFF:', error.message);
      return json({ error: error.message, code: error.code }, error.status, error.headers);
    }
    console.error('Error importing from OFF:', error);
    return json({ error: 'Internal error', code: 'internal_error' }, 500);
  }
});
