-- =====================================================================
-- NutriMind — 030 «UTENTE BASE» DOVUNQUE SERVA
-- Rieseguibile. **Richiede la 029 già eseguita, in uno script separato.**
--
-- La 029 aggiunge il valore all'enum; qui lo si usa. Separate perché
-- PostgreSQL non permette di usare un valore di enum nella stessa
-- transazione in cui è stato aggiunto (55P04).
--
-- Prima di scrivere questa migration è stato controllato **cosa
-- dipende** dal ruolo paziente, invece di indovinarlo:
--
--   * **nessuna policy RLS** lo guarda. Le policy usano
--     `patient_id = auth.uid()` e le funzioni d'aiuto
--     (`has_active_link`, `can_nutritionist_see`, …), non il ruolo.
--     Questo è il motivo per cui l'operazione è fattibile senza
--     rimettere in discussione la sicurezza di tutto il database;
--   * **nove funzioni** contengono la stringa `'patient'`. Due la usano
--     soltanto come etichetta nel registro di controllo
--     (`my_patients_overview`, `patient_adherence`) e non vanno toccate.
--     Una, `start_new_plan`, è superata da `start_macro_plan` e **non è
--     chiamata da nessuna parte nell'app**: si lascia com'è e si
--     eliminerà a parte, perché cambiarla significherebbe riscrivere
--     cento righe che nessuno esegue.
--
-- Restano le sei qui sotto, più `revoke_link`, che non nominava il
-- ruolo ma è il punto in cui si torna utente base.
--
-- La regola generale: dove il controllo serviva a dire «questa persona
-- è un assistito, non un professionista», ora vale per entrambi i
-- ruoli. Dove serviva a dire «ha un nutrizionista» si usava già
-- `has_active_link` e non cambia niente.
--
-- Due cose controllate prima di consegnare, perché avrebbero cambiato
-- il risultato:
--
--   * **nessuna policy e nessuna funzione legge il ruolo dal token**
--     (`auth.jwt()`, `app_metadata`): tutte leggono `public.profiles`.
--     Quindi la promozione ha effetto **subito**, e il client non deve
--     rinnovare la sessione dopo essersi collegato. Se un giorno un
--     controllo passasse al token, questo smetterebbe di essere vero e
--     servirebbe un `refreshSession()` dopo il riscatto dell'invito;
--   * i cambi di ruolo li registra già il trigger `profiles_audit`
--     (`audit_profile_privileged`), con valore di partenza e di arrivo.
--     Qui non si scrive nel registro, altrimenti ogni promozione
--     lascerebbe due righe per lo stesso fatto.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Chi si iscrive adesso è un utente base
-- ---------------------------------------------------------------------
-- Un ruolo diverso da `nutritionist` resta non assegnabile dal client:
-- chi scrivesse `admin` nei metadati della registrazione diventa utente
-- base come tutti.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_meta   jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  v_role   public.user_role;
  v_name   text;
  v_locale text;
begin
  v_role := case v_meta->>'role'
              when 'nutritionist' then 'nutritionist'::public.user_role
              else 'base_user'::public.user_role
            end;

  -- display_name: quello scelto, altrimenti la parte locale dell'email.
  -- profiles.display_name è NOT NULL e lungo al massimo 80 caratteri.
  v_name := nullif(btrim(coalesce(v_meta->>'display_name', '')), '');
  v_name := coalesce(v_name, nullif(split_part(coalesce(new.email, ''), '@', 1), ''), 'Utente');
  v_name := left(v_name, 80);

  -- profiles.locale ha un vincolo di formato: se non è una lingua valida
  -- si usa l'italiano.
  v_locale := coalesce(v_meta->>'locale', '');
  if v_locale !~ '^[a-z]{2}(-[A-Z]{2})?$' then
    v_locale := 'it';
  end if;

  insert into public.profiles (id, role, display_name, locale)
  values (new.id, v_role, v_name, v_locale)
  on conflict (id) do nothing;

  insert into public.patient_settings (user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  return new;
end;
$$;

-- ---------------------------------------------------------------------
-- Un collegamento può nascere da un utente base
-- ---------------------------------------------------------------------
-- Il controllo di questo trigger scatta **prima** della promozione,
-- perché la riga del collegamento si scrive per prima: senza questa
-- modifica nessun utente base potrebbe collegarsi a nessuno.

create or replace function public.links_validate_roles()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from public.profiles
                  where id = new.patient_id and role in ('patient', 'base_user')) then
    raise exception 'link_patient_must_be_patient' using errcode = '23514';
  end if;
  if not exists (select 1 from public.profiles
                  where id = new.nutritionist_id and role = 'nutritionist') then
    raise exception 'link_nutritionist_must_be_nutritionist' using errcode = '23514';
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------
-- Riscattare un invito promuove a paziente
-- ---------------------------------------------------------------------
-- Il ruolo cambia **qui dentro**, nella stessa transazione del
-- collegamento: se il collegamento non si scrive, la promozione non
-- avviene, e viceversa. È il modo di non avere un «paziente» senza
-- nutrizionista.
--
-- Resta intatto il motivo per cui questa funzione, quando il codice non
-- va, restituisce null invece di sollevare un errore: prima scrive il
-- tentativo fallito in `invitation_attempts`, e un `raise` annullerebbe
-- anche quella scrittura insieme al conteggio che ferma chi prova i
-- codici a raffica. Il client distingue il null (migration 027 lato
-- app).

create or replace function public.redeem_invitation(
  p_code           text,
  p_scopes         public.consent_scope[] default '{}'::public.consent_scope[],
  p_policy_version text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid   uuid := (select auth.uid());
  v_inv   public.invitations;
  v_link  uuid;
  v_fails int;
  v_scope public.consent_scope;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if not exists (select 1 from public.profiles
                  where id = v_uid and role in ('patient', 'base_user')) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if coalesce(cardinality(p_scopes), 0) > 0 and coalesce(trim(p_policy_version), '') = '' then
    raise exception 'policy_version_required' using errcode = '22023';
  end if;

  select count(*) into v_fails from public.invitation_attempts
   where user_id = v_uid and not succeeded and attempted_at > now() - interval '15 minutes';
  if v_fails >= 10 then raise exception 'too_many_attempts' using errcode = '54000'; end if;

  select * into v_inv from public.invitations
   where code = upper(trim(p_code)) and used_at is null and revoked_at is null and expires_at > now()
   for update;

  if not found then
    insert into public.invitation_attempts (user_id, succeeded) values (v_uid, false);
    return null;
  end if;

  insert into public.patient_links (patient_id, nutritionist_id)
  values (v_uid, v_inv.nutritionist_id)
  on conflict (patient_id, nutritionist_id)
  do update set status = 'active', revoked_at = null, revoked_by = null, created_at = now()
  returning id into v_link;

  update public.invitations set used_by = v_uid, used_at = now() where id = v_inv.id;
  insert into public.invitation_attempts (user_id, succeeded) values (v_uid, true);

  -- Da utente base a paziente. Il `where` sul ruolo rende l'operazione
  -- ripetibile e non tocca chi è già paziente.
  --
  -- Il cambio non si registra qui: lo fa già il trigger
  -- `profiles_audit` su ogni modifica di `role`, con il valore di
  -- partenza e quello di arrivo. Scriverlo anche qui vorrebbe dire due
  -- righe nel registro per lo stesso fatto.
  update public.profiles set role = 'patient'
   where id = v_uid and role = 'base_user';

  if p_scopes is not null then
    foreach v_scope in array p_scopes loop
      insert into public.consents (link_id, patient_id, nutritionist_id, scope, policy_version)
      values (v_link, v_uid, v_inv.nutritionist_id, v_scope, trim(p_policy_version))
      on conflict do nothing;
    end loop;
  end if;
  return v_link;
end;
$$;

-- ---------------------------------------------------------------------
-- Interrompere l'ultimo collegamento riporta a utente base
-- ---------------------------------------------------------------------
-- La retrocessione riguarda il **paziente di quel collegamento**, non
-- chi ha premuto il pulsante: scollegare lo può fare anche il
-- nutrizionista. E avviene solo se non resta nessun altro collegamento
-- attivo, perché nulla vieta di avere due professionisti.

create or replace function public.revoke_link(p_link_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := (select auth.uid());
  v_patient uuid;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;

  select patient_id into v_patient from public.patient_links
   where id = p_link_id and status = 'active' and (patient_id = v_uid or nutritionist_id = v_uid)
   for update;
  if v_patient is null then raise exception 'not_found' using errcode = 'P0002'; end if;

  update public.patient_links
     set status = 'revoked', revoked_at = now(), revoked_by = v_uid
   where id = p_link_id;
  update public.consents set revoked_at = now() where link_id = p_link_id and revoked_at is null;

  -- Come sopra: la registrazione la fa il trigger `profiles_audit`.
  if not exists (select 1 from public.patient_links
                  where patient_id = v_patient and status = 'active') then
    update public.profiles set role = 'base_user'
     where id = v_patient and role = 'patient';
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- Un utente base può scrivere a un professionista pubblico
-- ---------------------------------------------------------------------
-- È il modo in cui si trova un nutrizionista: senza questa modifica la
-- vetrina sarebbe guardabile ma non contattabile proprio da chi non ha
-- ancora nessuno.

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

  if v_role in ('patient', 'base_user') then
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

-- ---------------------------------------------------------------------
-- Autogestione del piano anche per gli utenti base
-- ---------------------------------------------------------------------
-- Questa è la più importante delle sette: senza, un utente base non
-- potrebbe impostarsi nessun obiettivo, cioè l'app non gli servirebbe a
-- niente. Il resto della funzione è identico alla 026, compreso il fatto
-- che `kcal_estimated` non si scrive perché è generata.

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

  if v_role in ('patient', 'base_user') then
    if p_patient_id <> v_user_id then
      raise exception 'forbidden' using errcode = '42501';
    end if;
    -- Autogestione solo senza professionista: con un collegamento attivo
    -- il piano lo decide lui, e un paziente che lo riscrivesse di
    -- nascosto renderebbe inutile l'aderenza calcolata sul piano. Un
    -- utente base per definizione non ha collegamenti, quindi questo
    -- controllo per lui non scatta mai: resta perché il ruolo e i
    -- collegamenti potrebbero disallinearsi, e in quel caso deve
    -- vincere il collegamento.
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

-- ---------------------------------------------------------------------
-- Il quadro dell'amministratore conta anche gli utenti base
-- ---------------------------------------------------------------------
-- Senza questa modifica il conteggio «pazienti» sarebbe crollato da un
-- giorno all'altro, perché quasi tutti diventano utenti base: non un
-- errore dell'app, ma un numero che racconta una cosa falsa.

create or replace function public.get_admin_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = 'public'
as $$
declare
  v_out jsonb;
begin
  if not public.is_admin() then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'pending_verifications',
      (select count(*) from public.professional_verifications where status = 'pending'),
    'foods_to_review',
      (select count(*) from public.foods
        where is_active and verification = 'unverified' and source in ('user', 'professional')),
    'meals_to_review',
      (select count(*) from public.suggested_meals where status = 'pending_review'),
    'patients',
      (select count(*) from public.profiles where role = 'patient'),
    'base_users',
      (select count(*) from public.profiles where role = 'base_user'),
    'professionals',
      (select count(*) from public.profiles where role = 'nutritionist'),
    'verified_professionals',
      (select count(*) from public.profiles where role = 'nutritionist' and professional_verified),
    'public_professionals',
      (select count(*) from public.nutritionist_details where is_public),
    'active_links',
      (select count(*) from public.patient_links where status = 'active'),
    'foods_total',
      (select count(*) from public.foods where is_active),
    'foods_verified',
      (select count(*) from public.foods where is_active and verification = 'verified'),
    'recipes_published',
      (select count(*) from public.suggested_meals where status = 'approved'),
    'diary_entries_last_7',
      (select count(*) from public.diary_entries where entry_date >= current_date - 6)
  ) into v_out;

  return v_out;
end;
$$;

-- ---------------------------------------------------------------------
-- Allineamento di quello che c'è già
-- ---------------------------------------------------------------------
-- Chi è `patient` senza nessun collegamento attivo è, per la regola
-- nuova, un utente base. Si corregge una volta qui. Non tocca i
-- professionisti né gli amministratori.

do $$
declare
  v_quanti integer;
begin
  with retrocessi as (
    update public.profiles p set role = 'base_user'
     where p.role = 'patient'
       and not exists (select 1 from public.patient_links l
                        where l.patient_id = p.id and l.status = 'active')
    returning p.id
  )
  select count(*) into v_quanti from retrocessi;
  raise notice 'Utenti riportati a base_user perche senza collegamento attivo: %', v_quanti;
end;
$$;

-- ---------------------------------------------------------------------
-- Lo stato da mostrare, in un posto solo
-- ---------------------------------------------------------------------
-- Il ruolo basta a sapere chi è chi, ma l'app ha bisogno anche di
-- sapere **se** c'è un collegamento attivo per decidere cosa mostrare
-- (per esempio la vista «Dal Mio Nutrizionista»). Tenendo le due cose
-- insieme in una funzione si evita che ogni schermata se le ricalcoli a
-- modo suo, ed è anche il posto dove si vede subito un eventuale
-- disallineamento fra ruolo e collegamenti.

create or replace function public.my_status()
returns jsonb
language sql
stable
security definer
set search_path = 'public'
as $$
  select jsonb_build_object(
    'role', p.role::text,
    'has_active_link', exists (select 1 from public.patient_links l
                                where l.patient_id = p.id and l.status = 'active'),
    'professional_verified', coalesce(p.professional_verified, false),
    'label', case p.role
               when 'base_user'    then 'Utente Base'
               when 'patient'      then 'Paziente'
               when 'nutritionist' then 'Professionista'
               when 'admin'        then 'Amministratore'
             end
  )
    from public.profiles p
   where p.id = (select auth.uid());
$$;

revoke all on function public.my_status() from public, anon;
grant execute on function public.my_status() to authenticated;
