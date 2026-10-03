# Nutrimind Backend

Nutrimind è un'app di food tracking macro-first con portale nutrizionista e database alimentare verificato.

## Stack

- **Backend**: C# .NET 8, ASP.NET Core Minimal API
- **Database**: PostgreSQL su Supabase
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
