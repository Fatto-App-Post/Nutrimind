# Nutrimind Backend

Nutrimind è un'app di food tracking macro-first con portale nutrizionista e database alimentare verificato.

## Stack

- **Backend**: C# .NET 8, ASP.NET Core Minimal API
- **Database**: PostgreSQL su Supabase
  - Sviluppo: `Nutrimind - dev` (`eu-west-1`)
  - Produzione: `Nutrimind - prod` (`eu-north-1`)
- **Fonte esterna**: Open Food Facts API
  - DEV: `https://world.openfoodfacts.net`
  - PROD: `https://world.openfoodfacts.org`
- **Frontend**: Flutter (app mobile)

## Struttura soluzione

- `src/Nutrimind.Api` – API HTTP, endpoint, configurazione
- `src/Nutrimind.Application` – Servizi, DTO, mapping, regole di business
- `src/Nutrimind.Domain` – Modelli, value object, interfacce repository
- `src/Nutrimind.Infrastructure.Supabase` – Repository, migrazioni, client Supabase
- `src/Nutrimind.Infrastructure.OpenFoodFacts` – Client OFF, mapper, policy di cache
- `tests/Nutrimind.Tests.Unit` – Test unitari
- `tests/Nutrimind.Tests.Integration` – Test di integrazione (API, DB, OFF)

## Setup locale

**Guida completa**: [SETUP_LOCALE.md](SETUP_LOCALE.md)

In breve:

1. Clona il repo: `git clone https://github.com/Fatto-App-Post/Nutrimind.git`
2. Configura `appsettings.Development.json` con le chiavi di `Nutrimind - dev`.
3. Esegui `dotnet restore`.
4. Esegui i test: `dotnet test`.
5. Avvia l'API: `dotnet run --project src/Nutrimind.Api`.

## Documentazione

- [Setup locale e test](SETUP_LOCALE.md)
- [Architettura](docs/architecture.md)
- [Database e migrazioni](docs/database.md)
- [Integrazione Open Food Facts](docs/off-integration.md)
- [Sicurezza e ambienti](docs/security.md)
- [Piano di test BE e Data](docs/testing-be-data.md)
- [Integrazione Frontend](docs/frontend-integration.md)
- [Migrazioni SQL](migrations/)

## Branching

- `main` – produzione (punta a `Nutrimind - prod`)
- `develop` – integrazione (punta a `Nutrimind - dev`)
- `feature/*` – funzionalità specifiche (sviluppate su `dev`)

## CI/CD

Il progetto usa **GitHub Actions** per build e test automatici:

- Push su `main` o `develop` → build + test.
- PR verso `develop` → build + test.

Configura i secret nel repo:
- `SUPABASE_DEV_URL`
- `SUPABASE_DEV_SERVICE_KEY`

## Endpoint principali

- `GET /health` – health check
- `GET /api/foods/search?q=...&limit=...` – ricerca alimenti
- `GET /api/foods/barcode/{barcode}` – dettaglio alimento (con fallback automatico su OFF)

## Integrazione con Open Food Facts

Il backend gestisce automaticamente:

- ricerca locale in `foods`;
- fallback su OFF se il prodotto non esiste;
- cache dei risultati in Supabase (`foods.off_raw`, `food_off_sync_log`).

La funzione SQL `get_or_plan_off_sync(barcode)` è il punto di ingresso unico per "ottieni o sincronizza" un alimento.

## Alimenti seed (DEV)

Il DB di dev include già alcuni alimenti da OFF:

- Nutella (3017620422003)
- Coca-Cola (5449000000996)
- Doritos Nacho Cheese (5000159484126)
- Milka Chocolate (7622210316769)
- Biscotti Nutella (8000500310427)

## Linee guida per i contributori

Vedi [CONTRIBUTING.md](CONTRIBUTING.md).
