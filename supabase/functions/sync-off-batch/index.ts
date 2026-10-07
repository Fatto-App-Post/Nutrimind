import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// Sincronizzazione in blocco dei prodotti in attesa in food_off_sync_log.
// Solo per admin, oppure con la chiave di servizio (job schedulato).
//
// Correzioni rispetto alla versione precedente:
// - `source: 'off'` non esiste nell'enum food_source: ogni upsert veniva
//   rifiutato. Il valore corretto è 'openfoodfacts';
// - gli import automatici nascono 'unverified': marcarli 'verified' senza
//   una revisione umana falsava il livello di affidabilità mostrato in app;
// - `sync.attempt_count` veniva usato senza essere selezionato (NaN);
// - ambiente: su DEV si usa il server di staging, come le altre funzioni;
// - pausa di 6,5 secondi tra le richieste, come chiede Open Food Facts.

const OFF_BASE_URI_DEV = 'https://world.openfoodfacts.net';
const OFF_BASE_URI_PROD = 'https://world.openfoodfacts.org';
const PROD_PROJECT_REF = 'ynnlfxgehbtlneiknrfr';
const BATCH_SIZE = 20;
const PAUSE_MS = 6_500;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
/// Porzione in italiano quando il catalogo esterno usa la formula
/// inglese "1 serving (47.5 g)"; le porzioni descrittive restano.
const servingLabel = (raw: unknown, servingG: number | null): string | null => {
  const label = typeof raw === 'string' && raw.trim() ? raw.trim().slice(0, 60) : null;
  if (label === null || /^\s*\d*[.,]?\d*\s*servings?\b/i.test(label)) {
    return servingG === null ? null : `Porzione ${servingG} g`;
  }
  return label;
};
const num = (v: unknown): number | null => {
  const n = typeof v === 'number' ? v : Number(v);
  return Number.isFinite(n) && n >= 0 ? Math.round(n * 100) / 100 : null;
};

function offConfig() {
  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const isProd = supabaseUrl.includes(PROD_PROJECT_REF);
  const baseUri = (Deno.env.get('OFF_BASE_URI') ?? (isProd ? OFF_BASE_URI_PROD : OFF_BASE_URI_DEV)).replace(/\/+$/, '');
  const userAgent = Deno.env.get('OFF_USER_AGENT') ?? (isProd ? 'Nutrimind/0.1' : 'Nutrimind/0.1-dev');
  const isStaging = new URL(baseUri).hostname.endsWith('openfoodfacts.net');
  const username = Deno.env.get('OFF_USERNAME') ?? (isStaging ? 'off' : undefined);
  const password = Deno.env.get('OFF_PASSWORD') ?? (isStaging ? 'off' : undefined);
  const headers: Record<string, string> = { 'User-Agent': userAgent, Accept: 'application/json' };
  if (username && password) headers.Authorization = `Basic ${btoa(`${username}:${password}`)}`;
  return { baseUri, headers };
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
    const admin = createClient(Deno.env.get('SUPABASE_URL') ?? '', serviceRoleKey);

    // Autorizzazione: chiave di servizio (job) oppure utente admin
    const bearer = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
    if (!bearer) return json({ error: 'Unauthorized', code: 'unauthorized' }, 401);
    if (bearer !== serviceRoleKey) {
      const { data: { user }, error: userError } = await admin.auth.getUser(bearer);
      if (userError || !user) return json({ error: 'Unauthorized', code: 'unauthorized' }, 401);
      const { data: profile } = await admin.from('profiles').select('role').eq('id', user.id).maybeSingle();
      if (profile?.role !== 'admin') return json({ error: 'Forbidden', code: 'forbidden' }, 403);
    }

    const { data: pending, error: pendingError } = await admin
      .from('food_off_sync_log')
      .select('id, barcode, attempt_count')
      .eq('status', 'pending')
      .or(`next_retry_at.is.null,next_retry_at.lte.${new Date().toISOString()}`)
      .order('started_at')
      .limit(BATCH_SIZE);
    if (pendingError) throw pendingError;

    if (!pending || pending.length === 0) {
      return json({ synced: 0, errors: 0, total: 0, message: 'Nessun prodotto in attesa' });
    }

    const { baseUri, headers } = offConfig();
    let synced = 0;
    let errors = 0;

    for (const [i, row] of pending.entries()) {
      if (i > 0) await sleep(PAUSE_MS);
      try {
        const res = await fetch(
          `${baseUri}/api/v2/product/${row.barcode}?fields=code,product_name,product_name_it,brands,quantity,serving_size,serving_quantity,nutriments,nutriscore_grade,nova_group`,
          { headers, signal: AbortSignal.timeout(12_000) },
        );

        if (res.status === 404) {
          await admin.from('food_off_sync_log').update({
            status: 'not_found',
            http_status: 404,
            off_status_verbose: 'Prodotto non presente su Open Food Facts',
            finished_at: new Date().toISOString(),
          }).eq('id', row.id);
          errors++;
          continue;
        }
        if (!res.ok) {
          await admin.from('food_off_sync_log').update({
            status: 'pending',
            http_status: res.status,
            error_message: `HTTP ${res.status}`,
            attempt_count: (row.attempt_count ?? 0) + 1,
            next_retry_at: new Date(Date.now() + 6 * 60 * 60 * 1000).toISOString(),
          }).eq('id', row.id);
          errors++;
          continue;
        }

        const data = await res.json();
        const product = data?.product;
        if (data?.status !== 1 || !product) {
          await admin.from('food_off_sync_log').update({
            status: 'not_found',
            http_status: res.status,
            off_status_verbose: data?.status_verbose ?? 'Prodotto non trovato',
            finished_at: new Date().toISOString(),
          }).eq('id', row.id);
          errors++;
          continue;
        }

        const n = product.nutriments ?? {};
        const kcal = num(n['energy-kcal_100g']) ??
          (num(n['energy_100g']) != null ? Math.round(num(n['energy_100g'])! / 4.184) : null);
        const name = (product.product_name_it || product.product_name || '').toString().trim();
        if (!name || kcal == null) {
          await admin.from('food_off_sync_log').update({
            status: 'not_found',
            http_status: res.status,
            off_status_verbose: 'Dati nutrizionali incompleti',
            finished_at: new Date().toISOString(),
          }).eq('id', row.id);
          errors++;
          continue;
        }

        const { data: food, error: upsertError } = await admin
          .from('foods')
          .upsert({
            name,
            brand: (product.brands ?? '').toString().split(',')[0].trim() || null,
            barcode: product.code,
            source: 'openfoodfacts',
            source_id: product.code,
            external_code: product.code,
            external_api_version: 'v2',
            external_last_synced_at: new Date().toISOString(),
            // Gli import automatici restano da verificare
            verification: 'unverified',
            kcal,
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
            is_active: true,
          }, { onConflict: 'source,source_id' })
          .select('id')
          .single();
        if (upsertError) throw upsertError;

        await admin.from('food_off_sync_log').update({
          status: 'done',
          food_id: food.id,
          http_status: 200,
          api_version: 'v2',
          error_message: null,
          finished_at: new Date().toISOString(),
        }).eq('id', row.id);
        synced++;
      } catch (e) {
        console.error('sync error', row.barcode, e instanceof Error ? e.message : e);
        await admin.from('food_off_sync_log').update({
          status: 'pending',
          error_message: e instanceof Error ? e.message.slice(0, 300) : 'errore',
          attempt_count: (row.attempt_count ?? 0) + 1,
          next_retry_at: new Date(Date.now() + 6 * 60 * 60 * 1000).toISOString(),
        }).eq('id', row.id);
        errors++;
      }
    }

    return json({ synced, errors, total: pending.length });
  } catch (error) {
    console.error('Error syncing batch:', error instanceof Error ? error.message : error);
    return json({ error: 'Internal error', code: 'internal_error' }, 500);
  }
});
