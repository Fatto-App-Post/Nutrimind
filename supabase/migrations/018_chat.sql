-- =====================================================================
-- NutriMind — 018 CHAT PAZIENTE-NUTRIZIONISTA
-- Rieseguibile. Da eseguire dopo la 017.
--
-- Le notifiche dei messaggi usano il tipo 'system' con
-- data->>'conversation_id': aggiungere un valore a notification_type
-- richiederebbe un ALTER TYPE, che il SQL Editor non può eseguire nella
-- stessa transazione del resto dello script.
--
-- Le tabelle sono leggibili solo dai due partecipanti; le scritture
-- passano dalle RPC, che validano i membri, limitano lo spam e creano la
-- notifica per il destinatario.
-- =====================================================================

create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.profiles (id) on delete cascade,
  nutritionist_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  last_message_at timestamptz not null default now(),
  constraint conversations_distinct check (patient_id <> nutritionist_id),
  constraint conversations_unique_pair unique (patient_id, nutritionist_id)
);
alter table public.conversations enable row level security;

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  sender_id uuid not null references public.profiles (id) on delete cascade,
  kind text not null default 'text' check (kind in ('text', 'invite', 'recipe')),
  body text not null check (char_length(body) between 1 and 4000),
  payload jsonb not null default '{}',
  created_at timestamptz not null default now(),
  read_at timestamptz
);
alter table public.messages enable row level security;
create index if not exists messages_conversation_idx on public.messages (conversation_id, created_at);

create or replace function public.is_conversation_member(p_conversation uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.conversations c
                  where c.id = p_conversation and (select auth.uid()) in (c.patient_id, c.nutritionist_id))
$$;

drop policy if exists conversations_select_member on public.conversations;
create policy conversations_select_member on public.conversations for select to authenticated
using ((select auth.uid()) in (patient_id, nutritionist_id));

drop policy if exists messages_select_member on public.messages;
create policy messages_select_member on public.messages for select to authenticated
using (public.is_conversation_member(conversation_id));

grant select on public.conversations to authenticated;
grant select on public.messages to authenticated;

-- ---------------------------------------------------------------------
-- Operazioni
-- ---------------------------------------------------------------------

-- Apre (o riprende) la conversazione con un nutrizionista in vetrina o già
-- collegato. Il nutrizionista può aprirla con un proprio paziente.
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

  if v_role = 'patient' then
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

create or replace function public.send_message(p_conversation uuid, p_body text, p_kind text default 'text', p_payload jsonb default '{}')
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_conv public.conversations;
  v_recipient uuid;
  v_id uuid;
  v_recent int;
  v_name text;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  select * into v_conv from public.conversations where id = p_conversation;
  if not found or v_uid not in (v_conv.patient_id, v_conv.nutritionist_id) then
    raise exception 'not_found' using errcode = 'P0002';
  end if;
  if coalesce(trim(p_body), '') = '' then raise exception 'empty_message' using errcode = '22023'; end if;
  if p_kind not in ('text', 'recipe') then raise exception 'invalid_kind' using errcode = '22023'; end if;

  -- limite anti-spam: 30 messaggi al minuto per conversazione
  select count(*) into v_recent from public.messages
   where conversation_id = p_conversation and sender_id = v_uid and created_at > now() - interval '1 minute';
  if v_recent >= 30 then raise exception 'rate_limited' using errcode = '54000'; end if;

  insert into public.messages (conversation_id, sender_id, kind, body, payload)
  values (p_conversation, v_uid, p_kind, left(trim(p_body), 4000), coalesce(p_payload, '{}'::jsonb))
  returning id into v_id;

  update public.conversations set last_message_at = now() where id = p_conversation;

  v_recipient := case when v_uid = v_conv.patient_id then v_conv.nutritionist_id else v_conv.patient_id end;
  select display_name into v_name from public.profiles where id = v_uid;
  insert into public.notifications (user_id, type, title, body, data)
  values (v_recipient, 'system', 'Nuovo messaggio da ' || coalesce(nullif(v_name, ''), 'NutriMind'),
          left(trim(p_body), 140),
          jsonb_build_object('kind', 'new_message', 'conversation_id', p_conversation, 'message_id', v_id));
  return v_id;
end;
$$;

-- Il nutrizionista invia in chat un codice invito che il paziente usa con un tocco
create or replace function public.send_invitation_message(p_conversation uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_conv public.conversations;
  v_code text;
  v_id uuid;
begin
  select * into v_conv from public.conversations where id = p_conversation;
  if not found or v_uid <> v_conv.nutritionist_id then raise exception 'forbidden' using errcode = '42501'; end if;
  v_code := public.create_invitation();
  insert into public.messages (conversation_id, sender_id, kind, body, payload)
  values (p_conversation, v_uid, 'invite', 'Ti ho inviato un invito per collegarci su NutriMind.',
          jsonb_build_object('code', v_code))
  returning id into v_id;
  update public.conversations set last_message_at = now() where id = p_conversation;
  insert into public.notifications (user_id, type, title, body, data)
  values (v_conv.patient_id, 'system', 'Invito dal nutrizionista', 'Apri la chat per collegarti',
          jsonb_build_object('kind', 'new_message', 'conversation_id', p_conversation, 'message_id', v_id));
  return v_id;
end;
$$;

create or replace function public.mark_conversation_read(p_conversation uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.messages
     set read_at = now()
   where conversation_id = p_conversation
     and sender_id <> (select auth.uid())
     and read_at is null
     and public.is_conversation_member(p_conversation)
$$;

create or replace function public.get_my_conversations()
returns table (
  id uuid, other_id uuid, other_name text, other_role public.user_role,
  last_message text, last_message_at timestamptz, unread_count bigint, linked boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select c.id,
         o.id, o.display_name, o.role,
         (select m.body from public.messages m where m.conversation_id = c.id order by m.created_at desc limit 1),
         c.last_message_at,
         (select count(*) from public.messages m
           where m.conversation_id = c.id and m.sender_id <> (select auth.uid()) and m.read_at is null),
         exists (select 1 from public.patient_links l
                  where l.patient_id = c.patient_id and l.nutritionist_id = c.nutritionist_id and l.status = 'active')
    from public.conversations c
    join public.profiles o on o.id = case when c.patient_id = (select auth.uid()) then c.nutritionist_id else c.patient_id end
   where (select auth.uid()) in (c.patient_id, c.nutritionist_id)
   order by c.last_message_at desc
$$;

-- Realtime per i messaggi
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables
                      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'messages') then
    alter publication supabase_realtime add table public.messages;
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- Permessi
-- ---------------------------------------------------------------------
do $$
declare
  v_fn regprocedure;
begin
  for v_fn in
    select p.oid::regprocedure
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('start_conversation', 'send_message', 'send_invitation_message',
                         'mark_conversation_read', 'get_my_conversations')
  loop
    execute format('revoke execute on function %s from public, anon', v_fn);
    execute format('grant execute on function %s to authenticated', v_fn);
  end loop;

  -- usata nella policy messages_select_member: deve restare eseguibile
  for v_fn in
    select p.oid::regprocedure
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'is_conversation_member'
  loop
    execute format('revoke execute on function %s from public, anon', v_fn);
    execute format('grant execute on function %s to authenticated', v_fn);
  end loop;
end;
$$;
