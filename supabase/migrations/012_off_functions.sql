-- =====================================================================
-- NutriMind — 012 FUNZIONI PER OPENFOODFACTS
-- Funzioni per chiamare le Edge Functions
-- =====================================================================

-- Abilita http extension se non esiste
create extension if not exists http with schema extensions;

-- ---------------------------------------------------------------------
-- CHIAMATA EDGE FUNCTION PER CERCARE SU OFF E CACHE NEL DB
-- ---------------------------------------------------------------------
create or replace function public.openfoodfacts_search_and_cache(p_barcode text)
returns setof foods
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_response text;
  v_status int;
  v_content_type text;
  v_headers text;
  v_food_record record;
  v_json jsonb;
begin
  -- Chiama la Edge Function
  select
    content,
    status,
    content_type,
    headers
  into
    v_response,
    v_status,
    v_content_type,
    v_headers
  from extensions.http(
    'POST',
    'https://tcszsyzpvmsifclziujc.supabase.co/functions/v1/search-off',
    array[
      extensions.http_header('Content-Type', 'application/json'),
      extensions.http_header('apikey', current_setting('supabase.service_role_key'))
    ],
    'application/json',
    jsonb_build_object('barcode', p_barcode)::text
  );

  -- Se errore, ritorna vuoto
  if v_status <> 200 then
    return;
  end if;

  -- Parse JSON response
  v_json := v_response::jsonb;

  -- Se c'è un errore nella response
  if v_json ? 'error' then
    return;
  end if;

  -- Inserisci/aggiorna nel DB e ritorna
  insert into foods (
    name, brand, barcode, source, source_id,
    verification, kcal, protein_g, carbs_g, fat_g,
    image_front_url, nutriscore_grade, ecoscore_grade, nova_group,
    is_active, trust_level
  ) values (
    v_json->>'name',
    v_json->>'brand',
    p_barcode,
    v_json->>'source',
    v_json->>'source_id',
    v_json->>'verification',
    (v_json->>'kcal')::numeric,
    (v_json->>'protein_g')::numeric,
    (v_json->>'carbs_g')::numeric,
    (v_json->>'fat_g')::numeric,
    v_json->>'image_front_url',
    v_json->>'nutriscore_grade',
    v_json->>'ecoscore_grade',
    (v_json->>'nova_group')::int,
    true,
    1
  )
  on conflict (barcode) do update set
    name = excluded.name,
    brand = excluded.brand,
    kcal = excluded.kcal,
    protein_g = excluded.protein_g,
    carbs_g = excluded.carbs_g,
    fat_g = excluded.fat_g,
    image_front_url = excluded.image_front_url,
    nutriscore_grade = excluded.nutriscore_grade,
    ecoscore_grade = excluded.ecoscore_grade,
    nova_group = excluded.nova_group,
    updated_at = now()
  returning * into v_food_record;

  return next v_food_record;
end;
$$;

-- ---------------------------------------------------------------------
-- FUNZIONE DI RICERCA DIRETTA SU OFF (senza cache)
-- ---------------------------------------------------------------------
create or replace function public.openfoodfacts_search_direct(p_barcode text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_response text;
  v_status int;
begin
  select content, status
  into v_response, v_status
  from extensions.http(
    'POST',
    'https://tcszsyzpvmsifclziujc.supabase.co/functions/v1/search-off',
    array[
      extensions.http_header('Content-Type', 'application/json'),
      extensions.http_header('apikey', current_setting('supabase.service_role_key'))
    ],
    'application/json',
    jsonb_build_object('barcode', p_barcode)::text
  );

  if v_status = 200 then
    return v_response::jsonb;
  else
    return null;
  end if;
end;
$$;
