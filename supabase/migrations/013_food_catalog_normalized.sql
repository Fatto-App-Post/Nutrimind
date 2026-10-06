-- NutriMind — 013 FOOD CATALOG NORMALIZZATO
-- DEV first. foods remains the canonical NutriMind table.
-- Repeated and nested source data is normalized into child tables.

alter table public.foods
  add column if not exists external_code text,
  add column if not exists external_api_version text,
  add column if not exists external_last_synced_at timestamptz,
  add column if not exists external_payload_hash text,
  add column if not exists external_last_status integer,
  add column if not exists external_last_status_verbose text,
  add column if not exists external_raw_data jsonb not null default '{}'::jsonb,
  add column if not exists generic_name text,
  add column if not exists quantity_text text,
  add column if not exists serving_size_text text,
  add column if not exists product_quantity numeric,
  add column if not exists product_quantity_unit text,
  add column if not exists ingredients_text text,
  add column if not exists allergens_text text,
  add column if not exists traces_text text,
  add column if not exists labels_text text,
  add column if not exists categories_text text,
  add column if not exists main_category text,
  add column if not exists countries_text text,
  add column if not exists origins_text text,
  add column if not exists packaging_text text,
  add column if not exists completeness numeric,
  add column if not exists nutriscore_grade text,
  add column if not exists ecoscore_grade text,
  add column if not exists nova_group smallint;

create unique index if not exists foods_external_code_unique
  on public.foods (source, external_code)
  where external_code is not null;

create table if not exists public.food_tags (
  id uuid primary key default gen_random_uuid(),
  food_id uuid not null references public.foods(id) on delete cascade,
  tag_type text not null,
  tag text not null,
  language text,
  label text,
  position smallint,
  raw_data jsonb not null default '{}',
  created_at timestamptz not null default now(),
  unique (food_id, tag_type, tag, language)
);
create index if not exists food_tags_food_idx on public.food_tags(food_id);
create index if not exists food_tags_lookup_idx on public.food_tags(tag_type, tag);

create table if not exists public.food_nutrients (
  id uuid primary key default gen_random_uuid(),
  food_id uuid not null references public.foods(id) on delete cascade,
  nutrient_key text not null,
  value numeric,
  unit text,
  per_100g numeric,
  per_100ml numeric,
  per_serving numeric,
  per_portion numeric,
  prepared_value numeric,
  raw_data jsonb not null default '{}',
  created_at timestamptz not null default now(),
  unique (food_id, nutrient_key)
);
create index if not exists food_nutrients_food_idx on public.food_nutrients(food_id);
create index if not exists food_nutrients_key_value_idx on public.food_nutrients(nutrient_key, per_100g);

create table if not exists public.food_ingredients (
  id uuid primary key default gen_random_uuid(),
  food_id uuid not null references public.foods(id) on delete cascade,
  position integer not null,
  ingredient_id text,
  text text,
  text_en text,
  percent_estimate numeric,
  vegan_status text,
  vegetarian_status text,
  palm_oil_status text,
  analysis_tags text[] not null default '{}',
  raw_data jsonb not null default '{}',
  created_at timestamptz not null default now(),
  unique (food_id, position)
);
create index if not exists food_ingredients_food_idx on public.food_ingredients(food_id);

create table if not exists public.food_images (
  id uuid primary key default gen_random_uuid(),
  food_id uuid not null references public.foods(id) on delete cascade,
  image_id text,
  image_type text,
  language text,
  url text,
  small_url text,
  thumb_url text,
  uploaded_at timestamptz,
  uploader text,
  selected boolean not null default false,
  sizes jsonb not null default '{}',
  raw_data jsonb not null default '{}',
  created_at timestamptz not null default now()
);
create index if not exists food_images_food_idx on public.food_images(food_id);
create index if not exists food_images_selected_idx on public.food_images(food_id, selected);

create table if not exists public.food_packagings (
  id uuid primary key default gen_random_uuid(),
  food_id uuid not null references public.foods(id) on delete cascade,
  position integer not null,
  material text,
  shape text,
  recycling text,
  food_contact boolean,
  number_of_units numeric,
  quantity_per_unit text,
  weight_measured numeric,
  environmental_score numeric,
  raw_data jsonb not null default '{}',
  created_at timestamptz not null default now(),
  unique (food_id, position)
);
create index if not exists food_packagings_food_idx on public.food_packagings(food_id);

create table if not exists public.food_quality (
  id uuid primary key default gen_random_uuid(),
  food_id uuid not null unique references public.foods(id) on delete cascade,
  completeness numeric,
  data_quality_overall numeric,
  data_quality_general_information numeric,
  data_quality_ingredients numeric,
  data_quality_nutrition numeric,
  data_quality_packaging numeric,
  states text,
  states_tags text[] not null default '{}',
  quality_tags text[] not null default '{}',
  warning_tags text[] not null default '{}',
  error_tags text[] not null default '{}',
  raw_data jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists food_quality_food_idx on public.food_quality(food_id);

create table if not exists public.food_scores (
  id uuid primary key default gen_random_uuid(),
  food_id uuid not null references public.foods(id) on delete cascade,
  score_type text not null,
  grade text,
  score numeric,
  version text,
  preparation text,
  language text,
  data jsonb not null default '{}',
  created_at timestamptz not null default now(),
  unique (food_id, score_type, version, preparation, language)
);
create index if not exists food_scores_food_idx on public.food_scores(food_id);
create index if not exists food_scores_type_idx on public.food_scores(score_type, grade);

create table if not exists public.food_sources (
  id uuid primary key default gen_random_uuid(),
  food_id uuid not null references public.foods(id) on delete cascade,
  source_type text,
  source_name text,
  source_id text,
  source_url text,
  license text,
  license_url text,
  imported_at timestamptz,
  raw_data jsonb not null default '{}',
  created_at timestamptz not null default now(),
  unique (food_id, source_type, source_name, source_id)
);
create index if not exists food_sources_food_idx on public.food_sources(food_id);

create table if not exists public.food_snapshots (
  id uuid primary key default gen_random_uuid(),
  food_id uuid not null references public.foods(id) on delete cascade,
  source public.food_source not null,
  source_code text not null,
  api_version text,
  captured_at timestamptz not null default now(),
  response_hash text not null,
  http_status integer,
  changed_fields text[] not null default '{}',
  payload jsonb not null,
  created_at timestamptz not null default now(),
  unique (food_id, response_hash)
);
create index if not exists food_snapshots_food_idx on public.food_snapshots(food_id, captured_at desc);

alter table public.food_off_sync_log
  add column if not exists food_id uuid references public.foods(id) on delete set null,
  add column if not exists http_status integer,
  add column if not exists response_hash text,
  add column if not exists api_version text,
  add column if not exists source_updated_at timestamptz,
  add column if not exists changed_fields text[],
  add column if not exists payload_size_bytes integer;
create index if not exists food_off_sync_log_food_idx on public.food_off_sync_log(food_id);

alter table public.food_tags enable row level security;
alter table public.food_nutrients enable row level security;
alter table public.food_ingredients enable row level security;
alter table public.food_images enable row level security;
alter table public.food_packagings enable row level security;
alter table public.food_quality enable row level security;
alter table public.food_scores enable row level security;
alter table public.food_sources enable row level security;
alter table public.food_snapshots enable row level security;

create policy "food tags readable for active foods" on public.food_tags for select using (exists (select 1 from public.foods f where f.id = food_id and f.is_active));
create policy "food nutrients readable for active foods" on public.food_nutrients for select using (exists (select 1 from public.foods f where f.id = food_id and f.is_active));
create policy "food ingredients readable for active foods" on public.food_ingredients for select using (exists (select 1 from public.foods f where f.id = food_id and f.is_active));
create policy "food images readable for active foods" on public.food_images for select using (exists (select 1 from public.foods f where f.id = food_id and f.is_active));
create policy "food packagings readable for active foods" on public.food_packagings for select using (exists (select 1 from public.foods f where f.id = food_id and f.is_active));
create policy "food quality readable for active foods" on public.food_quality for select using (exists (select 1 from public.foods f where f.id = food_id and f.is_active));
create policy "food scores readable for active foods" on public.food_scores for select using (exists (select 1 from public.foods f where f.id = food_id and f.is_active));
create policy "food sources readable for active foods" on public.food_sources for select using (exists (select 1 from public.foods f where f.id = food_id and f.is_active));
create policy "food snapshots readable for active foods" on public.food_snapshots for select using (exists (select 1 from public.foods f where f.id = food_id and f.is_active));
