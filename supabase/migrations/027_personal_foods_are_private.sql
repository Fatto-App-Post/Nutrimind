-- =====================================================================
-- NutriMind — 027 GLI ALIMENTI PERSONALI SONO PRIVATI
-- Rieseguibile.
--
-- Trovato controllando una per una le RPC esposte a chi è autenticato.
-- Sono 68, tutte `security definer`: ognuna è una porta sul database e
-- deve chiudersi da sola, perché `security definer` scavalca la
-- protezione per riga. Cinque non facevano nessun controllo. Tre vanno
-- bene (`get_my_patients` delega a `my_patients_overview`, che controlla
-- ruolo e identità; `get_food` e `get_food_portions` si raggiungono solo
-- con l'UUID esatto). Due no, e sono queste.
--
-- `search_foods` e `get_food_by_barcode` leggevano `public.foods` senza
-- distinguere la provenienza. Ma in quella tabella convivono due cose
-- diverse: il **catalogo**, che è di tutti (usda, crea, openfoodfacts,
-- professional), e gli **alimenti personali** con `source = 'user'`,
-- che una persona scrive per sé quando un prodotto non esiste — di
-- solito copiandolo dalla confezione, a volte con un nome che dice
-- qualcosa di sé ("frullato della dieta", "pranzo dell'ospedale").
--
-- Due conseguenze, entrambe reali:
--
-- 1. **Privacy.** Cercando una parola qualsiasi si ottenevano gli
--    alimenti personali di chiunque, con il nome che l'autore ha
--    scelto. Nel caso del codice a barre non serviva nemmeno indovinare
--    un UUID: i codici a barre sono pubblici, stanno stampati sulle
--    confezioni.
--
-- 2. **Qualità del dato.** `get_food_by_barcode` non aveva né ordine né
--    limite e il client prende il primo risultato. Appena qualcuno
--    inserisce un alimento personale con un codice a barre vero, quella
--    riga scritta a mano diventa la risposta di *tutti* per quel
--    prodotto, al posto della voce verificata. Il percorso
--    "Inseriscilo tu" dello scanner crea esattamente alimenti personali
--    con il codice a barre appena inquadrato, quindi era questione di
--    tempo.
--
-- La regola nuova: un alimento con `source = 'user'` lo vede solo chi
-- l'ha scritto, **finché resta non verificato**. Appena un
-- professionista o un amministratore lo verifica diventa catalogo e
-- vale per tutti: è esattamente lo scopo della coda di revisione
-- introdotta dalla 025, e senza questa eccezione verificare un alimento
-- non avrebbe nessun effetto visibile. Gli alimenti `rejected` erano
-- già esclusi per tutti.
--
-- La coda di verifica (`get_foods_to_review`) ha una funzione sua e
-- continua a vedere anche i non verificati, altrimenti nessuno potrebbe
-- promuoverli.
--
-- Questa eccezione è venuta fuori guardando i risultati veri a schermo:
-- "Pane di segale della nonna" era stato scritto da un paziente e poi
-- verificato dall'amministratore, e con la prima versione della regola
-- sarebbe tornato privato.
--
-- `get_food(p_id)` resta volutamente aperta: serve al paziente per
-- aprire un alimento che il nutrizionista gli ha consigliato
-- (`patient_suggestions`), e chiuderla col solo criterio del
-- proprietario romperebbe "Consigliati per te". Per restringerla serve
-- una regola a tre vie — mio, di catalogo, oppure consigliato a me — ed
-- è un lavoro a parte.
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
     -- Un alimento personale risponde solo al suo autore, finché
     -- qualcuno non lo verifica: allora è catalogo e vale per tutti.
     and (f.source <> 'user'
          or f.verification = 'verified'
          or f.created_by = (select auth.uid()))
   -- Ordine e limite: il client prende il primo risultato, quindi deve
   -- essere il più affidabile. `trust_level` è generata da `source` e
   -- `verification`, cioè esattamente da dove viene il dato.
   order by f.trust_level desc, f.created_at
   limit 5
$$;

revoke all on function public.get_food_by_barcode(text) from public, anon;
grant execute on function public.get_food_by_barcode(text) to authenticated;

-- ---------------------------------------------------------------------
-- search_foods: identica alla 022, con la sola riga sulla provenienza.
-- ---------------------------------------------------------------------

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
     -- Gli alimenti personali di qualcun altro non compaiono, a meno
     -- che non siano stati verificati (vedi la nota in testa).
     and (f.source <> 'user'
          or f.verification = 'verified'
          or f.created_by = (select auth.uid()))
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
