import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: req.headers.get('Authorization')! } } }
    );

    // Get user from auth header
    const { data: { user }, error: userError } = await supabaseClient.auth.getUser();
    if (userError || !user) {
      throw new Error('Unauthorized');
    }

    // Parse request body
    const { query, limit = 10 } = await req.json();

    if (!query || typeof query !== 'string') {
      throw new Error('Query parameter is required');
    }

    // Search OpenFoodFacts API
    const offUrl = `https://world.openfoodfacts.org/cgi/search.pl?search_terms=${encodeURIComponent(query)}&search_simple=1&action=process&json=1&page_size=${limit}`;
    
    const offResponse = await fetch(offUrl);
    if (!offResponse.ok) {
      throw new Error('OpenFoodFacts API error');
    }

    const offData = await offResponse.json();
    
    // Transform OFF results to our format
    const results = (offData.products || []).map((product: any) => ({
      name: product.product_name || 'Unknown',
      brand: product.brands || null,
      barcode: product.code || null,
      source: 'off' as const,
      source_id: product.code || null,
      verification: 'unverified' as const,
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
      image_front_url: product.image_front_url || null,
      nutriscore_grade: product.nutriscore_grade || null,
      ecoscore_grade: product.ecoscore_grade || null,
      nova_group: product.nova_group || null,
    }));

    return new Response(
      JSON.stringify({ results }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (error) {
    console.error('Error searching OFF:', error);
    return new Response(
      JSON.stringify({ error: error instanceof Error ? error.message : 'Unknown error' }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
