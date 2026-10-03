# Database Nutrimind

## Schema principale

- `profiles`, `patient_settings`, `nutritionist_details` – utenti e ruoli.
- `patient_links`, `consents`, `invitations` – collegamenti e consensi.
- `foods`, `food_portions`, `food_off_sync_log` – database alimentare + OFF.
- `macro_plans`, `macro_plan_targets` – piani nutrizionali.
- `diary_entries`, `favorite_foods`, `personal_meals` – diario e pasti personali.
- `suggested_meals`, `suggested_meal_items` – libreria pasti consigliati.
- `nutritionist_comments`, `notifications`, `device_tokens` – comunicazione.
- `legal_documents`, `terms_acceptances`, `audit_log` – compliance e audit.

## Integrazione OFF

- `foods.off_raw` conserva il payload completo da OFF.
- `food_off_sync_log` traccia le sincronizzazioni per barcode.
- La funzione `get_or_plan_off_sync(barcode)`:
  - restituisce l'alimento se esiste;
  - altrimenti crea un record di sync in `pending`.

Il backend C# userà questa funzione come punto di ingresso unico per "ottieni o sincronizza" un alimento da OFF.
