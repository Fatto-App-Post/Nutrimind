-- =====================================================================
-- NutriMind — 024 APPROVAZIONE DELLE VERIFICHE PROFESSIONALI
-- Rieseguibile.
--
-- Finora l'unico modo per abilitare un professionista era una UPDATE a
-- mano su `profiles.professional_verified`. Significa che nessuno può
-- gestire le iscrizioni senza accesso al database, e che il flag poteva
-- restare incoerente con la riga in `professional_verifications`.
--
-- Qui si aggiunge il minimo per un pannello di amministrazione nell'app:
-- l'elenco delle richieste e la decisione. L'approvazione aggiorna in
-- un'unica transazione la richiesta **e** il flag sul profilo, così i
-- due non possono più divergere.
--
-- Solo gli amministratori (`profiles.role = 'admin'`). Un amministratore
-- lo si nomina ancora da SQL, e va bene così: è l'unica operazione che
-- deve restare fuori dall'app.
--
--   update public.profiles set role = 'admin'
--    where id = (select id from auth.users where email = 'tu@esempio.it');
-- =====================================================================

create or replace function public.get_pending_verifications()
returns table (
  id            uuid,
  user_id       uuid,
  display_name  text,
  profession    text,
  license_body  text,
  license_number text,
  status        text,
  created_at    timestamptz,
  already_verified boolean
)
language plpgsql
stable
security definer
set search_path = 'public'
as $$
begin
  if not public.is_admin() then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  return query
  select v.id, v.user_id,
         coalesce(p.display_name, 'Professionista'),
         coalesce(nd.profession, 'nutritionist'),
         v.license_body, v.license_number,
         v.status::text, v.created_at,
         p.professional_verified
    from public.professional_verifications v
    join public.profiles p on p.id = v.user_id
    left join public.nutritionist_details nd on nd.user_id = v.user_id
   order by (v.status = 'pending') desc, v.created_at desc;
end;
$$;

create or replace function public.review_professional_verification(
  p_id       uuid,
  p_approve  boolean
)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_uid  uuid := (select auth.uid());
  v_user uuid;
  v_role public.user_role;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if not public.is_admin() then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  select v.user_id into v_user
    from public.professional_verifications v
   where v.id = p_id
     for update;
  if v_user is null then
    raise exception 'not_found' using errcode = 'P0002';
  end if;
  if v_user = v_uid then
    raise exception 'cannot_review_own_verification' using errcode = '42501';
  end if;

  -- profiles_verified_only_pro: il flag si può alzare solo su un
  -- professionista o un amministratore.
  select role into v_role from public.profiles where id = v_user;
  if p_approve and v_role not in ('nutritionist', 'admin') then
    raise exception 'not_a_professional' using errcode = '23514';
  end if;

  update public.professional_verifications
     set status = case when p_approve then 'verified' else 'rejected' end::public.verification_status,
         reviewed_by = v_uid,
         reviewed_at = now()
   where id = p_id;

  update public.profiles
     set professional_verified = p_approve
   where id = v_user;

  insert into public.notifications (user_id, type, title, body, data)
  values (
    v_user, 'system',
    case when p_approve then 'Abilitazione confermata' else 'Abilitazione non confermata' end,
    case when p_approve
         then 'Ora puoi comparire nella vetrina, pubblicare ricette e verificare quelle dei pazienti.'
         else 'Controlla i dati dell''albo e invia di nuovo la richiesta.' end,
    jsonb_build_object('kind', 'verification_reviewed', 'approved', p_approve)
  );
end;
$$;

revoke all on function public.get_pending_verifications() from public, anon;
revoke all on function public.review_professional_verification(uuid, boolean) from public, anon;
grant execute on function public.get_pending_verifications() to authenticated;
grant execute on function public.review_professional_verification(uuid, boolean) to authenticated;
