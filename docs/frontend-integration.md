# Integrazione Frontend (Flutter)

## Autenticazione

- Supabase Auth (email/password, OAuth).
- Token JWT inviato al backend come `Authorization: Bearer <token>`.

## Endpoint principali

- `GET /api/foods/search?q=...` – ricerca alimenti.
- `GET /api/foods/barcode/{barcode}` – dettaglio alimento.
- `POST /api/diary/entries` – registra pasto.
- `GET /api/plans/current?date=...` – piano corrente.
- `GET /api/patients/adherence?patientId=...&from=...&to=...` – aderenza.

## Gestione errori

- 400: validazione input.
- 401: sessione scaduta.
- 403: azione non consentita.
- 404: risorsa non trovata.
- 429: rate limit.
- 5xx: errore server.

## Cache locale

- Usare React Query / equivalente Flutter per cache di:
  - ricerca alimenti;
  - dettaglio barcode;
  - diario giornaliero;
  - piano corrente.
