# Linee guida per i contributori

## Branching

- `main` – codice di produzione (punta a `Nutrimind - prod`).
- `develop` – integrazione (punta a `Nutrimind - dev`).
- `feature/*` – nuove funzionalità, da mergiare su `develop`.
- `hotfix/*` – correzioni urgenti, da mergiare su `main` e `develop`.

## Configurazione locale

1. Copia `appsettings.Development.json` e inserisci le chiavi di `Nutrimind - dev`.
2. Per testare la configurazione di produzione, usa `appsettings.Production.json` con le chiavi di `Nutrimind - prod`.

## Test

- Esegui tutti i test prima di ogni commit: `dotnet test`.
- Aggiungi test unitari per nuova logica di business.
- Aggiungi test di integrazione per nuovi endpoint API.

## Commit

- Messaggi chiari e concisi, in italiano o inglese.
- Usa il prefisso `feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`.

## Sicurezza

- Non committare mai chiavi o segreti nel repo.
- Usa user-secrets o variabili ambiente per dati sensibili.
