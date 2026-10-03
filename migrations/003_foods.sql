-- =====================================================================
-- NutriMind — 003 DATABASE ALIMENTARE
-- =====================================================================

create table public.foods (
id uuid primary key default gen_random_uuid(),
name text not null,
brand text,
name_search text not null default '',
barcode text,
source public.food_source not null default 'user',
source_id text,
verification public.food_verification not null default 'unverified',
verified_by uuid references public.profiles (id) on delete set null,
verified_at timestamptz,
created_by uuid default auth.uid() references public.profiles (id) on delete set null,
kcal numeric(7,2) not null,
protein_g numeric(6,2) not null,
carbs_g numeric(6,2) not null,
fat_g numeric(6,2) not null,
fiber_g numeric(6,2),
sugars_g numeric(6,2),
saturated_fat_g numeric(6,2),
salt_g numeric(6,3),
serving_g numeric(7,2),
serving_label text,
trust_level smallint generated always as (
case when verification = 'verified' and source in ('usda', 'crea') then 3
     when verification = 'verified' then 2
     when verification = 'unverified' then 1
     else 0 end) stored,
is_active boolean not null default true,
created_at timestamptz not null default now(),
updated_at timestamptz not null default now(),
constraint foods_macro_sum_plausible check (protein_g + carbs_g + fat_g <= 100.5)
);
alter table public.foods enable row level security;

create unique index foods_source_unique on public.foods (source, source_id) where source_id is not null;
create index foods_barcode_idx on public.foods (barcode) where barcode is not null;
create index foods_name_trgm_idx on public.foods using gin (name_search extensions.gin_trgm_ops);

create table public.food_portions (
id uuid primary key default gen_random_uuid(),
food_id uuid not null references public.foods (id) on delete cascade,
label text not null,
grams numeric(7,2) not null,
created_at timestamptz not null default now(),
unique (food_id, label)
);
alter table public.food_portions enable row level security;

create or replace function public.foods_before_write()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
new.name_search := lower(extensions.unaccent('extensions.unaccent'::regdictionary, coalesce(new.name,'') || ' ' || coalesce(new.brand,'')));
new.updated_at := now();
return new;
end;
$$;
create trigger foods_before_write before insert or update on public.foods
for each row execute function public.foods_before_write();

create policy foods_select on public.foods for select to authenticated
using (is_active and verification <> 'rejected');

create policy foods_insert_user on public.foods for insert to authenticated
with check (source = 'user' and verification = 'unverified');

create policy food_portions_select on public.food_portions for select to authenticated
using (exists (select 1 from public.foods f where f.id = food_id));
