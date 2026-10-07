-- =====================================================================
-- NutriMind — 016 RICETTE (ex suggested_meals)
-- Rieseguibile. Da eseguire dopo 014 e 015.
--
-- Sostituisce la precedente 016_recipes_directory_chat.sql, che il SQL
-- Editor annullava per intero al primo errore: ora le tre aree (ricette,
-- vetrina, chat) sono in file separati e indipendenti.
--
-- - nuovi campi: procedimento, link social, immagine, tempo, visibilità;
-- - il nutrizionista verificato pubblica le proprie ricette senza
--   revisione, per tutti ('public') o solo per i suoi pazienti ('patients');
-- - le ricette dei pazienti le revisiona il loro nutrizionista (o un
--   nutrizionista verificato se il paziente non è collegato a nessuno);
-- - gli alimenti non devono più essere 'verified' (in catalogo non ce ne
--   sono: gli import OFF e quelli dei nutrizionisti nascono 'unverified'),
--   basta che siano attivi e non rifiutati;
-- - meal_recalc aggiorna anche i valori per porzione.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Helper condivisi (usati anche da 017 e 018)
-- ---------------------------------------------------------------------
create or replace function public.patient_has_nutritionist(p_patient uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.patient_links l where l.patient_id = p_patient and l.status = 'active')
$$;

-- Il chiamante (nutrizionista verificato) può revisionare le ricette di p_author?
create or replace function public.can_review_meals_of(p_author uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (public.is_verified_nutritionist() or public.is_admin())
     and p_author <> (select auth.uid())
     and (public.is_admin()
          or public.has_active_link(p_author)
          or not public.patient_has_nutritionist(p_author))
$$;

-- ---------------------------------------------------------------------
-- Nuovi campi
-- ---------------------------------------------------------------------
alter table public.suggested_meals
  add column if not exists instructions text,
  add column if not exists social_url text,
  add column if not exists image_url text,
  add column if not exists prep_minutes smallint,
  add column if not exists visibility text not null default 'public';

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'suggested_meals_visibility_check') then
    alter table public.suggested_meals
      add constraint suggested_meals_visibility_check check (visibility in ('public', 'patients'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'suggested_meals_social_url_check') then
    alter table public.suggested_meals
      add constraint suggested_meals_social_url_check
      check (social_url is null or (social_url ~* '^https://' and char_length(social_url) <= 500));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'suggested_meals_image_url_check') then
    alter table public.suggested_meals
      add constraint suggested_meals_image_url_check
      check (image_url is null or (image_url ~* '^https://' and char_length(image_url) <= 500));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'suggested_meals_text_len_check') then
    alter table public.suggested_meals
      add constraint suggested_meals_text_len_check
      check (char_length(title) between 1 and 120
             and char_length(coalesce(description, '')) <= 2000
             and char_length(coalesce(instructions, '')) <= 8000);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'suggested_meals_prep_check') then
    alter table public.suggested_meals
      add constraint suggested_meals_prep_check check (prep_minutes is null or prep_minutes between 0 and 1440);
  end if;
end;
$$;

-- Visibilità: le ricette 'patients' le vedono solo i pazienti collegati
drop policy if exists meals_select on public.suggested_meals;
create policy meals_select on public.suggested_meals for select to authenticated
using (
  proposed_by = (select auth.uid())
  or public.is_admin()
  or (status = 'approved' and (visibility = 'public' or public.is_my_nutritionist(proposed_by)))
  or (status = 'pending_review' and public.can_review_meals_of(proposed_by))
);

-- ---------------------------------------------------------------------
-- Totali e valori per porzione
-- ---------------------------------------------------------------------
create or replace function public.meal_recalc(p_meal uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.suggested_meals m
     set kcal_total            = round(t.k, 2),
         protein_g_total       = round(t.p, 2),
         carbs_g_total         = round(t.c, 2),
         fat_g_total           = round(t.f, 2),
         kcal_per_serving      = round(t.k / greatest(m.servings, 1), 2),
         protein_g_per_serving = round(t.p / greatest(m.servings, 1), 2),
         carbs_g_per_serving   = round(t.c / greatest(m.servings, 1), 2),
         fat_g_per_serving     = round(t.f / greatest(m.servings, 1), 2)
    from (select coalesce(sum(f.kcal      * i.grams / 100), 0) as k,
                 coalesce(sum(f.protein_g * i.grams / 100), 0) as p,
                 coalesce(sum(f.carbs_g   * i.grams / 100), 0) as c,
                 coalesce(sum(f.fat_g     * i.grams / 100), 0) as f
            from public.suggested_meal_items i
            join public.foods f on f.id = i.food_id
           where i.meal_id = p_meal) t
   where m.id = p_meal
$$;

-- Cambio porzioni: ricalcola i valori per porzione
create or replace function public.meal_servings_changed()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.meal_recalc(new.id);
  return null;
end;
$$;

drop trigger if exists meals_servings_changed on public.suggested_meals;
create trigger meals_servings_changed after update of servings on public.suggested_meals
for each row when (old.servings is distinct from new.servings)
execute function public.meal_servings_changed();

-- Alimenti utilizzabili in una ricetta: attivi e non rifiutati
create or replace function public.meal_has_unusable_foods(p_meal uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from (select food_id from public.suggested_meal_items where meal_id = p_meal
            union all
            select replacement_food_id from public.suggested_meal_swaps where meal_id = p_meal) x
      join public.foods f on f.id = x.food_id
     where not f.is_active or f.verification = 'rejected')
$$;

-- ---------------------------------------------------------------------
-- Ciclo di vita della ricetta
-- ---------------------------------------------------------------------
create or replace function public.submit_meal_for_review(p_meal_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := (select auth.uid());
  v_meal public.suggested_meals;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;

  select * into v_meal from public.suggested_meals where id = p_meal_id and proposed_by = v_uid for update;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  if v_meal.status not in ('draft', 'rejected') then raise exception 'invalid_state' using errcode = '55000'; end if;
  if not exists (select 1 from public.suggested_meal_items where meal_id = p_meal_id) then
    raise exception 'meal_has_no_items' using errcode = '23514';
  end if;
  if public.meal_has_unusable_foods(p_meal_id) then
    raise exception 'unusable_foods_in_meal' using errcode = '23514';
  end if;

  update public.suggested_meals
     set status = 'pending_review', review_notes = null, reviewed_by = null, reviewed_at = null
   where id = p_meal_id;
end;
$$;

create or replace function public.review_meal(p_meal_id uuid, p_approve boolean, p_notes text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := (select auth.uid());
  v_meal public.suggested_meals;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;

  select * into v_meal from public.suggested_meals where id = p_meal_id for update;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  if not public.can_review_meals_of(v_meal.proposed_by) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if v_meal.status <> 'pending_review' then raise exception 'invalid_state' using errcode = '55000'; end if;
  if not p_approve and coalesce(trim(p_notes), '') = '' then
    raise exception 'rejection_notes_required' using errcode = '22023';
  end if;
  if p_approve and public.meal_has_unusable_foods(p_meal_id) then
    raise exception 'unusable_foods_in_meal' using errcode = '23514';
  end if;

  update public.suggested_meals
     set status       = case when p_approve then 'approved'::public.approval_status else 'rejected'::public.approval_status end,
         reviewed_by  = v_uid,
         reviewed_at  = now(),
         review_notes = left(nullif(trim(coalesce(p_notes, '')), ''), 1000),
         published_at = case when p_approve then now() end
   where id = p_meal_id;
end;
$$;

-- Il nutrizionista verificato pubblica direttamente le proprie ricette
create or replace function public.publish_own_meal(p_meal_id uuid, p_visibility text default 'patients')
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := (select auth.uid());
  v_meal public.suggested_meals;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if not public.is_verified_nutritionist() then raise exception 'nutritionist_not_verified' using errcode = '42501'; end if;
  if p_visibility not in ('public', 'patients') then raise exception 'invalid_visibility' using errcode = '22023'; end if;

  select * into v_meal from public.suggested_meals where id = p_meal_id and proposed_by = v_uid for update;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  if v_meal.status not in ('draft', 'rejected') then raise exception 'invalid_state' using errcode = '55000'; end if;
  if not exists (select 1 from public.suggested_meal_items where meal_id = p_meal_id) then
    raise exception 'meal_has_no_items' using errcode = '23514';
  end if;
  if public.meal_has_unusable_foods(p_meal_id) then
    raise exception 'unusable_foods_in_meal' using errcode = '23514';
  end if;

  update public.suggested_meals
     set status = 'approved', visibility = p_visibility,
         reviewed_by = v_uid, reviewed_at = now(), review_notes = null, published_at = now()
   where id = p_meal_id;
end;
$$;

-- Ritira una ricetta pubblicata dal nutrizionista (torna in bozza)
create or replace function public.unpublish_own_meal(p_meal_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.suggested_meals
     set status = 'draft', published_at = null
   where id = p_meal_id and proposed_by = (select auth.uid()) and status = 'approved';
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
end;
$$;

-- Salva una bozza con i suoi ingredienti in un'unica transazione
-- (p_data: campi della ricetta; p_items: [{food_id, grams}]).
create or replace function public.save_meal_draft(p_meal_id uuid, p_data jsonb, p_items jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_id  uuid := p_meal_id;
  v_item jsonb;
  v_pos int := 0;
  v_visibility text := coalesce(p_data->>'visibility', 'public');
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if v_visibility not in ('public', 'patients') then raise exception 'invalid_visibility' using errcode = '22023'; end if;
  if jsonb_typeof(coalesce(p_items, '[]'::jsonb)) <> 'array' or jsonb_array_length(coalesce(p_items, '[]'::jsonb)) > 60 then
    raise exception 'invalid_items' using errcode = '22023';
  end if;

  if v_id is null then
    insert into public.suggested_meals (proposed_by, title)
    values (v_uid, coalesce(nullif(trim(p_data->>'title'), ''), 'Ricetta'))
    returning id into v_id;
  elsif not exists (select 1 from public.suggested_meals
                     where id = v_id and proposed_by = v_uid and status in ('draft', 'rejected')) then
    raise exception 'not_found' using errcode = 'P0002';
  end if;

  update public.suggested_meals set
    title            = coalesce(nullif(trim(p_data->>'title'), ''), title),
    description      = nullif(trim(p_data->>'description'), ''),
    instructions     = nullif(trim(p_data->>'instructions'), ''),
    meal_slots       = coalesce((select array_agg(x::public.meal_slot) from jsonb_array_elements_text(p_data->'meal_slots') x), '{}'),
    servings         = greatest(1, least(coalesce((p_data->>'servings')::int, 1), 50)),
    restriction_tags = coalesce((select array_agg(x) from jsonb_array_elements_text(p_data->'restriction_tags') x), '{}'),
    goal_tags        = coalesce((select array_agg(x) from jsonb_array_elements_text(p_data->'goal_tags') x), '{}'),
    social_url       = nullif(trim(p_data->>'social_url'), ''),
    prep_minutes     = (p_data->>'prep_minutes')::smallint,
    visibility       = v_visibility
  where id = v_id;

  delete from public.suggested_meal_items where meal_id = v_id;
  for v_item in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb))
  loop
    if (v_item->>'grams')::numeric is null or (v_item->>'grams')::numeric <= 0 or (v_item->>'grams')::numeric > 5000 then
      raise exception 'invalid_items' using errcode = '22023';
    end if;
    insert into public.suggested_meal_items (meal_id, food_id, grams, position)
    values (v_id, (v_item->>'food_id')::uuid, (v_item->>'grams')::numeric, v_pos);
    v_pos := v_pos + 1;
  end loop;
  perform public.meal_recalc(v_id);
  return v_id;
end;
$$;

-- Registra una ricetta visibile al chiamante (i macro li calcola il
-- trigger diary_entries_before_write)
create or replace function public.log_suggested_meal(p_meal_id uuid, p_date date, p_slot public.meal_slot, p_servings numeric default 1)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid   uuid := (select auth.uid());
  v_count integer;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if p_servings is null or p_servings <= 0 or p_servings > 20 then
    raise exception 'invalid_servings' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.suggested_meals m
     where m.id = p_meal_id
       and (m.proposed_by = v_uid
            or (m.status = 'approved' and (m.visibility = 'public' or public.is_my_nutritionist(m.proposed_by))))
  ) then
    raise exception 'not_found' using errcode = 'P0002';
  end if;

  insert into public.diary_entries (patient_id, entry_date, meal_slot, food_id, grams, entry_source)
  select v_uid, p_date, p_slot, i.food_id, round(i.grams * p_servings / greatest(m.servings, 1), 2), 'suggested_meal'
    from public.suggested_meals m
    join public.suggested_meal_items i on i.meal_id = m.id
   where m.id = p_meal_id
   order by i.position;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- ---------------------------------------------------------------------
-- Letture per il frontend
-- ---------------------------------------------------------------------

-- Ricette per l'aggiunta al diario: quelle del mio nutrizionista prima,
-- poi la libreria pubblica; filtri per pasto e restrizioni.
create or replace function public.get_recipes_for_me(
  p_slot public.meal_slot default null,
  p_restrictions text[] default '{}',
  p_query text default null,
  p_limit integer default 50
)
returns table (
  id uuid, title text, description text, meal_slots public.meal_slot[], servings smallint,
  restriction_tags text[], goal_tags text[], social_url text, image_url text, prep_minutes smallint,
  kcal_per_serving numeric, protein_g_per_serving numeric, carbs_g_per_serving numeric, fat_g_per_serving numeric,
  author_id uuid, author_name text, author_role public.user_role, from_my_nutritionist boolean, published_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select m.id, m.title, m.description, m.meal_slots, m.servings,
         m.restriction_tags, m.goal_tags, m.social_url, m.image_url, m.prep_minutes,
         coalesce(m.kcal_per_serving, m.kcal_total / greatest(m.servings, 1)),
         coalesce(m.protein_g_per_serving, m.protein_g_total / greatest(m.servings, 1)),
         coalesce(m.carbs_g_per_serving, m.carbs_g_total / greatest(m.servings, 1)),
         coalesce(m.fat_g_per_serving, m.fat_g_total / greatest(m.servings, 1)),
         m.proposed_by, p.display_name, m.proposer_role,
         public.is_my_nutritionist(m.proposed_by), m.published_at
    from public.suggested_meals m
    left join public.profiles p on p.id = m.proposed_by
   where m.status = 'approved'
     and (m.visibility = 'public' or public.is_my_nutritionist(m.proposed_by))
     and (p_slot is null or p_slot = any (m.meal_slots) or cardinality(m.meal_slots) = 0)
     and m.restriction_tags @> coalesce(p_restrictions, '{}')
     and (p_query is null or m.title ilike '%' || replace(replace(p_query, '%', '\%'), '_', '\_') || '%')
   order by public.is_my_nutritionist(m.proposed_by) desc, m.published_at desc nulls last
   limit least(greatest(coalesce(p_limit, 50), 1), 100)
$$;

-- Autore di una ricetta visibile al chiamante (profiles non è leggibile
-- direttamente per autori non collegati)
create or replace function public.get_recipe_author(p_meal_id uuid)
returns table (author_name text, author_role public.user_role, from_my_nutritionist boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select p.display_name, m.proposer_role, public.is_my_nutritionist(m.proposed_by)
    from public.suggested_meals m
    left join public.profiles p on p.id = m.proposed_by
   where m.id = p_meal_id
     and (m.proposed_by = (select auth.uid())
          or (m.status = 'approved' and (m.visibility = 'public' or public.is_my_nutritionist(m.proposed_by)))
          or (m.status = 'pending_review' and public.can_review_meals_of(m.proposed_by)))
$$;

-- Ricette dei pazienti in attesa di revisione per il nutrizionista
create or replace function public.get_meals_to_review()
returns table (id uuid, title text, author_id uuid, author_name text, created_at timestamptz, kcal_total numeric)
language sql
stable
security definer
set search_path = ''
as $$
  select m.id, m.title, m.proposed_by, p.display_name, m.created_at, m.kcal_total
    from public.suggested_meals m
    left join public.profiles p on p.id = m.proposed_by
   where m.status = 'pending_review' and public.can_review_meals_of(m.proposed_by)
   order by m.created_at
$$;

-- ---------------------------------------------------------------------
-- Permessi
-- ---------------------------------------------------------------------
grant select, delete on public.suggested_meals to authenticated;
grant insert (title, description, meal_slots, servings, goal_tags, restriction_tags,
              instructions, social_url, image_url, prep_minutes, visibility)
  on public.suggested_meals to authenticated;
grant update (title, description, meal_slots, servings, goal_tags, restriction_tags,
              instructions, social_url, image_url, prep_minutes, visibility)
  on public.suggested_meals to authenticated;
grant select, insert, update, delete on public.suggested_meal_items to authenticated;

do $$
declare
  v_fn regprocedure;
begin
  for v_fn in
    select p.oid::regprocedure
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in (
         'submit_meal_for_review', 'withdraw_meal', 'review_meal', 'publish_own_meal', 'unpublish_own_meal',
         'log_suggested_meal', 'save_meal_draft', 'get_recipe_author', 'get_recipes_for_me',
         'get_meals_to_review', 'search_meal_library')
  loop
    execute format('revoke execute on function %s from public, anon', v_fn);
    execute format('grant execute on function %s to authenticated', v_fn);
  end loop;

  -- helper interni: non esposti via API.
  -- can_review_meals_of resta eseguibile da authenticated: è usata nella
  -- policy meals_select, valutata nel contesto del chiamante.
  for v_fn in
    select p.oid::regprocedure
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('meal_recalc', 'meal_has_unusable_foods', 'patient_has_nutritionist')
  loop
    execute format('revoke execute on function %s from public, anon', v_fn);
    execute format('revoke execute on function %s from authenticated', v_fn);
  end loop;

  for v_fn in
    select p.oid::regprocedure
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'can_review_meals_of'
  loop
    execute format('revoke execute on function %s from public, anon', v_fn);
    execute format('grant execute on function %s to authenticated', v_fn);
  end loop;
end;
$$;
