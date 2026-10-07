-- =====================================================================
-- NutriMind — verifica (sola lettura) del contratto DB usato dal frontend
--
-- Un'unica query: restituisce il totale dei controlli, quanti passano e
-- l'elenco dei soli problemi. Se `problemi` è [] il database è allineato
-- all'app (migration 014-025).
-- =====================================================================

with expected_rpc(name, args) as (values
  -- catalogo
  ('search_foods','{p_query,p_limit,p_min_protein,p_max_protein,p_min_carbs,p_max_carbs,p_min_fat,p_max_fat,p_min_kcal,p_max_kcal,p_sort}'),
  ('get_food','{p_id}'),('get_food_by_barcode','{p_barcode}'),('get_food_portions','{p_food_id}'),
  ('create_food','{p_name,p_kcal,p_protein_g,p_carbs_g,p_fat_g,p_brand,p_barcode}'),
  ('create_food_portion','{p_food_id,p_label,p_grams}'),
  -- diario, preferiti, pasti personali
  ('log_meal','{p_entry_date,p_meal_slot,p_grams,p_food_id}'),('get_diary_entries','{p_date}'),
  ('delete_diary_entry','{p_entry_id}'),('add_favorite_food','{p_food_id,p_default_grams}'),
  ('get_favorite_foods','{}'),('create_personal_meal','{p_name,p_items,p_default_slot}'),
  ('log_personal_meal','{p_meal_id,p_date,p_slot}'),
  -- piani e aderenza
  ('get_current_macro_plan','{}'),
  ('get_patient_adherence','{p_patient_id,p_from,p_to,p_tolerance}'),('get_my_patients','{}'),
  ('get_diary_with_comments','{p_patient_id,p_from,p_to}'),
  -- commenti e notifiche
  ('create_nutritionist_comment','{p_patient_id,p_comment_date,p_body,p_meal_slot}'),
  ('get_nutritionist_comments','{p_patient_id,p_from,p_to}'),('mark_comment_read','{p_comment_id}'),
  ('get_unread_notifications','{}'),('mark_notification_read','{p_notification_id}'),
  -- inviti, collegamenti, consensi
  ('create_invitation','{}'),('redeem_invitation','{p_code,p_scopes,p_policy_version}'),
  ('revoke_link','{p_link_id}'),('grant_consent','{p_link_id,p_scope,p_policy_version}'),
  ('revoke_consent','{p_link_id,p_scope}'),
  -- ricette (016)
  ('submit_meal_for_review','{p_meal_id}'),('withdraw_meal','{p_meal_id}'),
  ('review_meal','{p_meal_id,p_approve,p_notes}'),('publish_own_meal','{p_meal_id,p_visibility}'),
  ('unpublish_own_meal','{p_meal_id}'),('log_suggested_meal','{p_meal_id,p_date,p_slot,p_servings}'),
  ('save_meal_draft','{p_meal_id,p_data,p_items}'),('get_recipe_author','{p_meal_id}'),
  ('get_recipes_for_me','{p_slot,p_restrictions,p_query}'),('get_meals_to_review','{}'),
  -- vetrina (017)
  ('search_nutritionists','{p_query,p_specialty,p_restriction,p_online}'),
  -- chat (018)
  ('start_conversation','{p_other}'),('send_message','{p_conversation,p_body,p_kind,p_payload}'),
  ('send_invitation_message','{p_conversation}'),('mark_conversation_read','{p_conversation}'),
  ('get_my_conversations','{}'),
  -- piani, autogestione, consigli mirati (023)
  ('start_macro_plan','{p_patient_id,p_name,p_valid_from,p_targets,p_notes}'),
  ('can_self_manage_plan','{}'),
  ('suggest_to_patient','{p_patient_id,p_meal_id,p_food_id,p_note}'),
  ('remove_patient_suggestion','{p_id}'),
  ('get_patient_suggestions','{p_patient_id}'),
  -- amministrazione (024, 025)
  ('get_pending_verifications','{}'),
  ('review_professional_verification','{p_id,p_approve}'),
  ('get_foods_to_review','{p_limit}'),
  ('get_admin_overview','{}'),
  ('review_food','{p_food_id,p_decision}'),
  -- privacy
  ('export_my_data','{}'),('delete_my_account','{}')
),
expected_table(name, privs) as (values
  ('foods','SELECT,INSERT'),('profiles','SELECT,UPDATE'),('patient_settings','SELECT,UPDATE'),
  ('nutritionist_details','SELECT,INSERT,UPDATE'),('professional_verifications','SELECT,INSERT'),
  ('patient_links','SELECT'),('consents','SELECT'),('favorite_foods','SELECT,DELETE'),
  ('personal_meals','SELECT,DELETE'),('macro_plan_targets','SELECT'),('notifications','SELECT'),
  ('device_tokens','SELECT,INSERT,DELETE'),('suggested_meals','SELECT,INSERT,UPDATE,DELETE'),
  ('suggested_meal_items','SELECT,INSERT,UPDATE,DELETE'),
  ('nutritionist_plan_templates','SELECT,INSERT,UPDATE,DELETE'),
  ('conversations','SELECT'),('messages','SELECT'),
  ('patient_suggestions','SELECT')
),
fn as (
  select p.proname, p.oid, coalesce(p.proargnames, '{}') as argnames,
         pg_get_function_identity_arguments(p.oid) as sig
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
),
checks(kind, name, detail, ok, problem) as (
  -- RPC: esistenza, parametri usati dal frontend, EXECUTE solo ad authenticated
  select 'rpc', e.name, coalesce(f.sig, '(mancante)'),
    f.oid is not null and e.args::text[] <@ f.argnames
      and has_function_privilege('authenticated', f.oid, 'execute')
      and not has_function_privilege('anon', f.oid, 'execute'),
    case when f.oid is null then 'funzione non trovata'
         when not (e.args::text[] <@ f.argnames) then 'parametri attesi: ' || e.args
         when not has_function_privilege('authenticated', f.oid, 'execute') then 'manca EXECUTE per authenticated'
         else 'anon puo eseguirla' end
  from expected_rpc e left join fn f on f.proname = e.name

  union all

  -- Tabelle: RLS attiva e privilegi (INSERT/UPDATE anche solo su alcune colonne)
  select 'table', t.name, t.privs,
    coalesce(c.relrowsecurity and bool_and(
      has_table_privilege('authenticated', c.oid, p.priv)
      or (p.priv in ('INSERT','UPDATE') and has_any_column_privilege('authenticated', c.oid, p.priv))), false),
    case when c.oid is null then 'tabella non trovata'
         when not c.relrowsecurity then 'RLS disattivata'
         else 'privilegi mancanti per authenticated' end
  from expected_table t
  cross join lateral unnest(string_to_array(t.privs, ',')) as p(priv)
  left join pg_class c on c.relname = t.name and c.relnamespace = 'public'::regnamespace
  group by t.name, t.privs, c.oid, c.relrowsecurity

  union all

  -- Policy: almeno una per ogni comando usato dal frontend
  select 'policy', t.name || ' ' || p.priv,
    coalesce((select string_agg(pp.policyname, ', ') from pg_policies pp
              where pp.schemaname = 'public' and pp.tablename = t.name and pp.cmd in (p.priv, 'ALL')), '(nessuna)'),
    exists (select 1 from pg_policies pp
            where pp.schemaname = 'public' and pp.tablename = t.name and pp.cmd in (p.priv, 'ALL')),
    'senza policy RLS blocca ogni riga'
  from expected_table t
  cross join lateral unnest(string_to_array(t.privs, ',')) as p(priv)

  union all

  -- Funzioni usate dentro le policy: valutate come il chiamante, quindi
  -- senza EXECUTE la lettura della tabella protetta va in errore
  select 'policy-exec', p.proname, 'EXECUTE per authenticated',
    has_function_privilege('authenticated', p.oid, 'execute'),
    'senza EXECUTE la lettura della tabella protetta va in errore'
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in ('can_review_meals_of', 'is_public_nutritionist', 'is_conversation_member',
                      'is_my_nutritionist', 'has_active_link', 'is_admin')

  union all

  select 'realtime', x.t, 'publication supabase_realtime',
    exists (select 1 from pg_publication_tables
            where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = x.t),
    'serve per notifiche e chat in tempo reale'
  from (values ('notifications'), ('messages')) x(t)

  union all

  select 'column', 'device_tokens',
    (select string_agg(column_name, ',' order by ordinal_position) from information_schema.columns
      where table_schema = 'public' and table_name = 'device_tokens'),
    (select count(*) = 3 from information_schema.columns
      where table_schema = 'public' and table_name = 'device_tokens'
        and column_name in ('user_id', 'token', 'platform')),
    'servono user_id, token, platform'

  union all

  -- Colonne generate dal database: scriverle da una funzione fa
  -- fallire ogni INSERT con 428C9. Ci siamo sbagliati due volte, su
  -- suggested_meals e su macro_plan_targets: meglio tenerle elencate.
  select 'generated', 'suggested_meals',
    (select string_agg(column_name, ',' order by ordinal_position) from information_schema.columns
      where table_schema = 'public' and table_name = 'suggested_meals' and is_generated = 'ALWAYS'),
    (select count(*) = 4 from information_schema.columns
      where table_schema = 'public' and table_name = 'suggested_meals' and is_generated = 'ALWAYS'),
    'attese 4 colonne per porzione generate'
  union all

  select 'generated', 'macro_plan_targets',
    (select coalesce(string_agg(column_name, ',' order by ordinal_position), '(nessuna)')
       from information_schema.columns
      where table_schema = 'public' and table_name = 'macro_plan_targets' and is_generated = 'ALWAYS'),
    (select count(*) = 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'macro_plan_targets'
        and is_generated = 'ALWAYS' and column_name = 'kcal_estimated'),
    'kcal_estimated e generata: start_macro_plan non deve scriverla'

  union all

  select 'enum', 'meal_slot',
    (select string_agg(enumlabel, ',' order by enumsortorder) from pg_enum where enumtypid = 'public.meal_slot'::regtype),
    (select string_agg(enumlabel, ',' order by enumsortorder) from pg_enum where enumtypid = 'public.meal_slot'::regtype)
      = 'breakfast,morning_snack,lunch,afternoon_snack,dinner,evening_snack',
    'valori diversi da quelli usati dall''app'

  union all

  -- Obiettivi ammessi per le ricette: l'app deve proporre esattamente questi
  select 'tags', 'suggested_meals_goal_tags', pg_get_constraintdef(oid),
    pg_get_constraintdef(oid) like '%high_protein%',
    'l''app propone obiettivi non ammessi dal vincolo'
  from pg_constraint where conname = 'suggested_meals_goal_tags_check'

  union all

  -- 021: il ruolo scelto alla registrazione deve finire nel profilo
  select 'signup', 'handle_new_user', 'legge raw_user_meta_data',
    exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public' and p.proname = 'handle_new_user'
               and pg_get_functiondef(p.oid) like '%raw_user_meta_data%'
               and pg_get_functiondef(p.oid) like '%nutritionist%'),
    'chi si registra come nutrizionista diventa paziente: eseguire la 021'

  union all

  select 'signup', 'on_auth_user_created', 'trigger su auth.users',
    exists (select 1 from pg_trigger
             where tgname = 'on_auth_user_created'
               and tgrelid = 'auth.users'::regclass and not tgisinternal),
    'senza il trigger la registrazione non crea il profilo'

  union all

  select 'signup', 'utenze senza profilo',
    (select count(*)::text from auth.users u
      where not exists (select 1 from public.profiles p where p.id = u.id)),
    not exists (select 1 from auth.users u
                 where not exists (select 1 from public.profiles p where p.id = u.id)),
    'ogni scrittura di quell''utente va in errore di chiave esterna'

  union all

  -- 022: la ricerca testuale deve tollerare gli errori di battitura
  select 'search', 'search_foods', 'usa la somiglianza di pg_trgm',
    exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public' and p.proname = 'search_foods'
               and pg_get_functiondef(p.oid) like '%word_similarity%'),
    'solo ilike: "mozarella" non trova "mozzarella"'

  union all

  select 'search', 'foods_name_trgm_idx', 'indice GIN su name_search',
    exists (select 1 from pg_class i join pg_index ix on ix.indexrelid = i.oid
             where ix.indrelid = 'public.foods'::regclass and i.relname = 'foods_name_trgm_idx'),
    'senza indice la ricerca per somiglianza scansiona tutto il catalogo'
  union all

  -- 025: l'esportazione dei dati deve comprendere le tabelle nuove,
  -- altrimenti chi chiede i propri dati ne riceve solo una parte
  select 'privacy', 'export_my_data', 'comprende i consigli mirati',
    exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public' and p.proname = 'export_my_data'
               and pg_get_functiondef(p.oid) like '%patient_suggestions%'),
    'esportazione incompleta: manca patient_suggestions'
)
select (select count(*) from checks) as totale,
       (select count(*) from checks where ok) as ok,
       (select coalesce(json_agg(json_build_object(
                 'kind', kind, 'name', name, 'detail', detail, 'problem', problem) order by kind, name), '[]'::json)
          from checks where not ok) as problemi;
