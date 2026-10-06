# Integrazione Open Food Facts

## Endpoint utilizzati

- `GET /api/v2/product/{barcode}` – dettaglio prodotto.
- `GET /api/v2/search?...` – ricerca (usata solo come scrematura).

## Flusso backend

1. Il client richiede un alimento per barcode.
2. Il backend chiama `get_or_plan_off_sync(barcode)`.
3. Se l'alimento esiste in `foods`, lo restituisce.
4. Altrimenti:
   - crea un record in `food_off_sync_log`;
   - una Edge Function (o job) legge i record `pending`;
   - chiama OFF, normalizza il dato e inserisce in `foods`;
   - aggiorna lo stato del log.

## Campi salvati

Su `foods`:

- `generic_name`, `product_name_it`, `quantity_*`
- `image_front_url`, `image_nutrition_url`
- `nutriscore_grade`, `ecoscore_grade`, `ecoscore_score`, `nova_group`
- `off_raw`, `off_fetched_at`, `off_last_modified_at`

Il backend non espone mai direttamente il JSON OFF al client, ma solo DTO normalizzati.
