-- =====================================================================
-- NutriMind — 022 RICERCA ALIMENTI: TOLLERA GLI ERRORI DI BATTITURA
-- Rieseguibile.
--
-- La ricerca testuale faceva solo `ilike '%testo%'`: "mozarella" non
-- trovava "mozzarella", e i risultati uscivano ordinati per livello di
-- affidabilità e nome, quindi il prodotto più pertinente poteva finire
-- in fondo.
--
-- Sul database c'è già tutto il necessario e non era usato:
--   * l'estensione pg_trgm;
--   * l'indice GIN `foods_name_trgm_idx` su `name_search`, inutile
--     finché la funzione non usa gli operatori di somiglianza.
--
-- Cosa cambia:
--   * oltre alla sottostringa si cerca per somiglianza (`<%` e `%`), così
--     un errore di battitura trova comunque il prodotto;
--   * l'ordine diventa: codice a barre esatto, poi l'eventuale
--     ordinamento scelto dall'utente, poi chi comincia col testo
--     cercato, poi la somiglianza, e solo alla fine affidabilità e nome.
--
-- `name_search` lo riempie il trigger `foods_before_write` come
-- `lower(unaccent(nome || ' ' || marca))`: il testo cercato va
-- normalizzato allo stesso modo, altrimenti "Però" non troverebbe "pero".
--
-- La firma non cambia: il frontend non va aggiornato.
-- =====================================================================

create or replace function public.search_foods(
  p_query       text    default null,
  p_limit       integer default 20,
  p_min_protein numeric default null,
  p_max_protein numeric default null,
  p_min_carbs   numeric default null,
  p_max_carbs   numeric default null,
  p_min_fat     numeric default null,
  p_max_fat     numeric default null,
  p_min_kcal    numeric default null,
  p_max_kcal    numeric default null,
  p_sort        text    default null
)
returns setof public.foods
language sql
stable
security definer
-- search_path resta 'public' come nelle altre funzioni: tutto ciò che
-- sta in `extensions` (unaccent, similarity, gli operatori di pg_trgm) è
-- richiamato con lo schema esplicito, così la funzione non dipende da
-- come è configurata la sessione.
set search_path = 'public'
as $$
  with params as (
    select q.text_q,
           lower(extensions.unaccent('extensions.unaccent'::regdictionary, q.text_q)) as norm_q,
           coalesce(p_min_protein, p_max_protein, p_min_carbs, p_max_carbs,
                    p_min_fat, p_max_fat, p_min_kcal, p_max_kcal) is not null as has_filters
      from (select nullif(trim(coalesce(p_query, '')), '') as text_q) q
  ),
  pattern as (
    select p.*,
           replace(replace(replace(p.norm_q, '\', '\\'), '%', '\%'), '_', '\_') as like_q
      from params p
  )
  select f.*
    from public.foods f, pattern p
   where (p.text_q is not null or p.has_filters)   -- né testo né filtri: nessun risultato
     and f.is_active
     and f.verification <> 'rejected'
     and (p.norm_q is null
          or f.barcode = p.text_q
          or f.name_search like '%' || p.like_q || '%'
          -- somiglianza complessiva: l'operatore usa l'indice GIN
          or f.name_search operator(extensions.%) p.norm_q
          -- somiglianza con una singola parola del nome, con soglia
          -- esplicita: non dipende dalla configurazione della sessione
          -- ("mozarela" trova "mozzarella di bufala")
          or extensions.word_similarity(p.norm_q, f.name_search) > 0.45)
     and (p_min_protein is null or f.protein_g >= p_min_protein)
     and (p_max_protein is null or f.protein_g <= p_max_protein)
     and (p_min_carbs   is null or f.carbs_g   >= p_min_carbs)
     and (p_max_carbs   is null or f.carbs_g   <= p_max_carbs)
     and (p_min_fat     is null or f.fat_g     >= p_min_fat)
     and (p_max_fat     is null or f.fat_g     <= p_max_fat)
     and (p_min_kcal    is null or f.kcal      >= p_min_kcal)
     and (p_max_kcal    is null or f.kcal      <= p_max_kcal)
   order by
     -- 1. chi cerca un codice a barre vuole quel prodotto
     case when p.text_q is not null and f.barcode = p.text_q then 0 else 1 end,
     -- 2. l'ordinamento scelto dall'utente, se c'è
     case when p_sort = 'protein_desc' then f.protein_g end desc nulls last,
     case when p_sort = 'carbs_asc'    then f.carbs_g   end asc  nulls last,
     case when p_sort = 'fat_asc'      then f.fat_g     end asc  nulls last,
     case when p_sort = 'kcal_asc'     then f.kcal      end asc  nulls last,
     case when p_sort = 'kcal_desc'    then f.kcal      end desc nulls last,
     -- 3. chi comincia col testo cercato
     case when p.norm_q is not null and f.name_search like p.like_q || '%' then 0 else 1 end,
     -- 4. quanto somiglia (0 = identico)
     case when p.norm_q is null then 0
          else 1 - greatest(extensions.word_similarity(p.norm_q, f.name_search),
                            extensions.similarity(f.name_search, p.norm_q))
     end,
     f.trust_level desc, f.name
   limit least(greatest(coalesce(p_limit, 20), 1), 100)
$$;

revoke all on function public.search_foods(text, integer, numeric, numeric, numeric, numeric,
                                           numeric, numeric, numeric, numeric, text) from public, anon;
grant execute on function public.search_foods(text, integer, numeric, numeric, numeric, numeric,
                                              numeric, numeric, numeric, numeric, text) to authenticated;

-- Nota: la versione precedente cercava anche su `name` e su `brand` con
-- `ilike`. Erano condizioni ridondanti e non indicizzate: `name_search`
-- contiene già nome e marca, normalizzati senza accenti, ed è l'unica
-- colonna coperta dall'indice GIN. Nessun indice nuovo serve.
