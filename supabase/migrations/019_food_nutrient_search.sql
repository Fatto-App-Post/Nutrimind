-- =====================================================================
-- NutriMind — 019 RICERCA ALIMENTI PER VALORI NUTRIZIONALI
-- Rieseguibile.
--
-- search_foods accetta filtri su proteine, carboidrati, grassi e calorie
-- (per 100 g) e un ordinamento, così si può cercare per esempio "oltre
-- 50 g di proteine e meno di 10 g di grassi".
--
-- La vecchia firma (p_query, p_limit) viene eliminata: due overload
-- renderebbero ambigua la chiamata da PostgREST. Il testo diventa
-- opzionale, perché con i soli filtri si può cercare senza digitare nulla.
-- =====================================================================

drop function if exists public.search_foods(text, int);
drop function if exists public.search_foods(text, integer);

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
language plpgsql
stable
security definer
set search_path = 'public'
as $$
declare
  v_text    text := nullif(trim(coalesce(p_query, '')), '');
  v_pattern text := '%' || replace(replace(coalesce(v_text, ''), '%', '\%'), '_', '\_') || '%';
  v_has_filters boolean := coalesce(p_min_protein, p_max_protein, p_min_carbs, p_max_carbs,
                                    p_min_fat, p_max_fat, p_min_kcal, p_max_kcal) is not null;
begin
  -- Senza testo né filtri non si restituisce l'intero catalogo
  if v_text is null and not v_has_filters then
    return;
  end if;

  return query
  select f.*
    from public.foods f
   where f.is_active
     and f.verification <> 'rejected'
     and (v_text is null
          or f.name_search ilike v_pattern
          or f.name ilike v_pattern
          or f.brand ilike v_pattern
          or f.barcode = v_text)
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
   limit least(greatest(coalesce(p_limit, 20), 1), 100);

  -- Barcode non in catalogo: import da Open Food Facts (solo ricerca
  -- testuale pura, i filtri non si applicano a un singolo prodotto)
  if not found and not v_has_filters and v_text ~ '^[0-9]{8,14}$' then
    return query
    select f.* from public.openfoodfacts_search_and_cache(v_text) f;
  end if;
end;
$$;

-- Indici per i filtri sui macro (il catalogo cresce con gli import OFF)
create index if not exists foods_protein_idx on public.foods (protein_g) where is_active;
create index if not exists foods_carbs_idx   on public.foods (carbs_g)   where is_active;
create index if not exists foods_fat_idx     on public.foods (fat_g)     where is_active;
create index if not exists foods_kcal_idx    on public.foods (kcal)      where is_active;

do $$
declare
  v_fn regprocedure;
begin
  for v_fn in
    select p.oid::regprocedure
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'search_foods'
  loop
    execute format('revoke execute on function %s from public, anon', v_fn);
    execute format('grant execute on function %s to authenticated', v_fn);
  end loop;
end;
$$;
