-- =====================================================================
-- NutriMind — 012 NUOVE FUNZIONI PER FUNZIONALITÀ AGGIUNTIVE
-- =====================================================================

-- COMMENTI NUTRIZIONISTA: CREA COMMENTO
create or replace function public.create_nutritionist_comment(
  p_patient_id uuid,
  p_comment_date date,
  p_body text,
  p_meal_slot public.meal_slot default null,
  p_diary_entry_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_comment_id uuid;
  v_user_id uuid := auth.uid();
  v_role public.user_role;
begin
  select role into v_role from public.profiles where id = v_user_id;
  
  if v_role <> 'nutritionist' and v_role <> 'admin' then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  
  if v_role = 'nutritionist' and not public.has_active_link(p_patient_id) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  
  insert into public.nutritionist_comments (
    patient_id, nutritionist_id, comment_date, meal_slot, diary_entry_id, body
  ) values (
    p_patient_id, v_user_id, p_comment_date, p_meal_slot, p_diary_entry_id, p_body
  )
  returning id into v_comment_id;
  
  insert into public.notifications (user_id, type, title, body, data)
  values (
    p_patient_id, 'nutritionist_comment',
    'Nuovo commento dal nutrizionista',
    'Hai ricevuto un nuovo commento per il giorno ' || to_char(p_comment_date, 'DD/MM/YYYY'),
    jsonb_build_object('comment_id', v_comment_id, 'comment_date', p_comment_date, 'meal_slot', p_meal_slot)
  );
  
  return v_comment_id;
end;
$$;

-- COMMENTI NUTRIZIONISTA: OTTIENI COMMENTI PER PAZIENTE
create or replace function public.get_nutritionist_comments(
  p_patient_id uuid,
  p_from date default null,
  p_to date default null
)
returns setof public.nutritionist_comments
language sql
security definer
set search_path = 'public'
as $$
  select nc.*
  from public.nutritionist_comments nc
  where nc.patient_id = p_patient_id
    and (p_from is null or nc.comment_date >= p_from)
    and (p_to is null or nc.comment_date <= p_to)
  order by nc.comment_date desc, nc.created_at desc;
$$;

-- COMMENTI NUTRIZIONISTA: AGGIORNA COMMENTO
create or replace function public.update_nutritionist_comment(
  p_comment_id uuid,
  p_body text
)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_user_id uuid := auth.uid();
  v_nutritionist_id uuid;
begin
  select nutritionist_id into v_nutritionist_id
  from public.nutritionist_comments
  where id = p_comment_id;
  
  if v_nutritionist_id <> v_user_id then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  
  update public.nutritionist_comments
  set body = p_body, edited_at = now()
  where id = p_comment_id;
end;
$$;

-- COMMENTI NUTRIZIONISTA: SEGNA COME LETTO
create or replace function public.mark_comment_read(p_comment_id uuid)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  update public.nutritionist_comments
  set read_at = now()
  where id = p_comment_id and patient_id = auth.uid();
end;
$$;

-- COMMENTI NUTRIZIONISTA: ELIMINA COMMENTO
create or replace function public.delete_nutritionist_comment(p_comment_id uuid)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_user_id uuid := auth.uid();
  v_role public.user_role;
  v_nutritionist_id uuid;
begin
  select role into v_role from public.profiles where id = v_user_id;
  select nutritionist_id into v_nutritionist_id
  from public.nutritionist_comments
  where id = p_comment_id;
  
  if v_role <> 'admin' and v_nutritionist_id <> v_user_id then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  
  delete from public.nutritionist_comments
  where id = p_comment_id;
end;
$$;

-- PORZIONI CIBO: OTTIENI PORZIONI PER ALIMENTO
create or replace function public.get_food_portions(p_food_id uuid)
returns setof public.food_portions
language sql
security definer
set search_path = 'public'
as $$
  select fp.*
  from public.food_portions fp
  where fp.food_id = p_food_id
  order by fp.grams;
$$;

-- PORZIONI CIBO: CREA PORZIONE
create or replace function public.create_food_portion(
  p_food_id uuid,
  p_label text,
  p_grams numeric
)
returns uuid
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_portion_id uuid;
  v_user_id uuid := auth.uid();
  v_role public.user_role;
begin
  select role into v_role from public.profiles where id = v_user_id;
  
  if v_role not in ('nutritionist', 'admin') then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  
  if v_role = 'nutritionist' and not exists (
    select 1 from public.profiles where id = v_user_id and professional_verified = true
  ) then
    raise exception 'nutritionist_not_verified' using errcode = '42501';
  end if;
  
  if not exists (select 1 from public.foods where id = p_food_id) then
    raise exception 'food_not_found' using errcode = 'P0002';
  end if;
  
  insert into public.food_portions (food_id, label, grams)
  values (p_food_id, p_label, p_grams)
  returning id into v_portion_id;
  
  return v_portion_id;
end;
$$;

-- PORZIONI CIBO: AGGIORNA PORZIONE
create or replace function public.update_food_portion(
  p_portion_id uuid,
  p_label text default null,
  p_grams numeric default null
)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_user_id uuid := auth.uid();
  v_role public.user_role;
begin
  select role into v_role from public.profiles where id = v_user_id;
  
  if v_role <> 'admin' then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  
  update public.food_portions
  set
    label = coalesce(p_label, label),
    grams = coalesce(p_grams, grams),
    created_at = now()
  where id = p_portion_id;
end;
$$;

-- PORZIONI CIBO: ELIMINA PORZIONE
create or replace function public.delete_food_portion(p_portion_id uuid)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_user_id uuid := auth.uid();
  v_role public.user_role;
begin
  select role into v_role from public.profiles where id = v_user_id;
  
  if v_role <> 'admin' then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  
  delete from public.food_portions
  where id = p_portion_id;
end;
$$;

-- DIARIO: OTTIENI COMMENTI CON ENTRATE
create or replace function public.get_diary_with_comments(
  p_patient_id uuid,
  p_from date,
  p_to date
)
returns table (
  entry_date date,
  meal_slot public.meal_slot,
  entries jsonb,
  comments jsonb
)
language sql
security definer
set search_path = 'public'
as $$
  with diary_entries_agg as (
    select
      de.entry_date,
      de.meal_slot,
      jsonb_agg(
        jsonb_build_object(
          'id', de.id,
          'food_name', coalesce(de.custom_name, f.name),
          'grams', de.grams,
          'kcal', de.kcal,
          'protein_g', de.protein_g,
          'carbs_g', de.carbs_g,
          'fat_g', de.fat_g
        )
        order by de.created_at
      ) as entries
    from public.diary_entries de
    left join public.foods f on f.id = de.food_id
    where de.patient_id = p_patient_id
      and de.entry_date between p_from and p_to
    group by de.entry_date, de.meal_slot
  ),
  comments_agg as (
    select
      nc.comment_date as entry_date,
      nc.meal_slot,
      jsonb_agg(
        jsonb_build_object(
          'id', nc.id,
          'body', nc.body,
          'nutritionist_id', nc.nutritionist_id,
          'created_at', nc.created_at,
          'edited_at', nc.edited_at,
          'read_at', nc.read_at
        )
        order by nc.created_at
      ) as comments
    from public.nutritionist_comments nc
    where nc.patient_id = p_patient_id
      and nc.comment_date between p_from and p_to
    group by nc.comment_date, nc.meal_slot
  )
  select
    coalesce(d.entry_date, c.entry_date) as entry_date,
    coalesce(d.meal_slot, c.meal_slot) as meal_slot,
    coalesce(d.entries, '[]'::jsonb) as entries,
    coalesce(c.comments, '[]'::jsonb) as comments
  from diary_entries_agg d
  full outer join comments_agg c
    on d.entry_date = c.entry_date and d.meal_slot = c.meal_slot
  order by entry_date desc, meal_slot;
$$;
