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

    const { patient_id, from_date, to_date } = await req.json();

    if (!patient_id || !from_date || !to_date) {
      throw new Error('patient_id, from_date, and to_date are required');
    }

    // Check permissions
    const { data: profile } = await supabaseClient
      .from('profiles')
      .select('role')
      .eq('id', user.id)
      .single();

    const isNutritionist = profile?.role === 'nutritionist';
    const isSelf = user.id === patient_id;

    if (!isSelf && !isNutritionist) {
      // Check if nutritionist has active link
      if (isNutritionist) {
        const { data: link } = await supabaseClient
          .from('patient_links')
          .select('id')
          .eq('patient_id', patient_id)
          .eq('nutritionist_id', user.id)
          .eq('status', 'active')
          .single();

        if (!link) {
          throw new Error('Forbidden');
        }
      } else {
        throw new Error('Forbidden');
      }
    }

    // Get diary entries for the period
    const { data: entries } = await supabaseClient
      .from('diary_entries')
      .select('entry_date, meal_slot, kcal, protein_g, carbs_g, fat_g, food_trust_level')
      .eq('patient_id', patient_id)
      .gte('entry_date', from_date)
      .lte('entry_date', to_date)
      .order('entry_date');

    if (!entries || entries.length === 0) {
      return new Response(
        JSON.stringify({
          period: { from: from_date, to: to_date },
          total_days: 0,
          logged_days: 0,
          adherence_rate: 0,
          daily_breakdown: [],
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Get macro targets for the period
    const { data: targets } = await supabaseClient
      .from('macro_plan_targets')
      .select('*')
      .in('day_of_week', [1, 2, 3, 4, 5, 6, 7]);

    // Group entries by date and meal slot
    const byDate = new Map<string, any>();
    
    for (const entry of entries) {
      const date = entry.entry_date;
      if (!byDate.has(date)) {
        byDate.set(date, {
          date,
          meals: {},
          total_kcal: 0,
          total_protein: 0,
          total_carbs: 0,
          total_fat: 0,
          entries_count: 0,
        });
      }
      
      const dayData = byDate.get(date);
      if (!dayData.meals[entry.meal_slot]) {
        dayData.meals[entry.meal_slot] = {
          kcal: 0,
          protein: 0,
          carbs: 0,
          fat: 0,
          entries: 0,
        };
      }
      
      dayData.meals[entry.meal_slot].kcal += entry.kcal;
      dayData.meals[entry.meal_slot].protein += entry.protein_g;
      dayData.meals[entry.meal_slot].carbs += entry.carbs_g;
      dayData.meals[entry.meal_slot].fat += entry.fat_g;
      dayData.meals[entry.meal_slot].entries += 1;
      
      dayData.total_kcal += entry.kcal;
      dayData.total_protein += entry.protein_g;
      dayData.total_carbs += entry.carbs_g;
      dayData.total_fat += entry.fat_g;
      dayData.entries_count += 1;
    }

    // Calculate adherence metrics
    const dailyBreakdown = Array.from(byDate.values()).map(day => {
      const dayOfWeek = new Date(day.date).getDay();
      const normalizedDay = dayOfWeek === 0 ? 7 : dayOfWeek;
      
      const dayTargets = targets?.filter(t => t.day_of_week === normalizedDay) || [];
      
      let targetKcal = 0;
      let targetProtein = 0;
      let targetCarbs = 0;
      let targetFat = 0;
      
      for (const t of dayTargets) {
        targetKcal += ((t.protein_g + t.carbs_g) * 4 + t.fat_g * 9);
        targetProtein += t.protein_g;
        targetCarbs += t.carbs_g;
        targetFat += t.fat_g;
      }

      const kcalDiff = targetKcal > 0 ? Math.abs(day.total_kcal - targetKcal) / targetKcal : 0;
      const proteinDiff = targetProtein > 0 ? Math.abs(day.total_protein - targetProtein) / targetProtein : 0;
      const carbsDiff = targetCarbs > 0 ? Math.abs(day.total_carbs - targetCarbs) / targetCarbs : 0;
      const fatDiff = targetFat > 0 ? Math.abs(day.total_fat - targetFat) / targetFat : 0;
      
      const avgDiff = (kcalDiff + proteinDiff + carbsDiff + fatDiff) / 4;
      const onTarget = avgDiff <= 0.15; // Within 15% of targets

      return {
        date: day.date,
        logged: true,
        entries_count: day.entries_count,
        total_kcal: Math.round(day.total_kcal),
        total_protein: Math.round(day.total_protein),
        total_carbs: Math.round(day.total_carbs),
        total_fat: Math.round(day.total_fat),
        target_kcal: Math.round(targetKcal),
        target_protein: Math.round(targetProtein),
        target_carbs: Math.round(targetCarbs),
        target_fat: Math.round(targetFat),
        on_target: onTarget,
        deviation_pct: Math.round(avgDiff * 100),
      };
    });

    const totalDays = dailyBreakdown.length;
    const loggedDays = dailyBreakdown.filter(d => d.logged).length;
    const onTargetDays = dailyBreakdown.filter(d => d.on_target).length;
    const adherenceRate = totalDays > 0 ? Math.round((onTargetDays / totalDays) * 100) : 0;

    return new Response(
      JSON.stringify({
        period: { from: from_date, to: to_date },
        total_days: totalDays,
        logged_days: loggedDays,
        on_target_days: onTargetDays,
        adherence_rate: adherenceRate,
        daily_breakdown: dailyBreakdown,
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (error) {
    console.error('Error analyzing adherence:', error);
    return new Response(
      JSON.stringify({ error: error instanceof Error ? error.message : 'Unknown error' }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
