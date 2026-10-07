-- =====================================================================
-- NutriMind — 021 IL RUOLO SCELTO ALLA REGISTRAZIONE VIENE RISPETTATO
-- Rieseguibile.
--
-- handle_new_user() ignorava i metadati della registrazione e creava
-- sempre un profilo con role = 'patient' e display_name ricavato
-- dall'email. L'app invia invece:
--
--   auth.signUp(..., data: {'role': ..., 'display_name': ...})
--
-- Risultato: chi si registrava come nutrizionista diventava un paziente
-- e il nome scelto veniva buttato. Tutto il lato professionista
-- (pazienti, ricette, vetrina, piani di base) era quindi raggiungibile
-- solo correggendo il ruolo a mano in SQL.
--
-- Sicurezza: si accettano solo 'patient' e 'nutritionist'. 'admin' non
-- deve mai essere assegnabile dal client, e infatti qualsiasi altro
-- valore ricade su 'patient'. professional_verified resta false: un
-- professionista appena iscritto non compare in vetrina e non può
-- seguire pazienti finché non viene abilitato (vedi in fondo).
-- `authenticated` non ha il privilegio di UPDATE sulle colonne `role` e
-- `professional_verified` di profiles, quindi non si può alzare da soli.
-- =====================================================================

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
              else 'patient'::public.user_role
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

-- Il trigger di solito esiste già: lo si crea solo se manca, così la
-- migration funziona anche su un progetto nuovo. Non lo si ricrea mai,
-- perché auth.users appartiene al servizio di autenticazione e un
-- errore di privilegi annullerebbe tutta la migration.
do $$
begin
  if not exists (
    select 1 from pg_trigger
     where tgname = 'on_auth_user_created'
       and tgrelid = 'auth.users'::regclass
       and not tgisinternal
  ) then
    execute 'create trigger on_auth_user_created after insert on auth.users '
         || 'for each row execute function public.handle_new_user()';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Recupero: utenze senza profilo
--
-- Un'utenza creata prima del trigger (o dalla dashboard) resta senza
-- riga in profiles. L'app in quel caso mostra dati vuoti e ogni
-- scrittura che referenzia profiles(id) va in errore di chiave
-- esterna. Qui si creano i profili mancanti.
--
-- I profili che esistono già NON vengono toccati: un ruolo corretto a
-- mano in passato verrebbe sovrascritto. Per allineare una singola
-- utenza al ruolo scelto in fase di registrazione:
--
--   update public.profiles p
--      set role = 'nutritionist'
--     from auth.users u
--    where u.id = p.id and u.email = 'indirizzo@esempio.it';
-- ---------------------------------------------------------------------

insert into public.profiles (id, role, display_name, locale)
select u.id,
       case u.raw_user_meta_data->>'role'
         when 'nutritionist' then 'nutritionist'::public.user_role
         else 'patient'::public.user_role
       end,
       left(
         coalesce(
           nullif(btrim(coalesce(u.raw_user_meta_data->>'display_name', '')), ''),
           nullif(split_part(coalesce(u.email, ''), '@', 1), ''),
           'Utente'
         ), 80),
       'it'
  from auth.users u
 where not exists (select 1 from public.profiles p where p.id = u.id)
on conflict (id) do nothing;

insert into public.patient_settings (user_id)
select p.id
  from public.profiles p
 where not exists (select 1 from public.patient_settings s where s.user_id = p.id)
on conflict (user_id) do nothing;

-- ---------------------------------------------------------------------
-- Come abilitare un professionista (finché non esiste il pannello admin)
--
--   update public.profiles set professional_verified = true
--    where id = (select id from auth.users where email = 'indirizzo@esempio.it');
--
-- Poi il professionista, dal proprio profilo nell'app, attiva
-- "Mostrami in Trova un nutrizionista" per comparire in vetrina.
-- ---------------------------------------------------------------------
