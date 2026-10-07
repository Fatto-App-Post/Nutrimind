-- =====================================================================
-- NutriMind — 020 RIMUOVE IL FALLBACK A UNA FUNZIONE INESISTENTE
-- Rieseguibile.
--
-- get_food_by_barcode e search_foods chiamavano
-- public.openfoodfacts_search_and_cache(), che nel database non esiste
-- (la 012_off_functions.sql non è mai stata applicata, e non va
-- applicata: faceva una chiamata HTTP sincrona da Postgres).
--
-- Il corpo di una funzione plpgsql non viene verificato alla creazione,
-- quindi l'errore compariva solo a runtime: cercando un barcode non in
-- catalogo si otteneva "function does not exist" (42883) invece di un
-- risultato vuoto, e il client non riusciva nemmeno a tentare l'import.
--
-- L'import da Open Food Facts resta compito della Edge Function
-- `import-off-barcode`, chiamata dall'app quando il catalogo locale non
-- ha il prodotto.
-- =====================================================================

create or replace function public.get_food_by_barcode(p_barcode text)
returns setof public.foods
language sql
stable
security definer
set search_path = 'public'
as $$
  select f.*
    from public.foods f
   where f.barcode = p_barcode
     and f.is_active
     and f.verification <> 'rejected'
$$;

create or replace function public.search_foods(
  p_query text default null,
  p_limit int default 20,
  p_min_protein numeric default null,
  p_max_protein numeric default null,
  p_min_carbs numeric default null,
  p_max_carbs numeric default null,
  p_min_fat numeric default null,
  p_max_fat numeric default null,
  p_min_kcal numeric default null,
  p_max_kcal numeric default null,
  p_sort text default null
)
returns setof public.foods
language sql
stable
security definer
set search_path = 'public'
as $$
  with params as (
    select nullif(trim(coalesce(p_query, '')), '') as text_q,
           coalesce(p_min_protein, p_max_protein, p_min_carbs, p_max_carbs,
                    p_min_fat, p_max_fat, p_min_kcal, p_max_kcal) is not null as has_filters
  )
  select f.*
    from public.foods f, params p
   where (p.text_q is not null or p.has_filters)   -- né testo né filtri: nessun risultato
     and f.is_active
     and f.verification <> 'rejected'
     and (p.text_q is null
          or f.name_search ilike '%' || replace(replace(p.text_q, '%', '\%'), '_', '\_') || '%'
          or f.name        ilike '%' || replace(replace(p.text_q, '%', '\%'), '_', '\_') || '%'
          or f.brand       ilike '%' || replace(replace(p.text_q, '%', '\%'), '_', '\_') || '%'
          or f.barcode = p.text_q)
     and (p_min_protein is null or f.protein_g >= p_min_protein)
     and (p_max_protein is null or f.protein_g <= p_max_protein)
     and (p_min_carbs   is null or f.carbs_g   >= p_min_carbs)
     and (p_max_carbs   is null or f.carbs_g   <= p_max_carbs)
     and (p_min_fat     is null or f.fat_g     >= p_min_fat)
     and (p_max_fat     is null or f.fat_g     <= p_max_fat)
     and (p_min_kcal    is null or f.kcal      >= p_min_kcal)
     and (p_max_kcal    is null or f.kcal      <= p_max_kcal)
   order by
     case when p_sort = 'protein_desc' then f.protein_g end desc nulls last,
     case when p_sort = 'carbs_asc'    then f.carbs_g   end asc  nulls last,
     case when p_sort = 'fat_asc'      then f.fat_g     end asc  nulls last,
     case when p_sort = 'kcal_asc'     then f.kcal      end asc  nulls last,
     case when p_sort = 'kcal_desc'    then f.kcal      end desc nulls last,
     f.trust_level desc, f.name
   limit least(greatest(coalesce(p_limit, 20), 1), 100)
$$;

do $$
declare
  v_fn regprocedure;
begin
  for v_fn in
    select p.oid::regprocedure
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname in ('search_foods', 'get_food_by_barcode')
  loop
    execute format('revoke execute on function %s from public, anon', v_fn);
    execute format('grant execute on function %s to authenticated', v_fn);
  end loop;
end;
$$;
