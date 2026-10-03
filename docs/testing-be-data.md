# Piano di test BE e Data

## Obiettivo

Validare backend e data layer dopo l'applicazione delle migrazioni e l'implementazione delle API.

## Aree di test

- **Migrazioni**: fresh install, re-run, rollback, RLS coverage.
- **Schema alimentare**: upsert OFF, barcode, nutrienti, ingredienti, tag.
- **Integrazione OFF**: search, dettaglio, not found, rate limit, timeout.
- **API backend**: ricerca locale, fallback OFF, cache, refresh.
- **Diario**: calcolo macro, input malevoli, snapshot storico.
- **Sicurezza**: RLS, consensi, audit.

## Esecuzione

- Test unitari su Application e Infrastructure.
- Test di integrazione con Supabase dev e OFF staging.
- Smoke test pre-rilascio su ambiente dev.
