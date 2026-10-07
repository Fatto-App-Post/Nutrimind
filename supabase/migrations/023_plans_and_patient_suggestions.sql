-- =====================================================================
-- NutriMind — 023 PIANI CON ISTRUZIONI, AUTOGESTIONE, CONSIGLI MIRATI
-- Rieseguibile.
--
-- Tre cose:
--
-- 1. `start_macro_plan` non accettava le note del piano, benché
--    `macro_plans.notes` esista da sempre: il professionista non aveva
--    modo di spiegare al paziente *come* seguire i numeri. Ora le
--    accetta e calcola anche `kcal_estimated` per ogni pasto.
--
-- 2. Autogestione. La funzione già permetteva a un paziente di crearsi
--    un piano, ma senza condizioni: un paziente seguito avrebbe potuto
--    sovrascrivere il piano del proprio professionista senza che questo
--    lo sapesse. Adesso il paziente può farlo **solo se non ha un
--    professionista collegato**; appena si collega, il piano torna in
--    mano al professionista.
--
-- 3. Consigli mirati. Finora un professionista poteva pubblicare ricette
--    per tutti o per i propri pazienti, ma non indicare *a quel*
--    paziente una ricetta o un alimento preciso. La tabella
--    `patient_suggestions` serve a questo e vale per entrambi.
--
-- La firma di `start_macro_plan` cambia: la vecchia va eliminata, perché
-- aggiungere un parametro con valore predefinito creerebbe due funzioni
-- omonime e PostgREST, che chiama per nome dei parametri, non saprebbe
-- quale scegliere.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1 e 2. Piani macro: note e autogestione
-- ---------------------------------------------------------------------

drop function if exists public.start_macro_plan(uuid, text, date, jsonb);

create or replace function public.start_macro_plan(
  p_patient_id uuid,
  p_name       text default 'Piano',
  p_valid_from date default current_date,
  p_targets    jsonb default null,
  p_notes      text default null
)
returns uuid
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_plan_id uuid;
  v_user_id uuid := auth.uid();
  v_role    public.user_role;
  v_target  jsonb;
  v_protein numeric;
  v_carbs   numeric;
  v_fat     numeric;
  v_rows    integer := 0;
begin
  if v_user_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select role into v_role from public.profiles where id = v_user_id;

  if v_role = 'nutritionist' and not public.has_active_link(p_patient_id) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  if v_role = 'patient' then
    if p_patient_id <> v_user_id then
      raise exception 'forbidden' using errcode = '42501';
    end if;
    -- Autogestione solo senza professionista: con un collegamento attivo
    -- il piano lo decide lui, e un paziente che lo riscrivesse di
    -- nascosto renderebbe inutile l'aderenza calcolata sul piano.
    if exists (select 1 from public.patient_links
                where patient_id = v_user_id and status = 'active') then
      raise exception 'plan_managed_by_nutritionist' using errcode = '55000';
    end if;
  end if;

  if p_valid_from < current_date - 365 or p_valid_from > current_date + 365 then
    raise exception 'invalid_entry_date' using errcode = '22008';
  end if;

  update public.macro_plans
     set valid_to = p_valid_from - 1
   where patient_id = p_patient_id
     and (valid_to is null or valid_to >= p_valid_from);

  insert into public.macro_plans (patient_id, nutritionist_id, created_by, name, valid_from, notes)
  values (
    p_patient_id,
    case when v_role = 'nutritionist' then v_user_id end,
    v_user_id,
    left(coalesce(nullif(btrim(p_name), ''), 'Piano'), 120),
    p_valid_from,
    nullif(btrim(coalesce(p_notes, '')), '')
  )
  returning id into v_plan_id;

  if p_targets is not null then
    for v_target in select * from jsonb_array_elements(p_targets)
    loop
      v_protein := greatest(coalesce((v_target->>'protein_g')::numeric, 0), 0);
      v_carbs   := greatest(coalesce((v_target->>'carbs_g')::numeric, 0), 0);
      v_fat     := greatest(coalesce((v_target->>'fat_g')::numeric, 0), 0);

      -- Un pasto senza macro non è un obiettivo: si salta.
      if v_protein + v_carbs + v_fat > 0 then
        insert into public.macro_plan_targets
          (plan_id, day_of_week, meal_slot, protein_g, carbs_g, fat_g, kcal_estimated)
        values (
          v_plan_id,
          (v_target->>'day_of_week')::int,
          (v_target->>'meal_slot')::public.meal_slot,
          round(v_protein, 1),
          round(v_carbs, 1),
          round(v_fat, 1),
          -- Atwater: 4 kcal/g per proteine e carboidrati, 9 per i grassi
          round(v_protein * 4 + v_carbs * 4 + v_fat * 9)
        );
        v_rows := v_rows + 1;
      end if;
    end loop;
  end if;

  if v_rows = 0 then
    raise exception 'plan_has_no_targets' using errcode = '23514';
  end if;

  return v_plan_id;
end;
$$;

revoke all on function public.start_macro_plan(uuid, text, date, jsonb, text) from public, anon;
grant execute on function public.start_macro_plan(uuid, text, date, jsonb, text) to authenticated;

-- Il paziente deve sapere se può autogestirsi, senza dover leggere i
-- collegamenti (che l'app comunque legge, ma così è una domanda sola).
create or replace function public.can_self_manage_plan()
returns boolean
language sql
stable
security definer
set search_path = 'public'
as $$
  select auth.uid() is not null
     and not exists (
       select 1 from public.patient_links
        where patient_id = auth.uid() and status = 'active'
     )
$$;

revoke all on function public.can_self_manage_plan() from public, anon;
grant execute on function public.can_self_manage_plan() to authenticated;

-- ---------------------------------------------------------------------
-- 3. Consigli mirati a un singolo paziente
-- ---------------------------------------------------------------------

create table if not exists public.patient_suggestions (
  id              uuid primary key default gen_random_uuid(),
  patient_id      uuid not null references public.profiles(id) on delete cascade,
  nutritionist_id uuid not null references public.profiles(id) on delete cascade,
  meal_id         uuid references public.suggested_meals(id) on delete cascade,
  food_id         uuid references public.foods(id) on delete cascade,
  note            text check (char_length(note) <= 500),
  created_at      timestamptz not null default now(),
  -- una riga consiglia una ricetta **oppure** un alimento, non entrambi
  constraint patient_suggestions_one_target check ((meal_id is not null) <> (food_id is not null))
);

create unique index if not exists patient_suggestions_meal_unique
  on public.patient_suggestions (patient_id, nutritionist_id, meal_id) where meal_id is not null;
create unique index if not exists patient_suggestions_food_unique
  on public.patient_suggestions (patient_id, nutritionist_id, food_id) where food_id is not null;
create index if not exists patient_suggestions_patient_idx
  on public.patient_suggestions (patient_id, created_at desc);

alter table public.patient_suggestions enable row level security;

-- Scrittura solo tramite le funzioni qui sotto: nessun INSERT/UPDATE
-- diretto, così i controlli di autorizzazione stanno in un posto solo.
revoke all on table public.patient_suggestions from public, anon, authenticated;
grant select on table public.patient_suggestions to authenticated;

drop policy if exists patient_suggestions_select_own on public.patient_suggestions;
create policy patient_suggestions_select_own on public.patient_suggestions
  for select to authenticated
  using (patient_id = (select auth.uid()) or nutritionist_id = (select auth.uid()));

create or replace function public.suggest_to_patient(
  p_patient_id uuid,
  p_meal_id    uuid default null,
  p_food_id    uuid default null,
  p_note       text default null
)
returns uuid
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_me    uuid := auth.uid();
  v_id    uuid;
  v_title text;
begin
  if v_me is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if (p_meal_id is not null) = (p_food_id is not null) then
    raise exception 'invalid_state' using errcode = '22023';
  end if;
  if not public.has_active_link(p_patient_id) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  if p_meal_id is not null then
    -- Si può consigliare una ricetta propria o una già pubblicata.
    select m.title into v_title
      from public.suggested_meals m
     where m.id = p_meal_id
       and (m.proposed_by = v_me or m.status = 'approved');
    if v_title is null then
      raise exception 'not_found' using errcode = 'P0002';
    end if;
  else
    select f.name into v_title
      from public.foods f
     where f.id = p_food_id and f.is_active and f.verification <> 'rejected';
    if v_title is null then
      raise exception 'food_not_available' using errcode = '22023';
    end if;
  end if;

  insert into public.patient_suggestions (patient_id, nutritionist_id, meal_id, food_id, note)
  values (p_patient_id, v_me, p_meal_id, p_food_id,
          nullif(btrim(coalesce(p_note, '')), ''))
  on conflict do nothing
  returning id into v_id;

  if v_id is null then
    -- già consigliato: si restituisce quello esistente, non è un errore
    select id into v_id from public.patient_suggestions
     where patient_id = p_patient_id and nutritionist_id = v_me
       and meal_id is not distinct from p_meal_id
       and food_id is not distinct from p_food_id;
    return v_id;
  end if;

  insert into public.notifications (user_id, type, title, body, data)
  values (
    p_patient_id, 'system', 'Nuovo consiglio dal tuo nutrizionista',
    left(v_title, 200),
    jsonb_build_object('kind', 'new_suggestion', 'suggestion_id', v_id,
                       'meal_id', p_meal_id, 'food_id', p_food_id)
  );

  return v_id;
end;
$$;

create or replace function public.remove_patient_suggestion(p_id uuid)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  delete from public.patient_suggestions
   where id = p_id and nutritionist_id = auth.uid();
  if not found then
    raise exception 'not_found' using errcode = 'P0002';
  end if;
end;
$$;

-- Senza argomento restituisce i consigli ricevuti da chi chiama;
-- con un paziente, quelli che il professionista gli ha dato.
create or replace function public.get_patient_suggestions(p_patient_id uuid default null)
returns table (
  id          uuid,
  kind        text,
  meal_id     uuid,
  food_id     uuid,
  title       text,
  note        text,
  kcal        numeric,
  protein_g   numeric,
  carbs_g     numeric,
  fat_g       numeric,
  meal_slots  text[],
  author_name text,
  created_at  timestamptz
)
language plpgsql
stable
security definer
set search_path = 'public'
as $$
declare
  v_patient uuid := coalesce(p_patient_id, auth.uid());
begin
  if v_patient is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if v_patient <> auth.uid() and not public.has_active_link(v_patient) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  return query
  select s.id,
         case when s.meal_id is not null then 'recipe' else 'food' end,
         s.meal_id,
         s.food_id,
         coalesce(m.title, f.name),
         s.note,
         -- la ricetta per porzione, l'alimento per 100 g
         coalesce(m.kcal_per_serving, f.kcal),
         coalesce(m.protein_g_per_serving, f.protein_g),
         coalesce(m.carbs_g_per_serving, f.carbs_g),
         coalesce(m.fat_g_per_serving, f.fat_g),
         coalesce(m.meal_slots::text[], '{}'::text[]),
         coalesce(pr.display_name, 'Il tuo nutrizionista'),
         s.created_at
    from public.patient_suggestions s
    left join public.suggested_meals m on m.id = s.meal_id
    left join public.foods f on f.id = s.food_id
    left join public.profiles pr on pr.id = s.nutritionist_id
   where s.patient_id = v_patient
     -- un alimento disattivato non va più proposto
     and (s.food_id is null or f.is_active)
   order by s.created_at desc;
end;
$$;

revoke all on function public.suggest_to_patient(uuid, uuid, uuid, text) from public, anon;
revoke all on function public.remove_patient_suggestion(uuid) from public, anon;
revoke all on function public.get_patient_suggestions(uuid) from public, anon;
grant execute on function public.suggest_to_patient(uuid, uuid, uuid, text) to authenticated;
grant execute on function public.remove_patient_suggestion(uuid) to authenticated;
grant execute on function public.get_patient_suggestions(uuid) to authenticated;
