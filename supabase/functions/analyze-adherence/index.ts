import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// Aderenza al piano macro in un periodo, giorno per giorno.
//
// Chi può chiamarla: il paziente stesso, oppure un nutrizionista con
// collegamento attivo e consenso `adherence` (o `diary`) non revocato.
// I dati vengono letti con il service role solo dopo questo controllo.
//
// Per ogni giorno si usa il piano valido in quella data; i target con
// day_of_week nullo valgono per tutti i giorni. I giorni senza piano non
// entrano nel calcolo dell'aderenza.

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

const MAX_DAYS = 92;
const isoDate = /^\d{4}-\d{2}-\d{2}$/;

function daysBetween(from: string, to: string): string[] {
  const out: string[] = [];
  const d = new Date(`${from}T00:00:00Z`);
  const end = new Date(`${to}T00:00:00Z`);
  while (d <= end && out.length <= MAX_DAYS) {
    out.push(d.toISOString().slice(0, 10));
    d.setUTCDate(d.getUTCDate() + 1);
  }
  return out;
}

const num = (v: unknown) => (typeof v === 'number' ? v : Number(v ?? 0)) || 0;

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const admin = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '');

    const bearer = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
    const { data: { user }, error: userError } = await admin.auth.getUser(bearer);
    if (userError || !user) return json({ error: 'Unauthorized', code: 'unauthorized' }, 401);

    const body = await req.json().catch(() => null);
    const { patient_id, from_date, to_date } = body ?? {};
    const tolerance = typeof body?.tolerance === 'number' ? body.tolerance : 0.15;
    if (!patient_id || !isoDate.test(from_date ?? '') || !isoDate.test(to_date ?? '') || from_date > to_date) {
      return json({ error: 'patient_id, from_date and to_date (YYYY-MM-DD) are required', code: 'invalid_request' }, 400);
    }
    const days = daysBetween(from_date, to_date);
    if (days.length > MAX_DAYS) return json({ error: `Period longer than ${MAX_DAYS} days`, code: 'invalid_request' }, 400);

    // Autorizzazione
    if (user.id !== patient_id) {
      const { data: link } = await admin
        .from('patient_links')
        .select('id')
        .eq('patient_id', patient_id)
        .eq('nutritionist_id', user.id)
        .eq('status', 'active')
        .maybeSingle();
      if (!link) return json({ error: 'Forbidden', code: 'forbidden' }, 403);

      const { data: consent } = await admin
        .from('consents')
        .select('id')
        .eq('link_id', link.id)
        .in('scope', ['adherence', 'diary'])
        .is('revoked_at', null)
        .limit(1)
        .maybeSingle();
      if (!consent) return json({ error: 'Forbidden', code: 'consent_required' }, 403);
    }

    const [{ data: entries, error: entriesError }, { data: plans, error: plansError }] = await Promise.all([
      admin
        .from('diary_entries')
        .select('entry_date, kcal, protein_g, carbs_g, fat_g')
        .eq('patient_id', patient_id)
        .gte('entry_date', from_date)
        .lte('entry_date', to_date),
      admin
        .from('macro_plans')
        .select('id, valid_from, valid_to, macro_plan_targets(day_of_week, protein_g, carbs_g, fat_g, kcal_estimated)')
        .eq('patient_id', patient_id)
        .lte('valid_from', to_date)
        .or(`valid_to.is.null,valid_to.gte.${from_date}`)
        .order('valid_from', { ascending: false }),
    ]);
    if (entriesError || plansError) throw entriesError ?? plansError;

    const totals = new Map<string, { kcal: number; protein: number; carbs: number; fat: number; count: number }>();
    for (const e of entries ?? []) {
      const t = totals.get(e.entry_date) ?? { kcal: 0, protein: 0, carbs: 0, fat: 0, count: 0 };
      t.kcal += num(e.kcal);
      t.protein += num(e.protein_g);
      t.carbs += num(e.carbs_g);
      t.fat += num(e.fat_g);
      t.count += 1;
      totals.set(e.entry_date, t);
    }

    const dailyBreakdown = days.map((date) => {
      const plan = (plans ?? []).find((p) => p.valid_from <= date && (!p.valid_to || p.valid_to >= date));
      const weekday = new Date(`${date}T00:00:00Z`).getUTCDay() || 7; // 1 = lunedì ... 7 = domenica
      const all = (plan?.macro_plan_targets ?? []) as any[];
      let dayTargets = all.filter((t) => t.day_of_week === weekday);
      if (dayTargets.length === 0) dayTargets = all.filter((t) => t.day_of_week === null);

      const target = { kcal: 0, protein: 0, carbs: 0, fat: 0 };
      for (const t of dayTargets) {
        target.protein += num(t.protein_g);
        target.carbs += num(t.carbs_g);
        target.fat += num(t.fat_g);
        target.kcal += t.kcal_estimated != null ? num(t.kcal_estimated) : num(t.protein_g) * 4 + num(t.carbs_g) * 4 + num(t.fat_g) * 9;
      }
      const hasPlan = target.kcal > 0;
      const actual = totals.get(date) ?? { kcal: 0, protein: 0, carbs: 0, fat: 0, count: 0 };
      const logged = actual.count > 0;

      const diffs = (['kcal', 'protein', 'carbs', 'fat'] as const)
        .filter((k) => target[k] > 0)
        .map((k) => Math.abs(actual[k] - target[k]) / target[k]);
      const avgDiff = diffs.length ? diffs.reduce((a, b) => a + b, 0) / diffs.length : 0;

      return {
        date,
        logged,
        has_plan: hasPlan,
        entries_count: actual.count,
        total_kcal: Math.round(actual.kcal),
        total_protein: Math.round(actual.protein),
        total_carbs: Math.round(actual.carbs),
        total_fat: Math.round(actual.fat),
        target_kcal: Math.round(target.kcal),
        target_protein: Math.round(target.protein),
        target_carbs: Math.round(target.carbs),
        target_fat: Math.round(target.fat),
        // Un giorno senza registrazioni non è in target
        on_target: hasPlan ? logged && avgDiff <= tolerance : null,
        deviation_pct: hasPlan && logged ? Math.round(avgDiff * 100) : null,
      };
    });

    const planDays = dailyBreakdown.filter((d) => d.has_plan);
    const onTargetDays = planDays.filter((d) => d.on_target).length;

    return json({
      period: { from: from_date, to: to_date },
      total_days: dailyBreakdown.length,
      logged_days: dailyBreakdown.filter((d) => d.logged).length,
      plan_days: planDays.length,
      on_target_days: onTargetDays,
      adherence_rate: planDays.length ? Math.round((onTargetDays / planDays.length) * 100) : 0,
      tolerance,
      daily_breakdown: dailyBreakdown,
    });
  } catch (error) {
    console.error('Error analyzing adherence:', error instanceof Error ? error.message : error);
    return json({ error: 'Internal error', code: 'internal_error' }, 500);
  }
});
