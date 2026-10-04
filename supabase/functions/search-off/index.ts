// supabase/functions/search-off/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { barcode } = await req.json()
    
    if (!barcode || !/^[0-9]{8,13}$/.test(barcode)) {
      return new Response(
        JSON.stringify({ error: 'Invalid barcode format' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Fetch from OpenFoodFacts
    const offResponse = await fetch(
      `https://world.openfoodfacts.org/api/v2/product/${barcode}`,
      { headers: { 'User-Agent': 'NutriMind/1.0' } }
    )

    if (!offResponse.ok) {
      return new Response(
        JSON.stringify({ error: 'Product not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const offData = await offResponse.json()

    if (offData.status !== 0) {
      const product = offData.product
      
      // Transform to our schema
      const foodData = {
        name: product.product_name_it || product.product_name || product.product_name_en || 'Unknown',
        brand: product.brands?.split(',')[0]?.trim() || null,
        barcode: barcode,
        source: 'openfoodfacts',
        source_id: barcode,
        verification: 'unverified',
        kcal: product.nutriments?.['energy-kcal_100g'] || 0,
        protein_g: product.nutriments?.proteins_100g || 0,
        carbs_g: product.nutriments?.carbohydrates_100g || 0,
        fat_g: product.nutriments?.fat_100g || 0,
        image_front_url: product.image_front_url || null,
        nutriscore_grade: product.nutriscore_grade || null,
        ecoscore_grade: product.ecoscore_grade || null,
        nova_group: product.nova_group || null
      }

      // Cache in Supabase
      const supabase = createClient(
        Deno.env.get('SUPABASE_URL') ?? '',
        Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
        { auth: { autoRefreshToken: false, persistSession: false } }
      )

      const { data: cached, error } = await supabase
        .from('foods')
        .insert({
          name: foodData.name,
          brand: foodData.brand,
          barcode: foodData.barcode,
          source: foodData.source,
          source_id: foodData.source_id,
          verification: foodData.verification,
          kcal: foodData.kcal,
          protein_g: foodData.protein_g,
          carbs_g: foodData.carbs_g,
          fat_g: foodData.fat_g,
          image_front_url: foodData.image_front_url,
          nutriscore_grade: foodData.nutriscore_grade,
          ecoscore_grade: foodData.ecoscore_grade,
          nova_group: foodData.nova_group,
          is_active: true,
          trust_level: 1,
          created_by: null
        })
        .select()
        .single()

      if (error) {
        console.error('Error caching food:', error)
      }

      return new Response(
        JSON.stringify(cached || foodData),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    return new Response(
      JSON.stringify({ error: 'Product not found in OpenFoodFacts' }),
      { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('Error in search-off:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
