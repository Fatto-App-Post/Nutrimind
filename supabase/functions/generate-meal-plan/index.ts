import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface FoodSuggestion {
  food_id: string;
  name: string;
  meal_slot: 'breakfast' | 'lunch' | 'dinner' | 'snack';
  grams: number;
  kcal: number;
  protein_g: number;
  carbs_g: number;
  fat_g: number;
  reason: string;
}

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

    const { patient_id, date, preferences = {} } = await req.json();

    if (!patient_id) {
      throw new Error('patient_id is required');
    }

    // Get patient's macro targets for the day
    const dayOfWeek = new Date(date).getDay(); // 0 = Sunday, 1 = Monday, etc.
    
    const { data: targets } = await supabaseClient
      .from('macro_plan_targets')
      .select('*')
      .eq('day_of_week', dayOfWeek === 0 ? 7 : dayOfWeek) // Convert to 1-7
      .order('meal_slot');

    if (!targets || targets.length === 0) {
      throw new Error('No macro targets found for this day');
    }

    // Get patient's dietary restrictions and preferences
    const { data: settings } = await supabaseClient
      .from('patient_settings')
      .select('dietary_restrictions')
      .eq('user_id', patient_id)
      .single();

    const restrictions = settings?.dietary_restrictions || [];

    // Get patient's favorite foods
    const { data: favorites } = await supabaseClient
      .from('favorite_foods')
      .select('food_id, default_grams, default_slot')
      .eq('patient_id', patient_id)
      .order('use_count', { ascending: false })
      .limit(20);

    // Build meal suggestions based on targets and favorites
    const suggestions: FoodSuggestion[] = [];

    for (const target of targets) {
      const mealSlot = target.meal_slot;
      const targetProtein = target.protein_g;
      const targetCarbs = target.carbs_g;
      const targetFat = target.fat_g;

      // Find foods that match this meal slot and dietary restrictions
      let query = supabaseClient
        .from('foods')
        .select('*')
        .eq('is_active', true)
        .order('trust_level', { ascending: false })
        .limit(10);

      // Apply dietary restrictions
      if (restrictions.includes('vegetarian')) {
        // Would need a vegetarian flag in foods table
      }
      if (restrictions.includes('vegan')) {
        // Would need a vegan flag in foods table
      }
      if (restrictions.includes('gluten_free')) {
        // Would need a gluten_free flag in foods table
      }

      const { data: foods } = await query;

      if (!foods || foods.length === 0) {
        continue;
      }

      // Simple algorithm: pick top trusted foods and calculate portions
      const selectedFood = foods[0];
      const grams = 150; // Default portion
      
      const kcal = (selectedFood.kcal * grams) / 100;
      const protein = (selectedFood.protein_g * grams) / 100;
      const carbs = (selectedFood.carbs_g * grams) / 100;
      const fat = (selectedFood.fat_g * grams) / 100;

      suggestions.push({
        food_id: selectedFood.id,
        name: selectedFood.name,
        meal_slot: mealSlot as any,
        grams,
        kcal: Math.round(kcal),
        protein_g: Math.round(protein * 10) / 10,
        carbs_g: Math.round(carbs * 10) / 10,
        fat_g: Math.round(fat * 10) / 10,
        reason: 'High trust food matching your targets',
      });
    }

    return new Response(
      JSON.stringify({ 
        suggestions,
        date,
        total_kcal: suggestions.reduce((sum, s) => sum + s.kcal, 0),
        total_protein: suggestions.reduce((sum, s) => sum + s.protein_g, 0),
        total_carbs: suggestions.reduce((sum, s) => sum + s.carbs_g, 0),
        total_fat: suggestions.reduce((sum, s) => sum + s.fat_g, 0),
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (error) {
    console.error('Error generating meal plan:', error);
    return new Response(
      JSON.stringify({ error: error instanceof Error ? error.message : 'Unknown error' }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
