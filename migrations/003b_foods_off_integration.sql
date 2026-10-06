-- =====================================================================
-- NutriMind — 003b INTEGRAZIONE OPEN FOOD FACTS
-- =====================================================================

alter table public.foods
add column if not exists generic_name text,
add column if not exists product_name_it text,
add column if not exists quantity_text text,
add column if not exists quantity_value numeric,
add column if not exists quantity_unit text,
add column if not exists serving_size_text text,
add column if not exists image_front_url text,
add column if not exists image_nutrition_url text,
add column if not exists nutriscore_grade text,
add column if not exists ecoscore_grade text,
add column if not exists ecoscore_score numeric,
add column if not exists nova_group smallint,
add column if not exists completeness numeric,
add column if not exists off_last_modified_at timestamptz,
add column if not exists off_fetched_at timestamptz,
add column if not exists off_raw jsonb;

create unique index if not exists foods_off_barcode_idx
on public.foods (barcode)
where source = 'openfoodfacts' and barcode is not null;

create table public.food_off_sync_log (
id uuid primary key default gen_random_uuid(),
barcode text not null,
status text not null check (status in ('pending','running','success','failed','not_found')),
error_message text,
off_status_verbose text,
started_at timestamptz not null default now(),
finished_at timestamptz,
next_retry_at timestamptz,
attempt_count smallint not null default 1,
created_by uuid default auth.uid() references public.profiles (id) on delete set null
);
alter table public.food_off_sync_log enable row level security;

create index food_off_sync_log_barcode_idx on public.food_off_sync_log (barcode);
create index food_off_sync_log_status_retry_idx
on public.food_off_sync_log (status, next_retry_at)
where status in ('failed','pending');

create policy food_off_sync_log_select on public.food_off_sync_log
for select to authenticated using (true);

create or replace view public.v_foods_off_summary as
select
  f.id, f.barcode, f.name, f.brand, f.source, f.verification, f.trust_level,
  f.off_fetched_at, f.off_last_modified_at,
  (f.off_raw->>'status')::text as off_status,
  sl.status as last_sync_status,
  sl.finished_at as last_sync_finished_at
from public.foods f
left join lateral (
  select * from public.food_off_sync_log sl
  where sl.barcode = f.barcode
  order by sl.started_at desc limit 1
) sl on true
where f.source = 'openfoodfacts';

create or replace function public.get_or_plan_off_sync(p_barcode text)
returns setof public.foods
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_existing public.foods;
  v_log_id uuid;
begin
  select * into v_existing
  from public.foods
  where barcode = trim(p_barcode) and is_active and verification <> 'rejected'
  order by trust_level desc, created_at limit 1;

  if found then
    return query select * from public.foods where id = v_existing.id;
    return;
  end if;

  insert into public.food_off_sync_log (barcode, status)
  values (trim(p_barcode), 'pending');

  return;
end;
$$;
