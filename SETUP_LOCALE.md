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
   - **service_role key**: `sb_secret_4kZzc_2-HNU-Tthf56zhbw_nBdIAt0T`
   - **publishable_key**: `sb_publishable_LjiP_fxK-yrZrD_8IRW9zw_Qv9Uq_cXU`
   - **JWKS URL**: `https://tcszsyzpvmsifclziujc.supabase.co/auth/v1/.well-known/jwks.json`

### PROD

1. Vai su [Supabase Dashboard](https://supabase.com/dashboard)
2. Seleziona **Nutrimind - prod**
3. Vai su **Settings → API**
4. Copia:
   - **Project URL**: `https://ynnlfxgehbtlneiknrfr.supabase.co`
   - **service_role key**: `sb_secret_XT0GMUvpHmPWjgl60PLJfg_CENufVxY`
   - **publishable_key**: `sb_publishable_Dkv2o2Sl9rkpA0ZeDRgwIA_5QALd4u3`
   - **JWKS URL**: `https://ynnlfxgehbtlneiknrfr.supabase.co/auth/v1/.well-known/jwks.json`

## 3. Configurare l'ambiente locale

### Opzione A: User Secrets (consigliata)

Per **sviluppo su DEV**:

```bash
cd src/Nutrimind.Api
dotnet user-secrets init
dotnet user-secrets set "Supabase:Url" "https://tcszsyzpvmsifclziujc.supabase.co"
dotnet user-secrets set "Supabase:ServiceRoleKey" "sb_secret_4kZzc_2-HNU-Tthf56zhbw_nBdIAt0T"
dotnet user-secrets set "Supabase:PublishableKey" "sb_publishable_LjiP_fxK-yrZrD_8IRW9zw_Qv9Uq_cXU"
dotnet user-secrets set "Supabase:JwksUrl" "https://tcszsyzpvmsifclziujc.supabase.co/auth/v1/.well-known/jwks.json"
dotnet user-secrets set "OpenFoodFacts:BaseUri" "https://world.openfoodfacts.net"
```

Per **test su PROD** (solo se necessario):

```bash
cd src/Nutrimind.Api
dotnet user-secrets set "Supabase:Url" "https://ynnlfxgehbtlneiknrfr.supabase.co"
dotnet user-secrets set "Supabase:ServiceRoleKey" "sb_secret_XT0GMUvpHmPWjgl60PLJfg_CENufVxY"
dotnet user-secrets set "Supabase:PublishableKey" "sb_publishable_Dkv2o2Sl9rkpA0ZeDRgwIA_5QALd4u3"
dotnet user-secrets set "Supabase:JwksUrl" "https://ynnlfxgehbtlneiknrfr.supabase.co/auth/v1/.well-known/jwks.json"
dotnet user-secrets set "OpenFoodFacts:BaseUri" "https://world.openfoodfacts.org"
```

### Opzione B: Modificare `appsettings.Development.json`

Il file è già preconfigurato con le chiavi corrette. Se devi modificarlo:

```json
{
  "Supabase": {
    "Url": "https://tcszsyzpvmsifclziujc.supabase.co",
    "ServiceRoleKey": "sb_secret_4kZzc_2-HNU-Tthf56zhbw_nBdIAt0T",
    "PublishableKey": "sb_publishable_LjiP_fxK-yrZrD_8IRW9zw_Qv9Uq_cXU",
    "JwksUrl": "https://tcszsyzpvmsifclziujc.supabase.co/auth/v1/.well-known/jwks.json"
  },
  "OpenFoodFacts": {
    "BaseUri": "https://world.openfoodfacts.net"
  }
}
```

**Importante:** Non committare mai chiavi reali nel repo se sono diverse da quelle di esempio.

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

L'API risponderà con i dettagli della configurazione:

```json
{
  "status": "OK",
  "environment": "Development",
  "supabaseUrl": "https://tcszsyzpvmsifclziujc.supabase.co",
  "offBaseUri": "https://world.openfoodfacts.net"
}
```

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

Il workflow CI usa i seguenti secret (già configurati nel repo):

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

## 10. Risoluzione problemi

### Errore: "Supabase:Url not configured"

- Verifica di aver impostato i secret o le variabili d'ambiente.
- Controlla che i nomi siano esatti (case-sensitive).

### Errore: "Invalid API key"

- Assicurati di usare la **service_role key** corretta.
- Verifica che non ci siano spazi extra.

### I test falliscono con "404 Not Found"

- Alcuni test si aspettano che il DB sia vuoto per certi barcode.
- Puoi resettare il DB di dev (solo se sei sicuro):
  ```sql
  truncate table public.foods restart identity cascade;
  ```

## 11. Push e PR

Dopo aver testato:

```bash
git add .
git commit -m "feat: descrizione"
git push origin develop
```

Poi apri una PR su GitHub.
