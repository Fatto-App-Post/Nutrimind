-- =====================================================================
-- NutriMind — 017 VETRINA NUTRIZIONISTI E PIANI DI BASE
-- Rieseguibile. Da eseguire dopo la 016.
--
-- - nutritionist_details: profilo pubblico (professione, presentazione,
--   specializzazioni, città, consulenze online, social);
-- - nutritionist_plan_templates: piani alimentari "di base" in vetrina;
-- - search_nutritionists: ricerca per i pazienti.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Profilo pubblico
-- ---------------------------------------------------------------------
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
  studio_name, bio, profession, headline, specialties, city, online_consultations, accepting_patients, is_public,
  instagram_url, tiktok_url, youtube_url, website_url
) on public.nutritionist_details to authenticated;
-- L'upsert di PostgREST riscrive anche user_id: la policy impone user_id = auth.uid()
grant insert (
  user_id, studio_name, bio, profession, headline, specialties, city, online_consultations,
  accepting_patients, is_public, instagram_url, tiktok_url, youtube_url, website_url
) on public.nutritionist_details to authenticated;

-- Security definer: chi consulta non vede le righe profiles/details degli
-- altri nutrizionisti, quindi una subquery diretta in una policy darebbe false
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

-- ---------------------------------------------------------------------
-- 2. Piani alimentari di base
-- ---------------------------------------------------------------------
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

drop policy if exists plan_templates_select_published on public.nutritionist_plan_templates;
create policy plan_templates_select_published on public.nutritionist_plan_templates for select to authenticated
using (is_published and (public.is_public_nutritionist(nutritionist_id) or public.is_my_nutritionist(nutritionist_id)));

grant select, insert, update, delete on public.nutritionist_plan_templates to authenticated;

-- ---------------------------------------------------------------------
-- 3. Ricerca nutrizionisti
-- ---------------------------------------------------------------------
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
  with q as (select '%' || replace(replace(coalesce(p_query, ''), '%', '\%'), '_', '\_') || '%' as pattern)
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
    cross join q
   where p.role = 'nutritionist' and p.professional_verified and d.is_public
     and (p_query is null or p.display_name ilike q.pattern or d.studio_name ilike q.pattern
          or d.city ilike q.pattern or d.headline ilike q.pattern)
     and (p_specialty is null or p_specialty = any (d.specialties))
     and (p_online is null or d.online_consultations = p_online)
     and (p_restriction is null or exists (
          select 1 from public.suggested_meals m
           where m.proposed_by = p.id and m.status = 'approved' and m.visibility = 'public'
             and p_restriction = any (m.restriction_tags)))
   order by d.accepting_patients desc, p.display_name
   limit least(greatest(coalesce(p_limit, 30), 1), 100)
$$;

do $$
declare
  v_fn regprocedure;
begin
  for v_fn in
    select p.oid::regprocedure
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'search_nutritionists'
  loop
    execute format('revoke execute on function %s from public, anon', v_fn);
    execute format('grant execute on function %s to authenticated', v_fn);
  end loop;

  -- is_public_nutritionist resta eseguibile da authenticated: è usata nella
  -- policy plan_templates_select_published, valutata nel contesto del chiamante.
  for v_fn in
    select p.oid::regprocedure
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'is_public_nutritionist'
  loop
    execute format('revoke execute on function %s from public, anon', v_fn);
    execute format('grant execute on function %s to authenticated', v_fn);
  end loop;
end;
$$;
