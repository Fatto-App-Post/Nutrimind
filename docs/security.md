# Sicurezza e configurazione ambienti

## Panoramica

Nutrimind utilizza due progetti Supabase distinti:

- **Nutrimind - dev** (`eu-west-1`): ambiente di sviluppo e test.
- **Nutrimind - prod** (`eu-north-1`): ambiente di produzione.

Ogni ambiente ha le proprie chiavi API e configurazioni.

## Configurazione backend

Il backend ASP.NET Core usa i file `appsettings.{Environment}.json`:

- `appsettings.Development.json` → punta a `Nutrimind - dev` e OFF staging (`world.openfoodfacts.net`).
- `appsettings.Production.json` → punta a `Nutrimind - prod` e OFF production (`world.openfoodfacts.org`).

Variabili critiche (da gestire come segreti):

- `Supabase:Url`
- `Supabase:ServiceRoleKey`
- `OpenFoodFacts:BaseUri`

## Sicurezza database

### Row Level Security (RLS)

Tutte le tabelle principali hanno RLS abilitato:

- `profiles`, `patient_settings`, `nutritionist_details`
- `patient_links`, `consents`, `invitations`
- `foods`, `food_portions`, `food_off_sync_log`
- `macro_plans`, `macro_plan_targets`
- `diary_entries`, `favorite_foods`, `personal_meals`
- `suggested_meals`, `suggested_meal_items`
- `nutritionist_comments`, `notifications`, `device_tokens`
- `legal_documents`, `terms_acceptances`, `audit_log`

Policy tipiche:

- Lettura: solo per utenti autenticati e solo sui propri dati o su dati esplicitamente condivisi.
- Scrittura: solo per ruoli autorizzati (es. `nutritionist` per commenti, `admin` per verifiche).

### Funzioni di sicurezza

- `is_admin()`: verifica se l'utente corrente è admin.
- `is_verified_nutritionist()`: verifica se l'utente è un nutrizionista verificato.
- `has_active_link()`, `is_my_nutritionist()`, `can_nutritionist_see()`: controllano relazioni e consensi.

### Audit log

- La tabella `audit_log` è append-only (nessun update/delete).
- Ogni azione critica dovrebbe chiamare `log_audit()`.

## Sicurezza API

- Autenticazione: JWT da Supabase Auth (`Authorization: Bearer <token>`).
- Autorizzazione: controllata a livello di servizio e tramite RLS.
- Input validation: tutti gli input sono validati (lunghezza, formato, range).
- Rate limiting: da implementare a livello di gateway/hosting.

## Open Food Facts

- DEV: `https://world.openfoodfacts.net` (staging/test).
- PROD: `https://world.openfoodfacts.org` (production).

Il backend:

- Cerca prima nel DB locale.
- Se il prodotto non esiste, chiama OFF e salva il risultato in cache (`foods` + `food_off_sync_log`).
- Non espone mai il JSON grezzo di OFF al client, solo DTO normalizzati.

## Checklist sicurezza

Prima di ogni rilascio in produzione:

- [ ] Verificare che tutte le tabelle abbiano RLS abilitato.
- [ ] Controllare che le policy siano corrette per ogni ruolo.
- [ ] Assicurarsi che le chiavi di produzione non siano committate nel repo.
- [ ] Verificare che `audit_log` registri le azioni critiche.
- [ ] Testare endpoint API con utenti di ruoli diversi.
