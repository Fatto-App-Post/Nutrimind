-- =====================================================================
-- NutriMind — 014 PERMESSI E CORREZIONI PER IL FRONTEND
-- 1. Il ruolo `authenticated` non aveva EXECUTE sulle RPC usate dall'app
--    (errore 42501 "permission denied for function ...").
-- 2. Prima di concedere EXECUTE, le RPC security definer che accettano
--    p_patient_id verificano che il chiamante sia il paziente o un
--    nutrizionista autorizzato: altrimenti chiunque potrebbe leggere i
--    dati di un altro paziente.
-- 3. create_nutritionist_comment usava un notification_type inesistente.
-- 4. log_personal_meal non calcolava kcal e macro delle voci inserite.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 2. Controlli di autorizzazione sulle letture per paziente
-- ---------------------------------------------------------------------
create or replace function public.get_diary_entries(
  p_date date,
  p_patient_id uuid default null
)
returns setof public.diary_entries
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_patient uuid := coalesce(p_patient_id, auth.uid());
begin
  if v_patient <> auth.uid() and not public.can_nutritionist_see(v_patient, 'diary') then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  return query
  select de.*
  from public.diary_entries de
  where de.entry_date = p_date
    and de.patient_id = v_patient
  order by de.meal_slot, de.created_at;
end;
$$;

create or replace function public.get_current_macro_plan(p_patient_id uuid default null)
returns setof public.macro_plans
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_patient uuid := coalesce(p_patient_id, auth.uid());
begin
  if v_patient <> auth.uid() and not public.has_active_link(v_patient) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  return query
  select mp.*
  from public.macro_plans mp
  where mp.patient_id = v_patient
    and (mp.valid_to is null or mp.valid_to >= current_date)
  order by mp.valid_from desc
  limit 1;
end;
$$;

create or replace function public.get_nutritionist_comments(
  p_patient_id uuid,
  p_from date default null,
  p_to date default null
)
returns setof public.nutritionist_comments
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if p_patient_id <> auth.uid() and not public.has_active_link(p_patient_id) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  return query
  select nc.*
  from public.nutritionist_comments nc
  where nc.patient_id = p_patient_id
    and (p_from is null or nc.comment_date >= p_from)
    and (p_to is null or nc.comment_date <= p_to)
  order by nc.comment_date desc, nc.created_at desc;
end;
$$;

-- Wrapper con controllo: il corpo originale (012) diventa una funzione
-- interna non esposta. Rinomina solo alla prima esecuzione, così la
-- migration si può rieseguire.
do $$
begin
  if to_regprocedure('public.get_diary_with_comments_unchecked(uuid, date, date)') is null then
    alter function public.get_diary_with_comments(uuid, date, date)
      rename to get_diary_with_comments_unchecked;
  end if;
end;
$$;
revoke execute on function public.get_diary_with_comments_unchecked(uuid, date, date) from public, anon, authenticated;

create or replace function public.get_diary_with_comments(
  p_patient_id uuid,
  p_from date,
  p_to date
)
returns table (
  entry_date date,
  meal_slot public.meal_slot,
  entries jsonb,
  comments jsonb
)
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if p_patient_id <> auth.uid() and not public.can_nutritionist_see(p_patient_id, 'diary') then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  return query
  select * from public.get_diary_with_comments_unchecked(p_patient_id, p_from, p_to);
end;
$$;

-- ---------------------------------------------------------------------
-- 3. Tipo notifica valido ('new_comment' è nell'enum notification_type)
-- ---------------------------------------------------------------------
create or replace function public.create_nutritionist_comment(
  p_patient_id uuid,
  p_comment_date date,
  p_body text,
  p_meal_slot public.meal_slot default null,
  p_diary_entry_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_comment_id uuid;
  v_user_id uuid := auth.uid();
  v_role public.user_role;
begin
  select role into v_role from public.profiles where id = v_user_id;

  if v_role is null or v_role not in ('nutritionist', 'admin') then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  if v_role = 'nutritionist' and not public.has_active_link(p_patient_id) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  insert into public.nutritionist_comments (
    patient_id, nutritionist_id, comment_date, meal_slot, diary_entry_id, body
  ) values (
    p_patient_id, v_user_id, p_comment_date, p_meal_slot, p_diary_entry_id, p_body
  )
  returning id into v_comment_id;

  insert into public.notifications (user_id, type, title, body, data)
  values (
    p_patient_id, 'new_comment',
    'Nuovo commento dal nutrizionista',
    'Hai ricevuto un nuovo commento per il giorno ' || to_char(p_comment_date, 'DD/MM/YYYY'),
    jsonb_build_object('comment_id', v_comment_id, 'comment_date', p_comment_date, 'meal_slot', p_meal_slot)
  );

  return v_comment_id;
end;
$$;

-- ---------------------------------------------------------------------
-- 4. log_personal_meal calcola i macro come log_meal
-- ---------------------------------------------------------------------
create or replace function public.log_personal_meal(
  p_meal_id uuid,
  p_date date,
  p_slot public.meal_slot
)
returns integer
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_count int;
begin
  insert into public.diary_entries (
    patient_id, entry_date, meal_slot, food_id, grams,
    kcal, protein_g, carbs_g, fat_g, food_trust_level, entry_source
  )
  select
    pm.patient_id, p_date, p_slot, pmi.food_id, pmi.grams,
    round(f.kcal * pmi.grams / 100, 2),
    round(f.protein_g * pmi.grams / 100, 2),
    round(f.carbs_g * pmi.grams / 100, 2),
    round(f.fat_g * pmi.grams / 100, 2),
    f.trust_level,
    'personal_meal'
  from public.personal_meals pm
  join public.personal_meal_items pmi on pmi.meal_id = pm.id
  join public.foods f on f.id = pmi.food_id
  where pm.id = p_meal_id and pm.patient_id = auth.uid()
  order by pmi.position;

  get diagnostics v_count = row_count;

  update public.personal_meals
  set use_count = use_count + 1
  where id = p_meal_id and v_count > 0;

  return v_count;
end;
$$;

-- ---------------------------------------------------------------------
-- 1. EXECUTE solo agli utenti autenticati (mai ad anon), su tutte le
--    firme esistenti di ciascuna RPC usata dal frontend
-- ---------------------------------------------------------------------
do $$
declare
  v_fn regprocedure;
begin
  for v_fn in
    select p.oid::regprocedure
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        -- catalogo
        'search_foods', 'get_food', 'get_food_by_barcode', 'get_food_portions',
        'create_food', 'create_food_portion',
        -- diario, preferiti, pasti personali
        'log_meal', 'get_diary_entries', 'delete_diary_entry',
        'add_favorite_food', 'get_favorite_foods',
        'create_personal_meal', 'log_personal_meal',
        -- piani e aderenza
        'get_current_macro_plan', 'start_macro_plan',
        'get_patient_adherence', 'get_my_patients', 'get_diary_with_comments',
        -- commenti e notifiche
        'create_nutritionist_comment', 'get_nutritionist_comments', 'mark_comment_read',
        'get_unread_notifications', 'mark_notification_read',
        -- inviti, collegamenti, consensi
        'create_invitation', 'redeem_invitation', 'revoke_link',
        'grant_consent', 'revoke_consent'
      )
  loop
    execute format('revoke execute on function %s from public, anon', v_fn);
    execute format('grant execute on function %s to authenticated', v_fn);
  end loop;
end;
$$;

-- ---------------------------------------------------------------------
-- Tabelle lette/scritte direttamente dall'app: privilegi minimi + RLS
-- ---------------------------------------------------------------------
alter table public.foods enable row level security;
alter table public.profiles enable row level security;
alter table public.patient_settings enable row level security;
alter table public.nutritionist_details enable row level security;
alter table public.professional_verifications enable row level security;
alter table public.patient_links enable row level security;
alter table public.consents enable row level security;
alter table public.favorite_foods enable row level security;
alter table public.personal_meals enable row level security;
alter table public.macro_plan_targets enable row level security;
alter table public.notifications enable row level security;
alter table public.device_tokens enable row level security;

grant select on public.foods to authenticated;
grant select, update (display_name, locale) on public.profiles to authenticated;
grant select, update (dietary_restrictions, timezone, reminders_enabled, reminder_after_hours) on public.patient_settings to authenticated;
-- L'upsert di PostgREST riscrive anche user_id: la policy impone user_id = auth.uid()
grant select, insert, update (user_id, studio_name, bio) on public.nutritionist_details to authenticated;
grant select, insert (user_id, license_body, license_number) on public.professional_verifications to authenticated;
grant select on public.patient_links to authenticated;
grant select on public.consents to authenticated;
grant select, delete on public.favorite_foods to authenticated;
grant select on public.personal_meals to authenticated;
grant select on public.macro_plan_targets to authenticated;
grant select on public.notifications to authenticated;
-- Token push FCM: l'app registra e rimuove solo quelli del proprio utente
grant select, insert, delete on public.device_tokens to authenticated;

-- Policy create solo se per quel comando non ne esiste già una
do $$
declare
  v_policies text[][] := array[
    -- tabella, comando, nome, definizione
    array['profiles', 'SELECT', 'profiles_select_own',
          'for select to authenticated using (id = auth.uid())'],
    array['profiles', 'UPDATE', 'profiles_update_own',
          'for update to authenticated using (id = auth.uid()) with check (id = auth.uid())'],
    array['patient_settings', 'SELECT', 'patient_settings_select_own',
          'for select to authenticated using (user_id = auth.uid())'],
    array['patient_settings', 'UPDATE', 'patient_settings_update_own',
          'for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid())'],
    array['nutritionist_details', 'SELECT', 'nutritionist_details_select_own',
          'for select to authenticated using (user_id = auth.uid())'],
    array['nutritionist_details', 'INSERT', 'nutritionist_details_insert_own',
          'for insert to authenticated with check (user_id = auth.uid())'],
    array['nutritionist_details', 'UPDATE', 'nutritionist_details_update_own',
          'for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid())'],
    array['professional_verifications', 'SELECT', 'professional_verifications_select_own',
          'for select to authenticated using (user_id = auth.uid())'],
    array['professional_verifications', 'INSERT', 'professional_verifications_insert_own',
          'for insert to authenticated with check (user_id = auth.uid() and status = ''pending'')'],
    array['patient_links', 'SELECT', 'patient_links_select_party',
          'for select to authenticated using (auth.uid() in (patient_id, nutritionist_id))'],
    array['consents', 'SELECT', 'consents_select_party',
          'for select to authenticated using (auth.uid() in (patient_id, nutritionist_id))'],
    array['favorite_foods', 'SELECT', 'favorite_foods_select_own',
          'for select to authenticated using (patient_id = auth.uid())'],
    array['favorite_foods', 'DELETE', 'favorite_foods_delete_own',
          'for delete to authenticated using (patient_id = auth.uid())'],
    array['personal_meals', 'SELECT', 'personal_meals_select_own',
          'for select to authenticated using (patient_id = auth.uid())'],
    array['macro_plan_targets', 'SELECT', 'macro_plan_targets_select',
          'for select to authenticated using (exists (select 1 from public.macro_plans mp where mp.id = plan_id and (mp.patient_id = auth.uid() or public.has_active_link(mp.patient_id))))'],
    array['notifications', 'SELECT', 'notifications_select_own',
          'for select to authenticated using (user_id = auth.uid())'],
    array['device_tokens', 'SELECT', 'device_tokens_select_own',
          'for select to authenticated using (user_id = auth.uid())'],
    array['device_tokens', 'INSERT', 'device_tokens_insert_own',
          'for insert to authenticated with check (user_id = auth.uid())'],
    array['device_tokens', 'DELETE', 'device_tokens_delete_own',
          'for delete to authenticated using (user_id = auth.uid())']
  ];
  v_p text[];
begin
  foreach v_p slice 1 in array v_policies
  loop
    if not exists (
      select 1 from pg_policies
      where schemaname = 'public' and tablename = v_p[1] and cmd in (v_p[2], 'ALL')
    ) then
      execute format('create policy %I on public.%I %s', v_p[3], v_p[1], v_p[4]);
    end if;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------
-- Realtime: nuove notifiche in-app
-- ---------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'notifications'
     ) then
    alter publication supabase_realtime add table public.notifications;
  end if;
end;
$$;
