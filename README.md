# Nutrimind Backend

Nutrimind è un'app di food tracking macro-first con portale nutrizionista e database alimentare verificato.

## Stack

- **Backend**: C# .NET 8, ASP.NET Core Minimal API
- **Database**: PostgreSQL su Supabase (progetto `Nutrimind - dev`)
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

## Documentazione

- [Architettura](docs/architecture.md)
- [Database e migrazioni](docs/database.md)
- [Integrazione Open Food Facts](docs/off-integration.md)
- [Piano di test BE e Data](docs/testing-be-data.md)
- [Integrazione Frontend](docs/frontend-integration.md)
- [Migrazioni SQL](migrations/)

## Configurazione locale

Usa .NET user-secrets o variabili ambiente:

```json
{
  "Supabase": {
    "Url": "https://xxxxx.supabase.co",
    "AnonKey": "eyJ...",
    "ServiceRoleKey": "eyJ..."
  },
  "OpenFoodFacts": {
    "BaseUri": "https://world.openfoodfacts.net",
    "Username": "off",
    "Password": "off",
    "UserAgent": "Nutrimind/0.1 (contact@example.com)"
  }
}
```

## Branching

- `main` – produzione
- `develop` – integrazione
- `feature/*` – funzionalità specifiche

## Primi passi

1. Clona la repository.
2. Configura i segreti locali.
3. Esegui `dotnet build`.
4. Esegui i test: `dotnet test`.
5. Avvia l'API: `dotnet run --project src/Nutrimind.Api`.

## Integrazione con Supabase

Il database di sviluppo è il progetto Supabase **Nutrimind - dev**.
Le migrazioni sono già state applicate manualmente tramite SQL Editor / CLI.
Per riferimento, gli script sono in `migrations/`.

## Integrazione con Open Food Facts

Il backend gestisce automaticamente:

- ricerca locale in `foods`;
- fallback su OFF se il prodotto non esiste;
- cache dei risultati in Supabase (`foods.off_raw`, `food_off_sync_log`).

La funzione SQL `get_or_plan_off_sync(barcode)` è il punto di ingresso unico per "ottieni o sincronizza" un alimento.
