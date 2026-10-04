-- =====================================================================
-- NutriMind — 011 FUNZIONI PER IL FRONTEND
-- Tutte le funzioni RPC che il frontend può chiamare direttamente
-- ADATTATE ALLA STRUTTURA REALE DEL DATABASE
-- =====================================================================

-- ---------------------------------------------------------------------
-- RICERCA ALIMENTI con fallback OpenFoodFacts
-- ---------------------------------------------------------------------
create or replace function public.search_foods(
  p_query text,
  p_limit int default 20
)
returns setof public.foods
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  -- Cerca nel DB locale usando name_search per la ricerca full-text
  return query
  select f.*
  from public.foods f
  where f.is_active = true
    and (
      f.name_search ilike '%' || p_query || '%'
      or f.name ilike '%' || p_query || '%'
      or f.brand ilike '%' || p_query || '%'
      or f.barcode = p_query
    )
  order by f.trust_level desc, f.name
  limit p_limit;
  
  -- Se non trovato e sembra un barcode, chiama OFF
  if not found and p_query ~ '^[0-9]{8,14}$' then
    return query
    select f.*
    from public.openfoodfacts_search_and_cache(p_query) f;
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- DETTAGLIO ALIMENTO PER ID
-- ---------------------------------------------------------------------
create or replace function public.get_food(p_id uuid)
returns setof public.foods
language sql
security definer
set search_path = 'public'
as $$
  select f.*
  from public.foods f
  where f.id = p_id and f.is_active = true;
$$;

-- ---------------------------------------------------------------------
-- DETTAGLIO ALIMENTO PER BARCODE
-- ---------------------------------------------------------------------
create or replace function public.get_food_by_barcode(p_barcode text)
returns setof public.foods
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  -- Cerca nel DB locale
  return query
  select f.*
  from public.foods f
  where f.barcode = p_barcode and f.is_active = true;
  
  -- Se non trovato, cerca su OFF
  if not found then
    return query
    select f.*
    from public.openfoodfacts_search_and_cache(p_barcode) f;
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- CREA ALIMENTO (solo nutrizionisti verificati o admin)
-- ---------------------------------------------------------------------
create or replace function public.create_food(
  p_name text,
  p_brand text default null,
  p_barcode text default null,
  p_kcal numeric,
  p_protein_g numeric,
  p_carbs_g numeric,
  p_fat_g numeric,
  p_fiber_g numeric default null,
  p_sugars_g numeric default null,
  p_saturated_fat_g numeric default null,
  p_salt_g numeric default null,
  p_serving_g numeric default null,
  p_serving_label text default null
)
returns uuid
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_food_id uuid;
  v_user_id uuid := auth.uid();
  v_role public.user_role;
begin
  -- Verifica permessi
  select role into v_role from public.profiles where id = v_user_id;
  
  if v_role not in ('nutritionist', 'admin') then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  
  if v_role = 'nutritionist' and not exists (
    select 1 from public.profiles where id = v_user_id and professional_verified = true
  ) then
    raise exception 'nutritionist_not_verified' using errcode = '42501';
  end if;
  
  -- Crea alimento
  insert into public.foods (
    name, brand, barcode, source, source_id,
    verification, kcal, protein_g, carbs_g, fat_g,
    fiber_g, sugars_g, saturated_fat_g, salt_g, serving_g, serving_label,
    is_active
  ) values (
    p_name,
    p_brand,
    p_barcode,
    case when v_role = 'admin' then 'crea' else 'professional' end,
    coalesce(p_barcode, ''),
    case when v_role = 'admin' then 'verified' else 'unverified' end,
    p_kcal,
    p_protein_g,
    p_carbs_g,
    p_fat_g,
    p_fiber_g,
    p_sugars_g,
    p_saturated_fat_g,
    p_salt_g,
    p_serving_g,
    p_serving_label,
    true
  )
  returning id into v_food_id;
  
  return v_food_id;
end;
$$;

-- ---------------------------------------------------------------------
-- AGGIORNA ALIMENTO (solo creatore o admin)
-- ---------------------------------------------------------------------
create or replace function public.update_food(
  p_id uuid,
  p_name text default null,
  p_brand text default null,
  p_kcal numeric default null,
  p_protein_g numeric default null,
  p_carbs_g numeric default null,
  p_fat_g numeric default null,
  p_fiber_g numeric default null,
  p_sugars_g numeric default null,
  p_saturated_fat_g numeric default null,
  p_salt_g numeric default null,
  p_serving_g numeric default null,
  p_serving_label text default null
)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_user_id uuid := auth.uid();
  v_role public.user_role;
  v_created_by uuid;
begin
  -- Verifica permessi
  select role into v_role from public.profiles where id = v_user_id;
  select created_by into v_created_by from public.foods where id = p_id;
  
  if v_role <> 'admin' and v_created_by <> v_user_id then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  
  update public.foods
  set
    name = coalesce(p_name, name),
    brand = coalesce(p_brand, brand),
    kcal = coalesce(p_kcal, kcal),
    protein_g = coalesce(p_protein_g, protein_g),
    carbs_g = coalesce(p_carbs_g, carbs_g),
    fat_g = coalesce(p_fat_g, fat_g),
    fiber_g = coalesce(p_fiber_g, fiber_g),
    sugars_g = coalesce(p_sugars_g, sugars_g),
    saturated_fat_g = coalesce(p_saturated_fat_g, saturated_fat_g),
    salt_g = coalesce(p_salt_g, salt_g),
    serving_g = coalesce(p_serving_g, serving_g),
    serving_label = coalesce(p_serving_label, serving_label),
    updated_at = now()
  where id = p_id;
end;
$$;

-- ---------------------------------------------------------------------
-- ELIMINA ALIMENTO (soft delete - solo creatore o admin)
-- ---------------------------------------------------------------------
create or replace function public.delete_food(p_id uuid)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_user_id uuid := auth.uid();
  v_role public.user_role;
  v_created_by uuid;
begin
  select role into v_role from public.profiles where id = v_user_id;
  select created_by into v_created_by from public.foods where id = p_id;
  
  if v_role <> 'admin' and v_created_by <> v_user_id then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  
  update public.foods
  set is_active = false, updated_at = now()
  where id = p_id;
end;
$$;

-- ---------------------------------------------------------------------
-- DIARIO: REGISTRA PASTO
-- ---------------------------------------------------------------------
create or replace function public.log_meal(
  p_entry_date date,
  p_meal_slot public.meal_slot,
  p_food_id uuid default null,
  p_custom_name text default null,
  p_grams numeric
)
returns uuid
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_entry_id uuid;
  v_user_id uuid := auth.uid();
  v_food_record public.foods;
begin
  -- Se food_id fornito, recupera i valori nutrizionali
  if p_food_id is not null then
    select * into v_food_record from public.foods where id = p_food_id;
    
    if not found then
      raise exception 'food_not_found' using errcode = 'P0002';
    end if;
  end if;
  
  -- Inserisci voce diario
  insert into public.diary_entries (
    patient_id, entry_date, meal_slot, food_id, custom_name,
    grams, kcal, protein_g, carbs_g, fat_g,
    food_trust_level, entry_source
  ) values (
    v_user_id,
    p_entry_date,
    p_meal_slot,
    p_food_id,
    p_custom_name,
    p_grams,
    case when p_food_id is not null then round(v_food_record.kcal * p_grams / 100, 2) else 0 end,
    case when p_food_id is not null then round(v_food_record.protein_g * p_grams / 100, 2) else 0 end,
    case when p_food_id is not null then round(v_food_record.carbs_g * p_grams / 100, 2) else 0 end,
    case when p_food_id is not null then round(v_food_record.fat_g * p_grams / 100, 2) else 0 end,
    case when p_food_id is not null then v_food_record.trust_level else 0 end,
    case when p_food_id is not null then 'search' else 'manual' end
  )
  returning id into v_entry_id;
  
  return v_entry_id;
end;
$$;

-- ---------------------------------------------------------------------
-- DIARIO: OTTIENI ENTRATE PER DATA
-- ---------------------------------------------------------------------
create or replace function public.get_diary_entries(
  p_date date,
  p_patient_id uuid default null
)
returns setof public.diary_entries
language sql
security definer
set search_path = 'public'
as $$
  select de.*
  from public.diary_entries de
  where de.entry_date = p_date
    and de.patient_id = coalesce(p_patient_id, auth.uid())
  order by de.meal_slot, de.created_at;
$$;

-- ---------------------------------------------------------------------
-- DIARIO: ELIMINA VOCE
-- ---------------------------------------------------------------------
create or replace function public.delete_diary_entry(p_entry_id uuid)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  delete from public.diary_entries
  where id = p_entry_id and patient_id = auth.uid();
end;
$$;

-- ---------------------------------------------------------------------
-- PIANO MACRO: INIZIA NUOVO PIANO
-- ---------------------------------------------------------------------
create or replace function public.start_macro_plan(
  p_patient_id uuid,
  p_name text default 'Piano',
  p_valid_from date default current_date,
  p_targets jsonb default null
)
returns uuid
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_plan_id uuid;
  v_user_id uuid := auth.uid();
  v_role public.user_role;
  v_target jsonb;
begin
  -- Verifica permessi
  select role into v_role from public.profiles where id = v_user_id;
  
  if v_role = 'nutritionist' and not public.has_active_link(p_patient_id) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  
  if v_role = 'patient' and p_patient_id <> v_user_id then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  
  -- Chiudi piano precedente se esiste
  update public.macro_plans
  set valid_to = p_valid_from - 1
  where patient_id = p_patient_id
    and (valid_to is null or valid_to >= p_valid_from);
  
  -- Crea nuovo piano
  insert into public.macro_plans (patient_id, nutritionist_id, created_by, name, valid_from)
  values (
    p_patient_id,
    case when v_role = 'nutritionist' then v_user_id end,
    v_user_id,
    p_name,
    p_valid_from
  )
  returning id into v_plan_id;
  
  -- Inserisci target se forniti
  if p_targets is not null then
    for v_target in select * from jsonb_array_elements(p_targets)
    loop
      insert into public.macro_plan_targets (plan_id, day_of_week, meal_slot, protein_g, carbs_g, fat_g)
      values (
        v_plan_id,
        (v_target->>'day_of_week')::int,
        (v_target->>'meal_slot')::public.meal_slot,
        (v_target->>'protein_g')::numeric,
        (v_target->>'carbs_g')::numeric,
        (v_target->>'fat_g')::numeric
      );
    end loop;
  end if;
  
  return v_plan_id;
end;
$$;

-- ---------------------------------------------------------------------
-- PIANO MACRO: OTTIENI PIANO CORRENTE
-- ---------------------------------------------------------------------
create or replace function public.get_current_macro_plan(p_patient_id uuid default null)
returns setof public.macro_plans
language sql
security definer
set search_path = 'public'
as $$
  select mp.*
  from public.macro_plans mp
  where mp.patient_id = coalesce(p_patient_id, auth.uid())
    and (mp.valid_to is null or mp.valid_to >= current_date)
  order by mp.valid_from desc
  limit 1;
$$;

-- ---------------------------------------------------------------------
-- DASHBOARD: ADERENZA PAZIENTE
-- ---------------------------------------------------------------------
create or replace function public.get_patient_adherence(
  p_patient_id uuid,
  p_from date,
  p_to date,
  p_tolerance numeric default 0.10
)
returns setof public.adherence_day
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  -- Verifica permessi
  if auth.uid() <> p_patient_id and not public.can_nutritionist_see(p_patient_id, 'adherence') then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  
  return query
  select * from public.adherence_core(p_patient_id, p_from, p_to, p_tolerance);
end;
$$;

-- ---------------------------------------------------------------------
-- DASHBOARD: MIEI PAZIENTI (per nutrizionisti)
-- ---------------------------------------------------------------------
create or replace function public.get_my_patients()
returns table (
  patient_id uuid,
  display_name text,
  link_id uuid,
  linked_since timestamptz,
  shares_adherence boolean,
  last_logged_date date,
  days_logged_last_7 int,
  days_on_target_last_7 int,
  attention_score int
)
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  return query
  select * from public.my_patients_overview();
end;
$$;

-- ---------------------------------------------------------------------
-- PREFERITI: AGGIUNGI ALIMENTO PREFERITO
-- ---------------------------------------------------------------------
create or replace function public.add_favorite_food(
  p_food_id uuid,
  p_default_grams numeric default 100,
  p_default_slot public.meal_slot default null
)
returns uuid
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_favorite_id uuid;
begin
  insert into public.favorite_foods (patient_id, food_id, default_grams, default_slot)
  values (auth.uid(), p_food_id, p_default_grams, p_default_slot)
  on conflict (patient_id, food_id) do update
  set use_count = public.favorite_foods.use_count + 1, last_used_at = now()
  returning id into v_favorite_id;
  
  return v_favorite_id;
end;
$$;

-- ---------------------------------------------------------------------
-- PREFERITI: OTTIENI PREFERITI
-- ---------------------------------------------------------------------
create or replace function public.get_favorite_foods()
returns setof public.favorite_foods
language sql
security definer
set search_path = 'public'
as $$
  select ff.*
  from public.favorite_foods ff
  where ff.patient_id = auth.uid()
  order by ff.use_count desc, ff.last_used_at desc;
$$;

-- ---------------------------------------------------------------------
-- PASTI PERSONALI: CREA PASTO
-- ---------------------------------------------------------------------
create or replace function public.create_personal_meal(
  p_name text,
  p_default_slot public.meal_slot default null,
  p_items jsonb
)
returns uuid
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_meal_id uuid;
  v_item jsonb;
  v_position int := 0;
begin
  -- Crea pasto
  insert into public.personal_meals (patient_id, name, default_slot)
  values (auth.uid(), p_name, p_default_slot)
  returning id into v_meal_id;
  
  -- Inserisci ingredienti
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_position := v_position + 1;
    insert into public.personal_meal_items (meal_id, food_id, grams, position)
    values (
      v_meal_id,
      (v_item->>'food_id')::uuid,
      (v_item->>'grams')::numeric,
      v_position
    );
  end loop;
  
  return v_meal_id;
end;
$$;

-- ---------------------------------------------------------------------
-- PASTI PERSONALI: REGISTRA NEL DIARIO
-- ---------------------------------------------------------------------
create or replace function public.log_personal_meal(
  p_meal_id uuid,
  p_date date,
  p_slot public.meal_slot
)
returns integer
language plpgsql
security invoker
set search_path = 'public'
as $$
declare
  v_count int;
begin
  insert into public.diary_entries (patient_id, entry_date, meal_slot, food_id, grams, entry_source)
  select pm.patient_id, p_date, p_slot, pmi.food_id, pmi.grams, 'personal_meal'
  from public.personal_meals pm
  join public.personal_meal_items pmi on pmi.meal_id = pm.id
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
-- NOTIFICHE: OTTIENI NOTIFICHE NON LETTE
-- ---------------------------------------------------------------------
create or replace function public.get_unread_notifications()
returns setof public.notifications
language sql
security definer
set search_path = 'public'
as $$
  select n.*
  from public.notifications n
  where n.user_id = auth.uid() and not n.is_read
  order by n.created_at desc;
$$;

-- ---------------------------------------------------------------------
-- NOTIFICHE: SEGNA COME LETTA
-- ---------------------------------------------------------------------
create or replace function public.mark_notification_read(p_notification_id uuid)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  update public.notifications
  set is_read = true
  where id = p_notification_id and user_id = auth.uid();
end;
$$;

-- ---------------------------------------------------------------------
-- AUDIT: LOG ACCESSO DATI
-- ---------------------------------------------------------------------
create or replace function public.log_data_access(
  p_action text,
  p_entity text,
  p_entity_id text,
  p_patient_id uuid default null,
  p_extra_data jsonb default null
)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  insert into public.audit_log (actor_id, action, entity, entity_id, patient_id, extra_data)
  values (auth.uid(), p_action, p_entity, p_entity_id, p_patient_id, p_extra_data);
end;
$$;
