-- =====================================================================
-- NutriMind — 025 CODA DEGLI ALIMENTI DA VERIFICARE E QUADRO ADMIN
-- Rieseguibile.
--
-- `review_food` esiste dalle prime migration e **nessuno la chiama**:
-- l'app non ha mai avuto una schermata per verificare gli alimenti. Il
-- risultato è che tutto ciò che creano i pazienti e i professionisti
-- resta `unverified` per sempre, con `trust_level` 1, e il catalogo non
-- migliora mai di qualità. Mancava solo il modo di elencare quelli in
-- attesa: è questa funzione.
--
-- `get_admin_overview` dà all'amministratore i numeri su cui decidere
-- cosa guardare: quante richieste di abilitazione, quanti alimenti e
-- quante ricette aspettano una revisione. Senza, l'unico modo di saperlo
-- era aprire le tre schermate una per una.
--
-- In coda, una correzione a `export_my_data`: non comprendeva i consigli
-- mirati introdotti dalla 023. Un'esportazione incompleta è un problema
-- di sostanza, non di forma, perché è la risposta a chi chiede i propri
-- dati.
-- =====================================================================

create or replace function public.get_foods_to_review(p_limit integer default 50)
returns table (
  id            uuid,
  name          text,
  brand         text,
  source        text,
  kcal          numeric,
  protein_g     numeric,
  carbs_g       numeric,
  fat_g         numeric,
  serving_label text,
  barcode       text,
  author_name   text,
  is_mine       boolean,
  created_at    timestamptz
)
language plpgsql
stable
security definer
set search_path = 'public'
as $$
declare
  v_me uuid := (select auth.uid());
begin
  if v_me is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  -- Stessa regola di review_food: chi non può decidere non vede la coda.
  if not (public.is_verified_nutritionist() or public.is_admin()) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  return query
  select f.id, f.name, f.brand, f.source::text,
         f.kcal, f.protein_g, f.carbs_g, f.fat_g,
         f.serving_label, f.barcode,
         coalesce(p.display_name, 'Utente'),
         f.created_by = v_me,
         f.created_at
    from public.foods f
    left join public.profiles p on p.id = f.created_by
   where f.is_active
     and f.verification = 'unverified'
     -- Gli import dal catalogo esterno sono migliaia e non si
     -- verificano a mano: la coda è per quello che scrivono le persone.
     and f.source in ('user', 'professional')
     -- Un non amministratore non può rivedere i propri alimenti, quindi
     -- è inutile mostrarglieli; all'amministratore invece sì, perché
     -- review_food glielo consente.
     and (public.is_admin() or f.created_by is distinct from v_me)
   order by f.created_at
   limit least(greatest(coalesce(p_limit, 50), 1), 200);
end;
$$;

create or replace function public.get_admin_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = 'public'
as $$
declare
  v_out jsonb;
begin
  if not public.is_admin() then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'pending_verifications',
      (select count(*) from public.professional_verifications where status = 'pending'),
    'foods_to_review',
      (select count(*) from public.foods
        where is_active and verification = 'unverified' and source in ('user', 'professional')),
    'meals_to_review',
      (select count(*) from public.suggested_meals where status = 'pending_review'),
    'patients',
      (select count(*) from public.profiles where role = 'patient'),
    'professionals',
      (select count(*) from public.profiles where role = 'nutritionist'),
    'verified_professionals',
      (select count(*) from public.profiles where role = 'nutritionist' and professional_verified),
    'public_professionals',
      (select count(*) from public.nutritionist_details where is_public),
    'active_links',
      (select count(*) from public.patient_links where status = 'active'),
    'foods_total',
      (select count(*) from public.foods where is_active),
    'foods_verified',
      (select count(*) from public.foods where is_active and verification = 'verified'),
    'recipes_published',
      (select count(*) from public.suggested_meals where status = 'approved'),
    'diary_entries_last_7',
      (select count(*) from public.diary_entries where entry_date >= current_date - 6)
  ) into v_out;

  return v_out;
end;
$$;

revoke all on function public.get_foods_to_review(integer) from public, anon;
revoke all on function public.get_admin_overview() from public, anon;
grant execute on function public.get_foods_to_review(integer) to authenticated;
grant execute on function public.get_admin_overview() to authenticated;

-- ---------------------------------------------------------------------
-- export_my_data: aggiunge i consigli ricevuti e dati (migration 023)
-- ---------------------------------------------------------------------

create or replace function public.export_my_data()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_out jsonb;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  perform public.log_audit('data_export', 'profile', v_uid::text, v_uid);

  v_out := jsonb_build_object(
    'exported_at', now(),
    'profile', (select to_jsonb(p) from public.profiles p where p.id = v_uid),
    'patient_settings', (select to_jsonb(s) from public.patient_settings s where s.user_id = v_uid),
    'nutritionist_details', (select to_jsonb(n) from public.nutritionist_details n where n.user_id = v_uid),
    'professional_verifications', (select coalesce(jsonb_agg(to_jsonb(v)), '[]') from public.professional_verifications v where v.user_id = v_uid),
    'links', (select coalesce(jsonb_agg(to_jsonb(l)), '[]') from public.patient_links l where l.patient_id = v_uid or l.nutritionist_id = v_uid),
    'consents', (select coalesce(jsonb_agg(to_jsonb(c)), '[]') from public.consents c where c.patient_id = v_uid or c.nutritionist_id = v_uid),
    'plans', (select coalesce(jsonb_agg(to_jsonb(p) || jsonb_build_object('targets',
                (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from public.macro_plan_targets t where t.plan_id = p.id))), '[]')
               from public.macro_plans p where p.patient_id = v_uid or p.nutritionist_id = v_uid),
    'diary_entries', (select coalesce(jsonb_agg(to_jsonb(e) order by e.entry_date), '[]') from public.diary_entries e where e.patient_id = v_uid),
    'favorite_foods', (select coalesce(jsonb_agg(to_jsonb(f)), '[]') from public.favorite_foods f where f.patient_id = v_uid),
    'personal_meals', (select coalesce(jsonb_agg(to_jsonb(m) || jsonb_build_object('items',
                (select coalesce(jsonb_agg(to_jsonb(i)), '[]') from public.personal_meal_items i where i.meal_id = m.id))), '[]')
               from public.personal_meals m where m.patient_id = v_uid),
    'foods_created', (select coalesce(jsonb_agg(to_jsonb(f)), '[]') from public.foods f where f.created_by = v_uid),
    'meals_proposed', (select coalesce(jsonb_agg(to_jsonb(m) || jsonb_build_object('items',
                (select coalesce(jsonb_agg(to_jsonb(i)), '[]') from public.suggested_meal_items i where i.meal_id = m.id))), '[]')
               from public.suggested_meals m where m.proposed_by = v_uid),
    'comments', (select coalesce(jsonb_agg(to_jsonb(c)), '[]') from public.nutritionist_comments c where c.patient_id = v_uid or c.nutritionist_id = v_uid),
    'notifications', (select coalesce(jsonb_agg(to_jsonb(n)), '[]') from public.notifications n where n.user_id = v_uid),
    'terms_acceptances', (select coalesce(jsonb_agg(to_jsonb(a)), '[]') from public.terms_acceptances a where a.user_id = v_uid),
    'audit_log', (select coalesce(jsonb_agg(to_jsonb(a) order by a.at), '[]') from public.audit_log a where a.patient_id = v_uid or a.actor_id = v_uid)
  );

  -- Consigli mirati: quelli ricevuti e, se si e' un professionista,
  -- quelli dati. La tabella e' nata con la 023 e qui mancava.
  v_out := v_out || jsonb_build_object(
    'suggestions_received',
      (select coalesce(jsonb_agg(to_jsonb(s)), '[]') from public.patient_suggestions s where s.patient_id = v_uid),
    'suggestions_given',
      (select coalesce(jsonb_agg(to_jsonb(s)), '[]') from public.patient_suggestions s where s.nutritionist_id = v_uid)
  );

  return v_out;
end;
$$;

revoke all on function public.export_my_data() from public, anon;
grant execute on function public.export_my_data() to authenticated;
