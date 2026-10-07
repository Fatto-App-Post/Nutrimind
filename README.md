# NutriMind — backend

NutriMind è un'app di food tracking macro-first con portale per
nutrizionisti, dietisti e personal trainer, e un catalogo alimentare
verificato.

Questo repository contiene il backend: schema del database, funzioni e
Edge Functions di Supabase. L'app Flutter sta in
[fattoapp-post/nutrimind-frontend](https://github.com/fattoapp-post/nutrimind-frontend).

## Da dove iniziare

- **[docs/CONTESTO_PROGETTO.md](docs/CONTESTO_PROGETTO.md)** — come è
  fatta l'app, valori ammessi e vincoli del database, migration, Edge
  Functions, configurazione.
- **[docs/PROSSIMI_PASSI.md](docs/PROSSIMI_PASSI.md)** — cosa conviene
  fare adesso.

## Struttura

```
migrations/          schema iniziale (001-003b)
supabase/
  migrations/        funzioni e funzionalità successive (011-022)
  functions/         Edge Functions (Deno)
  verify_frontend_contract.sql   verifica che il DB sia allineato all'app
scripts/             controlli eseguiti dalla CI (SQL e funzioni)
docs/
```

## Controlli locali

```bash
npm install --no-save libpg-query@17 esbuild@0.25.0
node scripts/check-sql.mjs        # ogni .sql è sintatticamente valido
node scripts/check-functions.mjs  # ogni Edge Function è TypeScript valido
```

Sono gli stessi due controlli che esegue la CI. Non applicano niente al
database e non pubblicano niente.

## Ambienti

| | Project ref | Regione | Open Food Facts |
|---|---|---|---|
| DEV | `tcszsyzpvmsifclziujc` | eu-west-1 | `world.openfoodfacts.net` |
| PROD | `ynnlfxgehbtlneiknrfr` | eu-north-1 | `world.openfoodfacts.org` |

## Applicare le modifiche al database

Le migration si eseguono in ordine nel SQL Editor di Supabase, una per
volta: l'editor annulla l'intero script al primo errore. Quelle dalla 014
in poi si possono rieseguire senza conseguenze.

Dopo ogni migration conviene eseguire
`supabase/verify_frontend_contract.sql`: restituisce il numero di
controlli superati e il solo elenco dei problemi.

## Chiavi e secret

Nessuna chiave sta in questo repository. Le chiavi pubbliche
(URL e publishable key) si recuperano da Dashboard → Project Settings →
API; quelle segrete non vanno mai condivise né committate.

I secret delle Edge Functions (`FIREBASE_SERVICE_ACCOUNT`,
`RESEND_API_KEY`, `EMAIL_FROM`, gli eventuali `OFF_*`) si configurano
dalla dashboard, in Edge Functions → Secrets.

> **Da fare:** le secret key di DEV e PROD sono state pubblicate in
> chiaro in questo repository, che è pubblico. Anche se rimosse dal
> codice restano nella cronologia git: vanno rigenerate dalla dashboard e
> aggiornate nei secret di GitHub Actions.

## Branching

- `main` — produzione
- `develop` — integrazione
- `claude_code` — ramo di lavoro corrente
