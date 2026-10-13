-- =====================================================================
-- NutriMind — 028 IMMAGINI DEGLI ALIMENTI
-- Rieseguibile.
--
-- `public.foods` non aveva nessuna colonna per le immagini. Il modello
-- Dart leggeva `image_front_url`, che però esiste soltanto nella
-- risposta di `search-off`: era quindi visibile solo mentre si guardava
-- il catalogo esterno e si perdeva appena il prodotto veniva importato.
-- (La `image_url` citata nei documenti è un'altra cosa: sta su
-- `suggested_meals` e riguarda le ricette.)
--
-- Due colonne e non una, perché servono due misure diverse e scaricare
-- la foto grande per disegnare una riga di elenco è uno spreco su rete
-- mobile:
--
--   * `image_thumb_url`  — la piccola, per gli elenchi e la ricerca;
--   * `image_url`        — quella grande, per la scheda del prodotto.
--
-- Non si copiano i file: si conserva l'indirizzo delle immagini di Open
-- Food Facts, che le serve già da sola. Gli utenti non possono
-- aggiungere immagini agli alimenti — l'unico posto dove si carica un
-- file sono le proprie ricette.
--
-- Nessuna RPC va aggiornata: `search_foods`, `get_food` e
-- `get_food_by_barcode` restituiscono `setof public.foods`, quindi le
-- colonne nuove escono da sole.
-- =====================================================================

alter table public.foods
  add column if not exists image_url       text,
  add column if not exists image_thumb_url text;

comment on column public.foods.image_url is
  'Indirizzo dell''immagine grande del prodotto (Open Food Facts). Per la scheda.';
comment on column public.foods.image_thumb_url is
  'Indirizzo dell''immagine piccola. Per gli elenchi e la ricerca: non scaricare la grande per una riga.';

-- Solo indirizzi cifrati: un'immagine servita in chiaro su una pagina
-- https viene bloccata dal browser, quindi non si vedrebbe comunque.
do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.foods'::regclass and conname = 'foods_image_urls_https'
  ) then
    alter table public.foods add constraint foods_image_urls_https check (
      (image_url is null or image_url like 'https://%') and
      (image_thumb_url is null or image_thumb_url like 'https://%')
    );
  end if;
end;
$$;
