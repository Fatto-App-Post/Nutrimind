import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      { global: { headers: { Authorization: req.headers.get('Authorization')! } } }
    );

    const { data: { user }, error: userError } = await supabaseClient.auth.getUser();
    if (userError || !user) {
      throw new Error('Unauthorized');
    }

    // Check if user is admin
    const { data: profile } = await supabaseClient
      .from('profiles')
      .select('role')
      .eq('id', user.id)
      .single();

    if (profile?.role !== 'admin') {
      throw new Error('Admin only');
    }

    // Get barcodes to sync from food_off_sync_log
    const { data: pendingSyncs } = await supabaseClient
      .from('food_off_sync_log')
      .select('barcode, id')
      .eq('status', 'pending')
      .lte('next_retry_at', new Date().toISOString())
      .limit(50);

    if (!pendingSyncs || pendingSyncs.length === 0) {
      return new Response(
        JSON.stringify({ synced: 0, message: 'No pending syncs' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    let synced = 0;
    let errors = 0;

    for (const sync of pendingSyncs) {
      try {
        const offUrl = `https://world.openfoodfacts.org/api/v0/product/${sync.barcode}.json`;
        const offResponse = await fetch(offUrl);
        
        if (!offResponse.ok) {
          await supabaseClient
            .from('food_off_sync_log')
            .update({
              status: 'failed',
              error_message: 'OFF API error',
              next_retry_at: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
              attempt_count: sync.attempt_count + 1,
            })
            .eq('id', sync.id);
          errors++;
          continue;
        }

        const offData = await offResponse.json();
        
        if (offData.status !== 1 || !offData.product) {
          await supabaseClient
            .from('food_off_sync_log')
            .update({
              status: 'not_found',
              off_status_verbose: 'Product not found on OFF',
              finished_at: new Date().toISOString(),
            })
            .eq('id', sync.id);
          errors++;
          continue;
        }

        const product = offData.product;

        // Update or insert food
        const { error: upsertError } = await supabaseClient
          .from('foods')
          .upsert({
            name: product.product_name || 'Unknown',
            brand: product.brands || null,
            barcode: product.code,
            source: 'off',
            source_id: product.code,
            verification: 'verified',
            verified_by: user.id,
            verified_at: new Date().toISOString(),
            kcal: product.nutriments?.['energy-kcal_100g'] || 0,
            protein_g: product.nutriments?.proteins_100g || 0,
            carbs_g: product.nutriments?.carbohydrates_100g || 0,
            fat_g: product.nutriments?.fat_100g || 0,
            fiber_g: product.nutriments?.fiber_100g || null,
            sugars_g: product.nutriments?.sugars_100g || null,
            saturated_fat_g: product.nutriments?.['saturated-fat_100g'] || null,
            salt_g: product.nutriments?.salt_100g || null,
            serving_g: product.serving_size ? parseFloat(product.serving_size) : null,
            serving_label: product.serving_size || null,
            is_active: true,
          }, {
            onConflict: 'barcode'
          });

        if (upsertError) {
          throw upsertError;
        }

        await supabaseClient
          .from('food_off_sync_log')
          .update({
            status: 'synced',
            off_status_verbose: 'Successfully synced',
            finished_at: new Date().toISOString(),
          })
          .eq('id', sync.id);

        synced++;
      } catch (err) {
        console.error('Error syncing barcode:', sync.barcode, err);
        await supabaseClient
          .from('food_off_sync_log')
          .update({
            status: 'failed',
            error_message: err instanceof Error ? err.message : 'Unknown error',
            next_retry_at: new Date(Date.now() + 60 * 60 * 1000).toISOString(),
            attempt_count: sync.attempt_count + 1,
          })
          .eq('id', sync.id);
        errors++;
      }
    }

    return new Response(
      JSON.stringify({ synced, errors, total: pendingSyncs.length }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (error) {
    console.error('Error in sync-off-batch:', error);
    return new Response(
      JSON.stringify({ error: error instanceof Error ? error.message : 'Unknown error' }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
