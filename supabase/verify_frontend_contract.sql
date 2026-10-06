-- =====================================================================
-- NutriMind — verifica (sola lettura) del contratto DB usato dal frontend
-- Un'unica query: il SQL Editor di Supabase mostra solo l'ultimo
-- risultato. Le righe con ok = false sono problemi da risolvere.
-- =====================================================================

with expected_rpc(name, args) as (
  values
    ('search_foods',                '{p_query,p_limit}'),
    ('get_food',                    '{p_id}'),
    ('get_food_by_barcode',         '{p_barcode}'),
    ('get_food_portions',           '{p_food_id}'),
    ('create_food',                 '{p_name,p_kcal,p_protein_g,p_carbs_g,p_fat_g,p_brand,p_barcode}'),
    ('create_food_portion',         '{p_food_id,p_label,p_grams}'),
    ('log_meal',                    '{p_entry_date,p_meal_slot,p_grams,p_food_id}'),
    ('get_diary_entries',           '{p_date}'),
    ('delete_diary_entry',          '{p_entry_id}'),
    ('add_favorite_food',           '{p_food_id,p_default_grams}'),
    ('get_favorite_foods',          '{}'),
    ('create_personal_meal',        '{p_name,p_items,p_default_slot}'),
    ('log_personal_meal',           '{p_meal_id,p_date,p_slot}'),
    ('get_current_macro_plan',      '{}'),
    ('start_macro_plan',            '{p_patient_id,p_name,p_valid_from,p_targets}'),
    ('get_patient_adherence',       '{p_patient_id,p_from,p_to,p_tolerance}'),
    ('get_my_patients',             '{}'),
    ('get_diary_with_comments',     '{p_patient_id,p_from,p_to}'),
    ('create_nutritionist_comment', '{p_patient_id,p_comment_date,p_body,p_meal_slot}'),
    ('get_nutritionist_comments',   '{p_patient_id,p_from,p_to}'),
    ('mark_comment_read',           '{p_comment_id}'),
    ('get_unread_notifications',    '{}'),
    ('mark_notification_read',      '{p_notification_id}'),
    ('create_invitation',           '{}'),
    ('redeem_invitation',           '{p_code,p_scopes,p_policy_version}'),
    ('revoke_link',                 '{p_link_id}'),
    ('grant_consent',               '{p_link_id,p_scope,p_policy_version}'),
    ('revoke_consent',              '{p_link_id,p_scope}')
),
fn as (
  select p.proname, p.oid, coalesce(p.proargnames, '{}') as argnames,
         pg_get_function_identity_arguments(p.oid) as signature
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
),
expected_table(name, privs) as (
  values
    ('foods', 'SELECT'),
    ('profiles', 'SELECT,UPDATE'),
    ('patient_settings', 'SELECT,UPDATE'),
    ('nutritionist_details', 'SELECT,INSERT,UPDATE'),
    ('professional_verifications', 'SELECT,INSERT'),
    ('patient_links', 'SELECT'),
    ('consents', 'SELECT'),
    ('favorite_foods', 'SELECT,DELETE'),
    ('personal_meals', 'SELECT'),
    ('macro_plan_targets', 'SELECT'),
    ('notifications', 'SELECT'),
    ('device_tokens', 'SELECT,INSERT,DELETE')
),
checks(kind, name, detail, ok, problem) as (
  -- RPC: esistenza, parametri passati dal frontend, EXECUTE
  select
    'rpc', e.name,
    coalesce(f.signature, '(mancante)'),
    f.oid is not null
      and e.args::text[] <@ f.argnames
      and has_function_privilege('authenticated', f.oid, 'execute')
      and not has_function_privilege('anon', f.oid, 'execute'),
    case
      when f.oid is null then 'funzione non trovata'
      when not (e.args::text[] <@ f.argnames) then 'parametri diversi: attesi ' || e.args
      when not has_function_privilege('authenticated', f.oid, 'execute') then 'manca EXECUTE per authenticated'
      when has_function_privilege('anon', f.oid, 'execute') then 'anon può eseguirla'
      else ''
    end
  from expected_rpc e
  left join fn f on f.proname = e.name

  union all

  -- Tabelle: RLS attiva e privilegi per authenticated (INSERT/UPDATE anche
  -- solo su alcune colonne: la migration 014 limita le colonne scrivibili)
  select
    'table', t.name, t.privs,
    coalesce(c.relrowsecurity and bool_and((has_table_privilege('authenticated', c.oid, p.priv) or (p.priv in ('INSERT', 'UPDATE') and has_any_column_privilege('authenticated', c.oid, p.priv)))), false),
    case
      when c.oid is null then 'tabella non trovata'
      when not c.relrowsecurity then 'RLS disattivata'
      when not bool_and((has_table_privilege('authenticated', c.oid, p.priv) or (p.priv in ('INSERT', 'UPDATE') and has_any_column_privilege('authenticated', c.oid, p.priv)))) then 'privilegi mancanti per authenticated'
      else ''
    end
  from expected_table t
  cross join lateral unnest(string_to_array(t.privs, ',')) as p(priv)
  left join pg_class c on c.relname = t.name and c.relnamespace = 'public'::regnamespace
  group by t.name, t.privs, c.oid, c.relrowsecurity

  union all

  -- Policy: almeno una per ogni comando usato dal frontend
  select
    'policy', t.name || ' ' || p.priv,
    coalesce((select string_agg(pp.policyname, ', ') from pg_policies pp
              where pp.schemaname = 'public' and pp.tablename = t.name and pp.cmd in (p.priv, 'ALL')), '(nessuna)'),
    exists (select 1 from pg_policies pp
            where pp.schemaname = 'public' and pp.tablename = t.name and pp.cmd in (p.priv, 'ALL')),
    'senza policy RLS blocca ogni riga'
  from expected_table t
  cross join lateral unnest(string_to_array(t.privs, ',')) as p(priv)

  union all

  -- Colonne scritte dal frontend in device_tokens
  select
    'column', 'device_tokens',
    (select string_agg(column_name, ',' order by ordinal_position) from information_schema.columns
     where table_schema = 'public' and table_name = 'device_tokens'),
    (select count(*) = 3 from information_schema.columns
     where table_schema = 'public' and table_name = 'device_tokens' and column_name in ('user_id', 'token', 'platform')),
    'servono user_id, token, platform'

  union all

  -- Enum usato dal frontend
  select
    'enum', 'meal_slot',
    (select string_agg(e.enumlabel, ',' order by e.enumsortorder) from pg_enum e where e.enumtypid = 'public.meal_slot'::regtype),
    (select string_agg(e.enumlabel, ',' order by e.enumsortorder) from pg_enum e where e.enumtypid = 'public.meal_slot'::regtype)
      = 'breakfast,morning_snack,lunch,afternoon_snack,dinner,evening_snack',
    ''

  union all

  select
    'realtime', 'notifications', 'publication supabase_realtime',
    exists (select 1 from pg_publication_tables
            where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'notifications'),
    'opzionale: badge notifiche in tempo reale'
)
select kind, name, detail, ok, case when ok then '' else problem end as problem
from checks
order by ok, kind, name;
