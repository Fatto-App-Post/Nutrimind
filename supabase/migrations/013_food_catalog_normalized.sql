-- NutriMind — 013 FOOD CATALOG NORMALIZZATO
-- DEV first: foods remains the canonical food/product table.
-- Child tables contain only repeated or structured Open Food Facts data.

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
  raw_data jsonb not null default '{}'::jsonb,
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
  raw_data jsonb not null default '{}'::jsonb,
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
  raw_data jsonb not null default '{}'::jsonb,
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
  selected boolean not null default false,
  uploaded_at timestamptz,
  raw_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists food_images_food_idx on public.food_images(food_id);
create index if not exists food_images_selected_idx on public.food_images(food_id, selected);

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

create index if not exists food_snapshots_food_idx
  on public.food_snapshots(food_id, captured_at desc);

alter table public.food_off_sync_log
  add column if not exists food_id uuid references public.foods(id) on delete set null,
  add column if not exists http_status integer,
  add column if not exists response_hash text,
  add column if not exists api_version text,
  add column if not exists source_updated_at timestamptz,
  add column if not exists changed_fields text[],
  add column if not exists payload_size_bytes integer;

create index if not exists food_off_sync_log_food_idx
  on public.food_off_sync_log(food_id);

-- RLS: food catalog is readable with the same public food visibility model.
alter table public.food_tags enable row level security;
alter table public.food_nutrients enable row level security;
alter table public.food_ingredients enable row level security;
alter table public.food_images enable row level security;
alter table public.food_snapshots enable row level security;

create policy "food tags readable for active foods"
  on public.food_tags for select
  using (exists (select 1 from public.foods f where f.id = food_id and f.is_active));

create policy "food nutrients readable for active foods"
  on public.food_nutrients for select
  using (exists (select 1 from public.foods f where f.id = food_id and f.is_active));

create policy "food ingredients readable for active foods"
  on public.food_ingredients for select
  using (exists (select 1 from public.foods f where f.id = food_id and f.is_active));

create policy "food images readable for active foods"
  on public.food_images for select
  using (exists (select 1 from public.foods f where f.id = food_id and f.is_active));

create policy "food snapshots readable for active foods"
  on public.food_snapshots for select
  using (exists (select 1 from public.foods f where f.id = food_id and f.is_active));
