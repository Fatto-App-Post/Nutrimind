# Setup Locale e Test

## Prerequisiti

- **.NET 8 SDK** ([download](https://dotnet.microsoft.com/download/dotnet/8.0))
- **Git**
- **Accesso a Supabase** (progetti `Nutrimind - dev` e `Nutrimind - prod`)
- **Editor** (VS Code, Rider, Visual Studio)

## 1. Clonare il repository

```bash
git clone https://github.com/Fatto-App-Post/Nutrimind.git
cd Nutrimind
git checkout develop
```

## 2. Ottenere le chiavi Supabase

### DEV

1. Vai su [Supabase Dashboard](https://supabase.com/dashboard)
2. Seleziona **Nutrimind - dev**
3. Vai su **Settings → API**
4. Copia:
   - **Project URL**: `https://tcszsyzpvmsifclziujc.supabase.co`
   - **service_role key**: (la chiave segreta)

### PROD

1. Vai su [Supabase Dashboard](https://supabase.com/dashboard)
2. Seleziona **Nutrimind - prod**
3. Vai su **Settings → API**
4. Copia:
   - **Project URL**: `https://ynnlfxgehbtlneiknrfr.supabase.co`
   - **service_role key**: (la chiave segreta)

## 3. Configurare l'ambiente locale

### Opzione A: User Secrets (consigliata)

Per **sviluppo su DEV**:

```bash
cd src/Nutrimind.Api
dotnet user-secrets init
dotnet user-secrets set "Supabase:Url" "https://tcszsyzpvmsifclziujc.supabase.co"
dotnet user-secrets set "Supabase:ServiceRoleKey" "tua-service-role-key-dev"
dotnet user-secrets set "OpenFoodFacts:BaseUri" "https://world.openfoodfacts.net"
```

Per **test su PROD** (solo se necessario):

```bash
cd src/Nutrimind.Api
dotnet user-secrets set "Supabase:Url" "https://ynnlfxgehbtlneiknrfr.supabase.co"
dotnet user-secrets set "Supabase:ServiceRoleKey" "tua-service-role-key-prod"
dotnet user-secrets set "OpenFoodFacts:BaseUri" "https://world.openfoodfacts.org"
```

### Opzione B: Modificare `appsettings.Development.json`

Apri `src/Nutrimind.Api/appsettings.Development.json` e sostituisci:

```json
{
  "Supabase": {
    "Url": "https://tcszsyzpvmsifclziujc.supabase.co",
    "AnonKey": "tua-anon-key-dev",
    "ServiceRoleKey": "tua-service-role-key-dev"
  },
  "OpenFoodFacts": {
    "BaseUri": "https://world.openfoodfacts.net",
    "Username": "off",
    "Password": "off",
    "UserAgent": "Nutrimind/0.1-dev (tua-email@example.com)"
  }
}
```

**Importante:** Non committare mai chiavi reali nel repo.

## 4. Installare le dipendenze

```bash
dotnet restore
```

## 5. Eseguire i test

### Test unitari (non richiedono DB)

```bash
dotnet test tests/Nutrimind.Tests.Unit
```

### Test di integrazione (richiedono DB DEV)

Assicurati di aver configurato i secret per DEV, poi:

```bash
dotnet test tests/Nutrimind.Tests.Integration
```

### Tutti i test

```bash
dotnet test
```

## 6. Avviare l'API in locale

### Ambiente DEV (default)

```bash
cd src/Nutrimind.Api
dotnet run
```

L'API sarà disponibile su `http://localhost:5000` (o porta indicata).

### Ambiente PROD (per test locali)

```bash
cd src/Nutrimind.Api
dotnet run --environment Production
```

## 7. Endpoint di test

- **Health check**: `GET http://localhost:5000/health`
- **Ricerca alimenti (DEV)**: `GET http://localhost:5000/api/foods/search?q=nutella&limit=5`
- **Dettaglio barcode**: `GET http://localhost:5000/api/foods/barcode/3017620422003`

## 8. Verificare il DB

### DEV

1. Vai su **Supabase Dashboard → Nutrimind - dev**
2. **Table Editor → foods**
3. Filtra per `source = 'openfoodfacts'`

Dovresti vedere:
- Nutella (3017620422003)
- Coca-Cola (5449000000996)
- Doritos (5000159484126)
- Milka (7622210316769)
- Biscotti Nutella (8000500310427)

### PROD

1. Vai su **Supabase Dashboard → Nutrimind - prod**
2. **Table Editor → foods**
3. Filtra per `source = 'openfoodfacts'`

Dovresti vedere almeno:
- Biscotti Nutella (8000500310427)

## 9. GitHub Actions e Secret

Il workflow CI usa i seguenti secret (da configurare nel repo):

### Secret per DEV

- `SUPABASE_DEV_URL`
- `SUPABASE_DEV_PUBLISHABLE_KEY`
- `SUPABASE_DEV_SECRET_KEY`
- `SUPABASE_DEV_JWKS_URL`

### Secret per PROD

- `SUPABASE_PROD_URL`
- `SUPABASE_PROD_PUBLISHABLE_KEY`
- `SUPABASE_PROD_SECRET_KEY`
- `SUPABASE_PROD_JWKS_URL`

Per configurarli:

1. Vai su **https://github.com/Fatto-App-Post/Nutrimind/settings/secrets/actions**
2. Clicca **"New repository secret"** per ognuno.

## 10. Risoluzione problemi

### Errore: "Connection refused" o timeout

- Verifica che l'URL di Supabase sia corretto.
- Controlla che il firewall non blocchi le connessioni.

### Errore: "Invalid API key"

- Assicurati di usare la **service_role key** (non la publishable key).
- Verifica che non ci siano spazi extra nel file `appsettings` o nei secret.

### I test falliscono con "404 Not Found"

- Alcuni test si aspettano che il DB sia vuoto per certi barcode.
- Puoi resettare il DB di dev (solo se sei sicuro di non perdere dati):
  ```sql
  truncate table public.foods restart identity cascade;
  ```

## 11. Push e PR

Dopo aver testato in locale:

```bash
git add .
git commit -m "feat: descrizione della modifica"
git push origin develop
```

Poi apri una Pull Request su GitHub da `develop` verso `main` (o verso `develop` se sei su un branch feature).
