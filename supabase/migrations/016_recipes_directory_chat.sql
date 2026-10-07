-- =====================================================================
-- NutriMind — 016 RICETTE, VETRINA NUTRIZIONISTI, PIANI DI BASE, CHAT
-- Rieseguibile. Da eseguire dopo 014 e 015.
--
-- 1. Ricette (tabella esistente suggested_meals):
--    - nuovi campi: procedimento, link social, immagine, tempo, visibilità;
--    - il nutrizionista verificato pubblica le proprie ricette senza
--      revisione, per tutti ('public') o solo per i suoi pazienti ('patients');
--    - le ricette dei pazienti le revisiona il loro nutrizionista (o un
--      nutrizionista verificato se il paziente non è collegato a nessuno);
--    - gli alimenti non devono più essere 'verified' (in catalogo non ce
--      ne sono: gli import OFF e quelli dei nutrizionisti nascono
--      'unverified'), basta che siano attivi e non rifiutati;
--    - meal_recalc aggiorna anche i valori per porzione.
-- 2. Profilo pubblico del nutrizionista (nutritionist_details).
-- 3. Piani alimentari di base (nutritionist_plan_templates).
-- 4. Ricerca nutrizionisti (search_nutritionists, get_nutritionist_public).
-- 5. Chat paziente-nutrizionista (conversations, messages) con notifiche.
-- =====================================================================

alter type public.notification_type add value if not exists 'new_message';

-- ---------------------------------------------------------------------
-- Helper
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

-- =====================================================================
-- 1. RICETTE
-- =====================================================================
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

-- Ricalcolo totali e valori per porzione
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

-- Registra una ricetta visibile al chiamante (i macro li calcola il trigger
-- diary_entries_before_write)
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
     and (p_query is null or m.title ilike '%' || p_query || '%')
   order by public.is_my_nutritionist(m.proposed_by) desc, m.published_at desc nulls last
   limit least(greatest(coalesce(p_limit, 50), 1), 100)
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
  if jsonb_typeof(coalesce(p_items, '[]')) <> 'array' or jsonb_array_length(coalesce(p_items, '[]')) > 60 then
    raise exception 'invalid_items' using errcode = '22023';
  end if;

  if v_id is null then
    insert into public.suggested_meals (proposed_by, title) values (v_uid, coalesce(nullif(trim(p_data->>'title'), ''), 'Ricetta'))
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
  for v_item in select * from jsonb_array_elements(coalesce(p_items, '[]'))
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

-- =====================================================================
-- 2. PROFILO PUBBLICO DEL NUTRIZIONISTA
-- =====================================================================
alter table public.nutritionist_details
  add column if not exists profession text not null default 'nutritionist',
  add column if not exists headline text,
  add column if not exists specialties text[] not null default '{}',
  add column if not exists city text,
  add column if not exists online_consultations boolean not null default true,
  add column if not exists accepting_patients boolean not null default true,
  add column if not exists is_public boolean not null default false,
  add column if not exists instagram_url text,
  add column if not exists tiktok_url text,
  add column if not exists youtube_url text,
  add column if not exists website_url text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'nutritionist_details_profession_check') then
    alter table public.nutritionist_details add constraint nutritionist_details_profession_check
      check (profession in ('nutritionist', 'dietitian', 'personal_trainer'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'nutritionist_details_urls_check') then
    alter table public.nutritionist_details add constraint nutritionist_details_urls_check
      check (coalesce(instagram_url, 'https://') ~* '^https://'
         and coalesce(tiktok_url, 'https://') ~* '^https://'
         and coalesce(youtube_url, 'https://') ~* '^https://'
         and coalesce(website_url, 'https://') ~* '^https://');
  end if;
end;
$$;

grant update (
  profession, headline, specialties, city, online_consultations, accepting_patients, is_public,
  instagram_url, tiktok_url, youtube_url, website_url
) on public.nutritionist_details to authenticated;
grant insert (
  user_id, studio_name, bio, profession, headline, specialties, city, online_consultations,
  accepting_patients, is_public, instagram_url, tiktok_url, youtube_url, website_url
) on public.nutritionist_details to authenticated;

-- =====================================================================
-- 3. PIANI ALIMENTARI DI BASE (vetrina)
-- =====================================================================
create table if not exists public.nutritionist_plan_templates (
  id uuid primary key default gen_random_uuid(),
  nutritionist_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  title text not null check (char_length(title) between 1 and 120),
  description text check (char_length(coalesce(description, '')) <= 4000),
  goal_tags text[] not null default '{}',
  restriction_tags text[] not null default '{}',
  kcal numeric(7,2) check (kcal is null or kcal between 0 and 10000),
  protein_g numeric(6,2),
  carbs_g numeric(6,2),
  fat_g numeric(6,2),
  duration_weeks smallint check (duration_weeks is null or duration_weeks between 1 and 104),
  price_label text check (char_length(coalesce(price_label, '')) <= 60),
  is_published boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.nutritionist_plan_templates enable row level security;

drop trigger if exists plan_templates_updated_at on public.nutritionist_plan_templates;
create trigger plan_templates_updated_at before update on public.nutritionist_plan_templates
for each row execute function public.set_updated_at();

create index if not exists plan_templates_nutritionist_idx on public.nutritionist_plan_templates (nutritionist_id);

drop policy if exists plan_templates_owner_all on public.nutritionist_plan_templates;
create policy plan_templates_owner_all on public.nutritionist_plan_templates for all to authenticated
using (nutritionist_id = (select auth.uid()))
with check (nutritionist_id = (select auth.uid())
            and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'nutritionist'));

-- Security definer: chi consulta non vede le righe profiles/details degli
-- altri nutrizionisti, quindi una subquery diretta nella policy darebbe false
create or replace function public.is_public_nutritionist(p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.profiles p join public.nutritionist_details d on d.user_id = p.id
                  where p.id = p_user and p.role = 'nutritionist' and p.professional_verified and d.is_public)
$$;

drop policy if exists plan_templates_select_published on public.nutritionist_plan_templates;
create policy plan_templates_select_published on public.nutritionist_plan_templates for select to authenticated
using (is_published and (public.is_public_nutritionist(nutritionist_id) or public.is_my_nutritionist(nutritionist_id)));

grant select, insert, update, delete on public.nutritionist_plan_templates to authenticated;

-- =====================================================================
-- 4. RICERCA NUTRIZIONISTI
-- =====================================================================
create or replace function public.search_nutritionists(
  p_query text default null,
  p_specialty text default null,
  p_restriction text default null,
  p_online boolean default null,
  p_limit integer default 30
)
returns table (
  id uuid, display_name text, profession text, headline text, studio_name text, bio text,
  specialties text[], city text, online_consultations boolean, accepting_patients boolean,
  instagram_url text, tiktok_url text, youtube_url text, website_url text,
  recipes_count bigint, plans_count bigint, is_my_nutritionist boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.display_name, d.profession, d.headline, d.studio_name, d.bio,
         d.specialties, d.city, d.online_consultations, d.accepting_patients,
         d.instagram_url, d.tiktok_url, d.youtube_url, d.website_url,
         (select count(*) from public.suggested_meals m
           where m.proposed_by = p.id and m.status = 'approved' and m.visibility = 'public'),
         (select count(*) from public.nutritionist_plan_templates t
           where t.nutritionist_id = p.id and t.is_published),
         public.is_my_nutritionist(p.id)
    from public.profiles p
    join public.nutritionist_details d on d.user_id = p.id
   where p.role = 'nutritionist' and p.professional_verified and d.is_public
     and (p_query is null or p.display_name ilike '%' || p_query || '%'
          or d.studio_name ilike '%' || p_query || '%' or d.city ilike '%' || p_query || '%'
          or d.headline ilike '%' || p_query || '%')
     and (p_specialty is null or p_specialty = any (d.specialties))
     and (p_online is null or d.online_consultations = p_online)
     and (p_restriction is null or exists (
          select 1 from public.suggested_meals m
           where m.proposed_by = p.id and m.status = 'approved' and m.visibility = 'public'
             and p_restriction = any (m.restriction_tags)))
   order by d.accepting_patients desc, p.display_name
   limit least(greatest(coalesce(p_limit, 30), 1), 100)
$$;

-- =====================================================================
-- 5. CHAT
-- =====================================================================
create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.profiles (id) on delete cascade,
  nutritionist_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  last_message_at timestamptz not null default now(),
  constraint conversations_distinct check (patient_id <> nutritionist_id),
  constraint conversations_unique_pair unique (patient_id, nutritionist_id)
);
alter table public.conversations enable row level security;

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  sender_id uuid not null references public.profiles (id) on delete cascade,
  kind text not null default 'text' check (kind in ('text', 'invite', 'recipe')),
  body text not null check (char_length(body) between 1 and 4000),
  payload jsonb not null default '{}',
  created_at timestamptz not null default now(),
  read_at timestamptz
);
alter table public.messages enable row level security;
create index if not exists messages_conversation_idx on public.messages (conversation_id, created_at);

create or replace function public.is_conversation_member(p_conversation uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.conversations c
                  where c.id = p_conversation and (select auth.uid()) in (c.patient_id, c.nutritionist_id))
$$;

drop policy if exists conversations_select_member on public.conversations;
create policy conversations_select_member on public.conversations for select to authenticated
using ((select auth.uid()) in (patient_id, nutritionist_id));

drop policy if exists messages_select_member on public.messages;
create policy messages_select_member on public.messages for select to authenticated
using (public.is_conversation_member(conversation_id));

grant select on public.conversations to authenticated;
grant select on public.messages to authenticated;
-- Scritture solo tramite le RPC qui sotto (validazione e notifiche)

-- Apre (o riprende) la conversazione con un nutrizionista visibile in
-- vetrina o già collegato. Il nutrizionista può aprirla con un suo paziente.
create or replace function public.start_conversation(p_other uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := (select auth.uid());
  v_role public.user_role;
  v_id   uuid;
  v_patient uuid;
  v_nutritionist uuid;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  select role into v_role from public.profiles where id = v_uid;

  if v_role = 'patient' then
    v_patient := v_uid; v_nutritionist := p_other;
    if not public.is_my_nutritionist(p_other) then
      if not public.is_public_nutritionist(p_other) then
        raise exception 'forbidden' using errcode = '42501';
      end if;
      -- Chi non accetta nuovi pazienti resta contattabile solo da chi ha
      -- già una conversazione aperta
      if not exists (select 1 from public.nutritionist_details d where d.user_id = p_other and d.accepting_patients)
         and not exists (select 1 from public.conversations c where c.patient_id = v_uid and c.nutritionist_id = p_other) then
        raise exception 'not_accepting_patients' using errcode = '42501';
      end if;
    end if;
  elsif v_role = 'nutritionist' then
    v_patient := p_other; v_nutritionist := v_uid;
    if not public.has_active_link(p_other) then raise exception 'forbidden' using errcode = '42501'; end if;
  else
    raise exception 'forbidden' using errcode = '42501';
  end if;

  insert into public.conversations (patient_id, nutritionist_id)
  values (v_patient, v_nutritionist)
  on conflict (patient_id, nutritionist_id) do update set patient_id = excluded.patient_id
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.send_message(p_conversation uuid, p_body text, p_kind text default 'text', p_payload jsonb default '{}')
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_conv public.conversations;
  v_recipient uuid;
  v_id uuid;
  v_recent int;
  v_name text;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  select * into v_conv from public.conversations where id = p_conversation;
  if not found or v_uid not in (v_conv.patient_id, v_conv.nutritionist_id) then
    raise exception 'not_found' using errcode = 'P0002';
  end if;
  if coalesce(trim(p_body), '') = '' then raise exception 'empty_message' using errcode = '22023'; end if;
  if p_kind not in ('text', 'recipe') then raise exception 'invalid_kind' using errcode = '22023'; end if;

  -- limite anti-spam: 30 messaggi al minuto per conversazione
  select count(*) into v_recent from public.messages
   where conversation_id = p_conversation and sender_id = v_uid and created_at > now() - interval '1 minute';
  if v_recent >= 30 then raise exception 'rate_limited' using errcode = '54000'; end if;

  insert into public.messages (conversation_id, sender_id, kind, body, payload)
  values (p_conversation, v_uid, p_kind, left(trim(p_body), 4000), coalesce(p_payload, '{}'))
  returning id into v_id;

  update public.conversations set last_message_at = now() where id = p_conversation;

  v_recipient := case when v_uid = v_conv.patient_id then v_conv.nutritionist_id else v_conv.patient_id end;
  select display_name into v_name from public.profiles where id = v_uid;
  insert into public.notifications (user_id, type, title, body, data)
  values (v_recipient, 'new_message', 'Nuovo messaggio da ' || coalesce(nullif(v_name, ''), 'NutriMind'),
          left(trim(p_body), 140), jsonb_build_object('conversation_id', p_conversation, 'message_id', v_id));
  return v_id;
end;
$$;

-- Il nutrizionista invia in chat un codice invito che il paziente usa con un tocco
create or replace function public.send_invitation_message(p_conversation uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_conv public.conversations;
  v_code text;
  v_id uuid;
begin
  select * into v_conv from public.conversations where id = p_conversation;
  if not found or v_uid <> v_conv.nutritionist_id then raise exception 'forbidden' using errcode = '42501'; end if;
  v_code := public.create_invitation();
  insert into public.messages (conversation_id, sender_id, kind, body, payload)
  values (p_conversation, v_uid, 'invite', 'Ti ho inviato un invito per collegarci su NutriMind.',
          jsonb_build_object('code', v_code))
  returning id into v_id;
  update public.conversations set last_message_at = now() where id = p_conversation;
  insert into public.notifications (user_id, type, title, body, data)
  values (v_conv.patient_id, 'new_message', 'Invito dal nutrizionista',
          'Apri la chat per collegarti', jsonb_build_object('conversation_id', p_conversation, 'message_id', v_id));
  return v_id;
end;
$$;

create or replace function public.mark_conversation_read(p_conversation uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.messages
     set read_at = now()
   where conversation_id = p_conversation
     and sender_id <> (select auth.uid())
     and read_at is null
     and public.is_conversation_member(p_conversation)
$$;

create or replace function public.get_my_conversations()
returns table (
  id uuid, other_id uuid, other_name text, other_role public.user_role,
  last_message text, last_message_at timestamptz, unread_count bigint, linked boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select c.id,
         o.id, o.display_name, o.role,
         (select m.body from public.messages m where m.conversation_id = c.id order by m.created_at desc limit 1),
         c.last_message_at,
         (select count(*) from public.messages m
           where m.conversation_id = c.id and m.sender_id <> (select auth.uid()) and m.read_at is null),
         exists (select 1 from public.patient_links l
                  where l.patient_id = c.patient_id and l.nutritionist_id = c.nutritionist_id and l.status = 'active')
    from public.conversations c
    join public.profiles o on o.id = case when c.patient_id = (select auth.uid()) then c.nutritionist_id else c.patient_id end
   where (select auth.uid()) in (c.patient_id, c.nutritionist_id)
   order by c.last_message_at desc
$$;

-- Realtime per i messaggi
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables
                      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'messages') then
    alter publication supabase_realtime add table public.messages;
  end if;
end;
$$;

-- =====================================================================
-- PERMESSI
-- =====================================================================
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
         'log_suggested_meal', 'get_recipes_for_me', 'get_meals_to_review', 'search_meal_library',
         'search_nutritionists', 'start_conversation', 'send_message', 'send_invitation_message',
         'mark_conversation_read', 'get_my_conversations', 'save_meal_draft', 'get_recipe_author')
  loop
    execute format('revoke execute on function %s from public, anon', v_fn);
    execute format('grant execute on function %s to authenticated', v_fn);
  end loop;

  -- helper interni: non esposti via API
  for v_fn in
    select p.oid::regprocedure
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('meal_recalc', 'meal_has_unusable_foods')
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', v_fn);
  end loop;
end;
$$;
