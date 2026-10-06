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
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: req.headers.get('Authorization')! } } }
    );

    const { data: { user }, error: userError } = await supabaseClient.auth.getUser();
    if (userError || !user) {
      throw new Error('Unauthorized');
    }

    const { barcode } = await req.json();

    if (!barcode || typeof barcode !== 'string') {
      throw new Error('Barcode is required');
    }

    // Fetch from OpenFoodFacts
    const offUrl = `https://world.openfoodfacts.org/api/v0/product/${barcode}.json`;
    const offResponse = await fetch(offUrl);
    
    if (!offResponse.ok) {
      throw new Error('Product not found on OpenFoodFacts');
    }

    const offData = await offResponse.json();
    
    if (offData.status !== 1 || !offData.product) {
      throw new Error('Product not found');
    }

    const product = offData.product;

    // Check if already exists in DB
    const { data: existing } = await supabaseClient
      .from('foods')
      .select('id')
      .eq('barcode', barcode)
      .eq('verification', 'verified')
      .single();

    if (existing) {
      return new Response(
        JSON.stringify({ food_id: existing.id, imported: false }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Insert into foods table
    const { data: newFood, error: insertError } = await supabaseClient
      .from('foods')
      .insert({
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
      })
      .select('id')
      .single();

    if (insertError) {
      throw insertError;
    }

    return new Response(
      JSON.stringify({ food_id: newFood.id, imported: true }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (error) {
    console.error('Error importing from OFF:', error);
    return new Response(
      JSON.stringify({ error: error instanceof Error ? error.message : 'Unknown error' }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
