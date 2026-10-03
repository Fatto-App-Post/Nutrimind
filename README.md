# Nutrimind Backend

Nutrimind è un'app di food tracking macro-first con portale nutrizionista e database alimentare verificato.

## Stack

- **Backend**: C# .NET 8, ASP.NET Core Minimal API
- **Database**: PostgreSQL su Supabase
  - **DEV**: `Nutrimind - dev` (`eu-west-1`)
  - **PROD**: `Nutrimind - prod` (`eu-north-1`)
- **Fonte esterna**: Open Food Facts API
  - **DEV**: `https://world.openfoodfacts.net`
  - **PROD**: `https://world.openfoodfacts.org`
- **Frontend**: Flutter (app mobile)

## Struttura soluzione

```
src/
  Nutrimind.Api/
  Nutrimind.Application/
  Nutrimind.Domain/
  Nutrimind.Infrastructure.Supabase/
  Nutrimind.Infrastructure.OpenFoodFacts/
tests/
  Nutrimind.Tests.Unit/
  Nutrimind.Tests.Integration/
migrations/
docs/
```

## Setup locale

**Guida completa**: [SETUP_LOCALE.md](SETUP_LOCALE.md)

In breve:

1. Clona: `git clone https://github.com/Fatto-App-Post/Nutrimind.git && cd Nutrimind`
2. Configura i secret Supabase (vedi sotto).
3. `dotnet restore`
4. `dotnet test`
5. `dotnet run --project src/Nutrimind.Api`

## Configurazione secret (GitHub Actions)

Il workflow CI usa **8 secret** già configurati nel repo:

### Secret per DEV

| Nome | Valore |
|------|--------|
| `SUPABASE_DEV_URL` | `https://tcszsyzpvmsifclziujc.supabase.co` |
| `SUPABASE_DEV_PUBLISHABLE_KEY` | `sb_publishable_LjiP_fxK-yrZrD_8IRW9zw_Qv9Uq_cXU` |
| `SUPABASE_DEV_SECRET_KEY` | `sb_secret_4kZzc_2-HNU-Tthf56zhbw_nBdIAt0T` |
| `SUPABASE_DEV_JWKS_URL` | `https://tcszsyzpvmsifclziujc.supabase.co/auth/v1/.well-known/jwks.json` |

### Secret per PROD

| Nome | Valore |
|------|--------|
| `SUPABASE_PROD_URL` | `https://ynnlfxgehbtlneiknrfr.supabase.co` |
| `SUPABASE_PROD_PUBLISHABLE_KEY` | `sb_publishable_Dkv2o2Sl9rkpA0ZeDRgwIA_5QALd4u3` |
| `SUPABASE_PROD_SECRET_KEY` | `sb_secret_XT0GMUvpHmPWjgl60PLJfg_CENufVxY` |
| `SUPABASE_PROD_JWKS_URL` | `https://ynnlfxgehbtlneiknrfr.supabase.co/auth/v1/.well-known/jwks.json` |

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

Il progetto usa **GitHub Actions**:

- Push su `main` o `develop` → build + test (DEV + PROD).
- PR verso `develop` → build + test (DEV).

## Endpoint principali

- `GET /health` – health check (mostra ambiente e configurazione)
- `GET /api/foods/search?q=...&limit=...` – ricerca alimenti
- `GET /api/foods/barcode/{barcode}` – dettaglio alimento (fallback automatico su OFF)

## Alimenti seed (DEV)

Il DB di dev include già:

- Nutella (3017620422003)
- Coca-Cola (5449000000996)
- Doritos Nacho Cheese (5000159484126)
- Milka Chocolate (7622210316769)
- Biscotti Nutella (8000500310427)

## Linee guida

Vedi [CONTRIBUTING.md](CONTRIBUTING.md).
