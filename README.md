# Nutrimind Backend

Nutrimind è un'app di food tracking macro-first con portale nutrizionista e database alimentare verificato.

## Stack

- **Backend**: C# .NET 8, ASP.NET Core Minimal API
- **Database**: PostgreSQL su Supabase
  - Sviluppo: `Nutrimind - dev`
  - Produzione: `Nutrimind - prod`
- **Fonte esterna**: Open Food Facts API
- **Frontend**: Flutter (app mobile)

## Struttura soluzione

- `src/Nutrimind.Api` – API HTTP, endpoint, configurazione
- `src/Nutrimind.Application` – Servizi, DTO, mapping, regole di business
- `src/Nutrimind.Domain` – Modelli, value object, interfacce repository
- `src/Nutrimind.Infrastructure.Supabase` – Repository, migrazioni, client Supabase
- `src/Nutrimind.Infrastructure.OpenFoodFacts` – Client OFF, mapper, policy di cache
- `tests/Nutrimind.Tests.Unit` – Test unitari
- `tests/Nutrimind.Tests.Integration` – Test di integrazione (API, DB, OFF)

## Configurazione multi-ambiente

Il backend supporta due configurazioni distinte:

- **Development** (`appsettings.Development.json`): punta a `Nutrimind - dev`.
- **Production** (`appsettings.Production.json`): punta a `Nutrimind - prod`.

Per usare una configurazione specifica:

```bash
# Sviluppo
dotnet run --project src/Nutrimind.Api --environment Development

# Produzione (locale, per test)
dotnet run --project src/Nutrimind.Api --environment Production
```

In produzione reale, le chiavi Supabase vanno impostate come segreti nel servizio di hosting (es. Azure App Service, AWS ECS, ecc.).

## Documentazione

- [Architettura](docs/architecture.md)
- [Database e migrazioni](docs/database.md)
- [Integrazione Open Food Facts](docs/off-integration.md)
- [Piano di test BE e Data](docs/testing-be-data.md)
- [Integrazione Frontend](docs/frontend-integration.md)
- [Migrazioni SQL](migrations/)

## Branching

- `main` – produzione (punta a `Nutrimind - prod`)
- `develop` – integrazione (punta a `Nutrimind - dev`)
- `feature/*` – funzionalità specifiche (sviluppate su `dev`)

## Primi passi

1. Clona la repository.
2. Configura `appsettings.Development.json` con le chiavi di `Nutrimind - dev`.
3. Esegui `dotnet build`.
4. Esegui i test: `dotnet test`.
5. Avvia l'API: `dotnet run --project src/Nutrimind.Api`.

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
