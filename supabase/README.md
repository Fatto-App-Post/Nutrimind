# NutriMind - Backend Supabase Setup

## Panoramica

Questo progetto usa **Supabase** come backend completo:
- ✅ Autenticazione
- ✅ Database PostgreSQL con RLS
- ✅ Edge Functions per OpenFoodFacts
- ✅ Realtime subscriptions

Il frontend si interfaccia **direttamente** con Supabase, senza backend .NET intermedio.

---

## Setup Iniziale

### 1. Esegui le Migrazioni SQL

Nel **SQL Editor** di Supabase, esegui in ordine:

```sql
-- 1. Fondamenta (già esistente)
-- 001_foundation.sql

-- 2. Utenti e collegamenti (già esistente)
-- 002_users_and_links.sql

-- 3. Alimenti (già esistente)
-- 003_foods.sql

-- 4. Piano e diario (già esistente)
-- 004_plans_and_diary.sql

-- 5. Libreria pasti (già esistente)
-- 005_meal_library.sql

-- 6. Comunicazione (già esistente)
-- 006_communication.sql

-- 7. Compliance e audit (già esistente)
-- 007_compliance_audit.sql

-- 8. Dashboard (già esistente)
-- 008_dashboard_rpcs.sql

-- 9. Security hardening (già esistente)
-- 009_security_hardening.sql

-- 10. Seed dati dev (opzionale)
-- 010_seed_dev.sql

-- 11. NUOVE FUNZIONI PER IL FRONTEND
supabase/migrations/011_functions.sql

-- 12. FUNZIONI OPENFOODFACTS
supabase/migrations/012_off_functions.sql
```

### 2. Abilita HTTP Extension

```sql
create extension if not exists http with schema extensions;
```

### 3. Imposta Service Role Key

Aggiungi questa variabile d'ambiente in Supabase:

```sql
-- Non serve, usa quella di sistema: current_setting('supabase.service_role_key')
```

---

## Deploy Edge Functions

### Prerequisiti

```bash
# Installa Supabase CLI
npm install -g supabase

# Verifica installazione
supabase --version
```

### Deploy

```bash
# 1. Login
supabase login

# 2. Link al progetto (usa il tuo project ref)
supabase link --project-ref tcszsyzpvmsifclziujc

# 3. Deploy Edge Function
cd supabase/functions/search-off
supabase functions deploy search-off
```

### Test Edge Function

```bash
# Test locale
supabase functions serve search-off

# Test con curl
curl -i --location --request POST 'http://localhost:54321/functions/v1/search-off' \
  --header 'Content-Type: application/json' \
  --data '{"barcode":"8000500310427"}'
```

---

## Configurazione Frontend

### Variabili d'Ambiente

Nel tuo frontend (React/Flutter/etc.):

```env
VITE_SUPABASE_URL=https://tcszsyzpvmsifclziujc.supabase.co
VITE_SUPABASE_ANON_KEY=sb_publishable_LjiP_fxK-yrZrD_8IRW9zw_Qv9Uq_cX
```

### Esempio React

```tsx
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  import.meta.env.VITE_SUPABASE_URL,
  import.meta.env.VITE_SUPABASE_ANON_KEY
)

// Usage
const { data, error } = await supabase.rpc('search_foods', { 
  p_query: 'pasta' 
})
```

---

## Struttura Database

### Tabelle Principali

- **profiles** - Profili utente (role, display_name, etc.)
- **patient_settings** - Impostazioni pazienti (dietary restrictions, timezone)
- **nutritionist_details** - Dettagli nutrizionisti (studio, bio)
- **foods** - Database alimenti (locale + OpenFoodFacts)
- **diary_entries** - Diario alimentare
- **macro_plans** - Piani macro nutrizionali
- **macro_plan_targets** - Target macro per pasto/giorno
- **patient_links** - Collegamenti paziente-nutrizionista
- **consents** - Consensi GDPR
- **invitations** - Codici invito
- **favorite_foods** - Alimenti preferiti
- **personal_meals** - Pasti personali
- **notifications** - Notifiche push

### Funzioni RPC Principali

- `search_foods(p_query, p_limit)` - Cerca alimenti con fallback OFF
- `get_food_by_barcode(p_barcode)` - Dettaglio per barcode
- `log_meal(...)` - Registra pasto nel diario
- `start_macro_plan(...)` - Crea nuovo piano macro
- `get_patient_adherence(...)` - Aderenza giorno per giorno
- `get_my_patients()` - Lista pazienti (nutrizionisti)
- `create_invitation()` - Crea codice invito
- `redeem_invitation(...)` - Riscatta invito
- `grant_consent(...)` - Concedi consenso
- `revoke_consent(...)` - Revoca consenso

Vedi `docs/FRONTEND_SUPABASE_GUIDE.md` per la documentazione completa.

---

## Row Level Security (RLS)

Tutte le tabelle hanno RLS attivo. Policy principali:

- **profiles**: Vedi solo te stesso, i tuoi pazienti, il tuo nutrizionista
- **patient_settings**: Il paziente gestisce le proprie, nutrizionista legge con consenso
- **diary_entries**: Il paziente gestisce le proprie, nutrizionista legge con consenso 'diary'
- **macro_plans**: Paziente e nutrizionista che l'ha creato
- **foods**: Tutti leggono, solo nutrizionisti verificati o admin scrivono

Le funzioni RPC sono `security definer` e applicano le regole di business.

---

## OpenFoodFacts Integration

### Come Funziona

1. Il frontend chiama `search_foods('8000500310427')`
2. La funzione SQL cerca nel DB locale
3. Se non trovato, chiama la Edge Function `search-off`
4. La Edge Function interroga OpenFoodFacts API
5. Il risultato viene cachato nel DB locale
6. Viene ritornato al frontend

### Edge Function Flow

```
Frontend → RPC search_foods → SQL function 
  → Edge Function search-off → OpenFoodFacts API
  → Cache in foods table → Ritorna al frontend
```

---

## Monitoraggio

### Log Edge Functions

```bash
supabase functions logs search-off
```

### Query Performance

Usa **Database → Query Performance** nel dashboard Supabase per monitorare le query lente.

### Audit Log

Tutte le operazioni sono loggate in `audit_log` per compliance GDPR.

---

## Troubleshooting

### "Function does not exist"

Assicurati di aver eseguito `011_functions.sql` nel SQL Editor.

### "Permission denied"

Verifica che l'utente abbia i permessi corretti tramite RLS.

### Edge Function 500 Error

Controlla i log:
```bash
supabase functions logs search-off --format json
```

### HTTP Extension Missing

```sql
create extension if not exists http with schema extensions;
```

---

## Next Steps

1. ✅ Esegui migrazioni SQL
2. ✅ Deploy Edge Functions
3. ✅ Configura frontend con Supabase client
4. ✅ Testa flusso completo (registro, login, cerca alimenti, log pasto)
5. ✅ Implementa realtime subscriptions
6. ✅ Deploy in produzione

---

## Documentazione

- **Frontend Guide**: `docs/FRONTEND_SUPABASE_GUIDE.md`
- **Supabase Docs**: https://supabase.com/docs
- **Edge Functions**: https://supabase.com/docs/guides/functions

---

**Hai tutto il necessario per partire! 🚀**
