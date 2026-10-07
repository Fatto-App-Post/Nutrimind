-- =====================================================================
-- NutriMind — 026 CORREGGE start_macro_plan: kcal_estimated È GENERATA
-- Rieseguibile.
--
-- La 023 scriveva `macro_plan_targets.kcal_estimated`, che è una colonna
-- **generata** come `protein_g*4 + carbs_g*4 + fat_g*9`. Risultato:
-- qualsiasi creazione di piano finiva con
--
--   428C9  cannot insert a non-DEFAULT value into column "kcal_estimated"
--
-- cioè il piano macro non si poteva salvare, né dal professionista né in
-- autogestione. È lo stesso errore in cui era incappata `meal_recalc`
-- con le colonne `*_per_serving` di `suggested_meals`.
--
-- La formula che la 023 calcolava a mano è identica a quella della
-- colonna generata, quindi basta non scriverla: il risultato è lo stesso
-- e lo tiene aggiornato il database.
--
-- Come si è visto: provando per la prima volta a creare un piano con un
-- paziente collegato. Da qui il controllo aggiunto in
-- `verify_frontend_contract.sql`, che elenca le colonne generate delle
-- due tabelle in cui ci siamo già sbagliati.
-- =====================================================================

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
        -- kcal_estimated non si scrive: è generata dal database con la
        -- stessa formula di Atwater (4/4/9).
        insert into public.macro_plan_targets
          (plan_id, day_of_week, meal_slot, protein_g, carbs_g, fat_g)
        values (
          v_plan_id,
          (v_target->>'day_of_week')::int,
          (v_target->>'meal_slot')::public.meal_slot,
          round(v_protein, 1),
          round(v_carbs, 1),
          round(v_fat, 1)
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
