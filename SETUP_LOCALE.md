# Setup Locale e Test

## Prerequisiti

- **.NET 8 SDK** ([download](https://dotnet.microsoft.com/download/dotnet/8.0))
- **Git**
- **Accesso a Supabase** (progetto `Nutrimind - dev`)
- **Editor** (VS Code, Rider, Visual Studio)

## 1. Clonare il repository

```bash
git clone https://github.com/Fatto-App-Post/Nutrimind.git
cd Nutrimind
git checkout develop
```

## 2. Ottenere le chiavi Supabase

1. Vai su [Supabase Dashboard](https://supabase.com/dashboard)
2. Seleziona il progetto **Nutrimind - dev**
3. Vai su **Settings → API**
4. Copia:
   - **Project URL** (es. `https://tcszsyzpvmsifclziujc.supabase.co`)
   - **service_role key** (chiave segreta, **non condividerla**)

## 3. Configurare `appsettings.Development.json`

Apri il file `src/Nutrimind.Api/appsettings.Development.json` e sostituisci:

```json
{
  "Supabase": {
    "Url": "https://TUO-PROJECT-REF.supabase.co",
    "AnonKey": "tua-anon-key",
    "ServiceRoleKey": "tua-service-role-key"
  },
  "OpenFoodFacts": {
    "BaseUri": "https://world.openfoodfacts.net",
    "Username": "off",
    "Password": "off",
    "UserAgent": "Nutrimind/0.1-dev (tua-email@example.com)"
  }
}
```

**Importante:**
- Usa la **ServiceRoleKey** solo in locale per i test.
- Non committare mai chiavi reali nel repo (usa `.gitignore` o user-secrets).

### Alternativa: User Secrets (consigliata)

Invece di modificare `appsettings.Development.json`, puoi usare i secret locali:

```bash
cd src/Nutrimind.Api
dotnet user-secrets init
dotnet user-secrets set "Supabase:Url" "https://tcszsyzpvmsifclziujc.supabase.co"
dotnet user-secrets set "Supabase:ServiceRoleKey" "tua-service-role-key"
dotnet user-secrets set "OpenFoodFacts:BaseUri" "https://world.openfoodfacts.net"
```

## 4. Installare le dipendenze

```bash
dotnet restore
```

## 5. Eseguire i test

### Test unitari

```bash
dotnet test tests/Nutrimind.Tests.Unit
```

### Test di integrazione

```bash
dotnet test tests/Nutrimind.Tests.Integration
```

### Tutti i test

```bash
dotnet test
```

## 6. Avviare l'API in locale

```bash
cd src/Nutrimind.Api
dotnet run
```

L'API sarà disponibile su:
- `http://localhost:5000` (o porta indicata nel terminale)

### Endpoint di test

- **Health check**: `GET http://localhost:5000/health`
- **Ricerca alimenti**: `GET http://localhost:5000/api/foods/search?q=nutella&limit=5`
- **Dettaglio barcode**: `GET http://localhost:5000/api/foods/barcode/3017620422003`

## 7. Verificare il DB

Puoi verificare che gli alimenti seed siano presenti:

1. Vai su **Supabase Dashboard → Nutrimind - dev**
2. **Table Editor → foods**
3. Filtra per `source = 'openfoodfacts'`

Dovresti vedere:
- Nutella (3017620422003)
- Coca-Cola (5449000000996)
- Doritos (5000159484126)
- Milka (7622210316769)
- Biscotti Nutella (8000500310427)

## 8. Risoluzione problemi

### Errore: "Connection refused" o timeout

- Verifica che l'URL di Supabase sia corretto.
- Controlla che il firewall non blocchi le connessioni.

### Errore: "Invalid API key"

- Assicurati di usare la **service_role key** (non la anon key).
- Verifica che non ci siano spazi extra nel file `appsettings`.

### I test falliscono con "404 Not Found"

- Alcuni test si aspettano che il DB sia vuoto per certi barcode.
- Puoi resettare il DB di dev (solo se sei sicuro di non perdere dati):
  ```sql
  truncate table public.foods restart identity cascade;
  ```

## 9. Push e PR

Dopo aver testato in locale:

```bash
git add .
git commit -m "feat: descrizione della modifica"
git push origin develop
```
Poi apri una Pull Request su GitHub da `develop` verso `main` (o verso `develop` se sei su un branch feature).
