-- =====================================================================
-- NutriMind — 001 FONDAMENTA
-- Estensioni, tipi enumerati, funzioni di utilità.
-- =====================================================================

create extension if not exists pg_trgm with schema extensions;
create extension if not exists unaccent with schema extensions;
create extension if not exists btree_gist with schema extensions;

create type public.user_role as enum ('patient', 'nutritionist', 'admin');
create type public.link_status as enum ('active', 'revoked');
create type public.consent_scope as enum ('adherence', 'diary', 'profile');
create type public.meal_slot as enum ('breakfast', 'morning_snack', 'lunch', 'afternoon_snack', 'dinner', 'evening_snack');
create type public.food_source as enum ('usda', 'crea', 'openfoodfacts', 'user', 'professional');
create type public.food_verification as enum ('verified', 'unverified', 'rejected');
create type public.approval_status as enum ('draft', 'pending_review', 'approved', 'rejected');
create type public.verification_status as enum ('pending', 'verified', 'rejected');
create type public.notification_type as enum ('logging_reminder', 'new_comment', 'plan_updated', 'link_event', 'meal_review', 'system');

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
new.updated_at := now();
return new;
end;
$$;
