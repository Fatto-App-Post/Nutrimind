-- =====================================================================
-- NutriMind — 002 UTENTI, RUOLI, COLLEGAMENTI E CONSENSI
-- =====================================================================

create table public.profiles (
id uuid primary key references auth.users (id) on delete cascade,
role public.user_role not null default 'patient',
display_name text not null default '' check (char_length(display_name) <= 80),
locale text not null default 'it' check (locale ~ '^[a-z]{2}(-[A-Z]{2})?$'),
professional_verified boolean not null default false,
created_at timestamptz not null default now(),
updated_at timestamptz not null default now(),
constraint profiles_verified_only_pro check (not professional_verified or role in ('nutritionist', 'admin'))
);
alter table public.profiles enable row level security;
create trigger profiles_updated_at before update on public.profiles
for each row execute function public.set_updated_at();

create table public.patient_settings (
user_id uuid primary key references public.profiles (id) on delete cascade,
dietary_restrictions text[] not null default '{}',
timezone text not null default 'Europe/Rome',
reminders_enabled boolean not null default true,
reminder_after_hours smallint not null default 24,
updated_at timestamptz not null default now()
);
alter table public.patient_settings enable row level security;
create trigger patient_settings_updated_at before update on public.patient_settings
for each row execute function public.set_updated_at();

create table public.nutritionist_details (
user_id uuid primary key references public.profiles (id) on delete cascade,
studio_name text,
bio text,
updated_at timestamptz not null default now()
);
alter table public.nutritionist_details enable row level security;
create trigger nutritionist_details_updated_at before update on public.nutritionist_details
for each row execute function public.set_updated_at();

create table public.professional_verifications (
id uuid primary key default gen_random_uuid(),
user_id uuid not null references public.profiles (id) on delete cascade,
license_body text not null,
license_number text not null,
status public.verification_status not null default 'pending',
reviewed_by uuid references public.profiles (id) on delete set null,
reviewed_at timestamptz,
created_at timestamptz not null default now()
);
alter table public.professional_verifications enable row level security;

create table public.patient_links (
id uuid primary key default gen_random_uuid(),
patient_id uuid not null references public.profiles (id) on delete cascade,
nutritionist_id uuid not null references public.profiles (id) on delete cascade,
status public.link_status not null default 'active',
created_at timestamptz not null default now(),
revoked_at timestamptz,
revoked_by uuid references public.profiles (id) on delete set null,
constraint links_distinct_parties check (patient_id <> nutritionist_id),
constraint links_unique_pair unique (patient_id, nutritionist_id)
);
alter table public.patient_links enable row level security;

create table public.consents (
id uuid primary key default gen_random_uuid(),
link_id uuid not null,
patient_id uuid not null,
nutritionist_id uuid not null,
scope public.consent_scope not null,
policy_version text not null,
granted_at timestamptz not null default now(),
revoked_at timestamptz,
constraint consents_link_fk foreign key (link_id, patient_id, nutritionist_id)
references public.patient_links (id, patient_id, nutritionist_id) on delete cascade
);
alter table public.consents enable row level security;

create table public.invitations (
id uuid primary key default gen_random_uuid(),
nutritionist_id uuid not null references public.profiles (id) on delete cascade,
code text not null unique,
max_uses smallint not null default 1,
used_count smallint not null default 0,
expires_at timestamptz not null,
created_at timestamptz not null default now()
);
alter table public.invitations enable row level security;
