# NutriMind - Frontend Developer Guide

## Panoramica

NutriMind è un'applicazione per il monitoraggio nutrizionale con le seguenti caratteristiche:
- **Diario alimentare** con tracking di pasti e macro
- **Piani macro personalizzati** per pazienti
- **Dashboard nutrizionisti** per monitoraggio pazienti
- **Integrazione OpenFoodFacts** per ricerca alimenti
- **Sistema di aderenza** per valutare la compliance

---

## Configurazione Ambiente

### Supabase Projects

| Ambiente | Project ID | URL | Regione |
|----------|-----------|-----|---------|
| **DEV** | `tcszsyzpvmsifclziujc` | https://tcszsyzpvmsifclziujc.supabase.co | eu-west-1 |
| **PROD** | `ynnlfxgehbtlneiknrfr` | https://ynnlfxgehbtlneiknrfr.supabase.co | eu-north-1 |

### Variabili d'Ambiente

Crea un file `.env` nel tuo progetto frontend:

```env
# Supabase DEV
VITE_SUPABASE_URL_DEV=https://tcszsyzpvmsifclziujc.supabase.co
VITE_SUPABASE_ANON_KEY_DEV=<inserire_anon_key_dev>

# Supabase PROD
VITE_SUPABASE_URL_PROD=https://ynnlfxgehbtlneiknrfr.supabase.co
VITE_SUPABASE_ANON_KEY_PROD=<inserire_anon_key_prod>

# Edge Functions (opzionali)
VITE_FIREBASE_SERVER_KEY=<fcm_server_key>
VITE_RESEND_API_KEY=<resend_api_key>
VITE_EMAIL_FROM=NutriMind <noreply@nutrimind.app>
```

**Recuperare le API Key:**
1. Vai su https://supabase.com/dashboard/project/tcszsyzpvmsifclziujc/settings/api
2. Copia "anon public" key
3. Ripeti per PROD

---

## Database Schema

### Tabelle Principali

#### `profiles`
Informazioni utente e ruoli.

```typescript
interface Profile {
  id: string; // uuid, PK = auth.uid()
  role: 'patient' | 'nutritionist' | 'admin';
  display_name: string;
  locale: string; // default: 'it'
  professional_verified: boolean; // solo per nutrizionisti
  created_at: string;
  updated_at: string;
}
```

#### `foods`
Alimenti nel database.

```typescript
interface Food {
  id: string;
  name: string;
  brand?: string;
  barcode?: string;
  source: 'user' | 'professional' | 'off' | 'usda' | 'crea';
  source_id?: string;
  verification: 'unverified' | 'verified';
  kcal: number;
  protein_g: number;
  carbs_g: number;
  fat_g: number;
  fiber_g?: number;
  sugars_g?: number;
  saturated_fat_g?: number;
  salt_g?: number;
  serving_g?: number;
  serving_label?: string;
  trust_level: number; // 0-3 (calcolato)
  is_active: boolean;
  created_at: string;
  updated_at: string;
}
```

#### `diary_entries`
Voci del diario alimentare.

```typescript
interface DiaryEntry {
  id: string;
  patient_id: string;
  entry_date: string; // date
  meal_slot: 'breakfast' | 'lunch' | 'dinner' | 'snack';
  food_id?: string;
  custom_name?: string;
  grams: number;
  kcal: number;
  protein_g: number;
  carbs_g: number;
  fat_g: number;
  food_trust_level: number;
  entry_source: 'search' | 'manual' | 'personal_meal';
  logged_at: string;
  created_at: string;
  updated_at: string;
}
```

#### `macro_plans` + `macro_plan_targets`
Piani macro nutrizionali.

```typescript
interface MacroPlan {
  id: string;
  patient_id: string;
  nutritionist_id?: string;
  created_by: string;
  name: string;
  valid_from: string; // date
  valid_to?: string; // date
  created_at: string;
  updated_at: string;
}

interface MacroPlanTarget {
  id: string;
  plan_id: string;
  day_of_week: number; // 1-7 (lun-dom)
  meal_slot: 'breakfast' | 'lunch' | 'dinner' | 'snack';
  protein_g: number;
  carbs_g: number;
  fat_g: number;
  kcal_estimated?: number;
}
```

#### `patient_links`
Collegamento nutrizionista-paziente.

```typescript
interface PatientLink {
  id: string;
  patient_id: string;
  nutritionist_id: string;
  status: 'pending' | 'active' | 'revoked';
  created_at: string;
  revoked_at?: string;
  revoked_by?: string;
}
```

### Altre Tabelle

- `patient_settings` - Preferenze paziente (dietary_restrictions, timezone, reminders)
- `nutritionist_details` - Dettagli professionali nutrizionista
- `favorite_foods` - Alimenti preferiti per accesso rapido
- `personal_meals` + `personal_meal_items` - Pasti personali predefiniti
- `notifications` - Notifiche push/in-app
- `device_tokens` - Token per push notifications
- `nutritionist_comments` - Commenti sui diari dei pazienti
- `food_portions` - Porzioni predefinite per alimenti
- `consents` - Consensi GDPR per condivisione dati
- `invitations` - Codici invito per nutrizionisti

---

## Database Functions (RPC)

### Alimenti

#### `search_foods(query, limit?)`
Cerca alimenti nel database locale + fallback OpenFoodFacts.

```typescript
const { data, error } = await supabase
  .rpc('search_foods', { p_query: 'pasta', p_limit: 20 });
```

#### `get_food(id)`
Ottieni dettaglio alimento per ID.

```typescript
const { data, error } = await supabase
  .rpc('get_food', { p_id: 'uuid' });
```

#### `get_food_by_barcode(barcode)`
Ottieni alimento per barcode (cerca su OFF se non trovato).

```typescript
const { data, error } = await supabase
  .rpc('get_food_by_barcode', { p_barcode: '8001234567890' });
```

#### `create_food(params)`
Crea nuovo alimento (solo nutrizionisti verificati o admin).

```typescript
const { data: foodId, error } = await supabase.rpc('create_food', {
  p_name: 'Pasta al pomodoro',
  p_kcal: 150,
  p_protein_g: 5,
  p_carbs_g: 30,
  p_fat_g: 1,
  p_brand: 'Barilla',
  p_barcode: '8001234567890',
  // ... altri campi opzionali
});
```

**Parametri obbligatori:** `p_name`, `p_kcal`, `p_protein_g`, `p_carbs_g`, `p_fat_g`

#### `update_food(id, params)`
Aggiorna alimento (solo creatore o admin).

```typescript
const { error } = await supabase.rpc('update_food', {
  p_id: 'uuid',
  p_name: 'Nuovo nome',
  p_kcal: 160,
  // ... altri campi
});
```

#### `delete_food(id)`
Soft delete alimento (solo creatore o admin).

```typescript
const { error } = await supabase.rpc('delete_food', { p_id: 'uuid' });
```

---

### Diario

#### `log_meal(entry_date, meal_slot, grams, food_id?, custom_name?)`
Registra pasto nel diario.

```typescript
const { data: entryId, error } = await supabase.rpc('log_meal', {
  p_entry_date: '2026-10-04',
  p_meal_slot: 'lunch',
  p_grams: 100,
  p_food_id: 'uuid', // opzionale se custom_name
  p_custom_name: 'Pasto personalizzato', // opzionale se food_id
});
```

#### `get_diary_entries(date, patient_id?)`
Ottieni voci diario per una data.

```typescript
const { data, error } = await supabase.rpc('get_diary_entries', {
  p_date: '2026-10-04',
  p_patient_id: 'uuid', // opzionale, default auth.uid()
});
```

#### `delete_diary_entry(entry_id)`
Elimina voce dal diario.

```typescript
const { error } = await supabase.rpc('delete_diary_entry', {
  p_entry_id: 'uuid',
});
```

---

### Piani Macro

#### `start_macro_plan(patient_id, name?, valid_from?, targets?)`
Crea nuovo piano macro.

```typescript
const { data: planId, error } = await supabase.rpc('start_macro_plan', {
  p_patient_id: 'uuid',
  p_name: 'Piano Ottobre',
  p_valid_from: '2026-10-01',
  p_targets: [
    {
      day_of_week: 1,
      meal_slot: 'breakfast',
      protein_g: 20,
      carbs_g: 50,
      fat_g: 10,
    },
    // ... altri target
  ],
});
```

#### `get_current_macro_plan(patient_id?)`
Ottieni piano macro corrente.

```typescript
const { data, error } = await supabase.rpc('get_current_macro_plan', {
  p_patient_id: 'uuid', // opzionale, default auth.uid()
});
```

---

### Dashboard Nutrizionista

#### `get_my_patients()`
Lista pazienti per nutrizionista.

```typescript
const { data, error } = await supabase.rpc('get_my_patients');
// Returns: Array di { patient_id, display_name, link_id, linked_since, shares_adherence, last_logged_date, days_logged_last_7, days_on_target_last_7, attention_score }
```

#### `get_patient_adherence(patient_id, from, to, tolerance?)`
Ottieni aderenza paziente.

```typescript
const { data, error } = await supabase.rpc('get_patient_adherence', {
  p_patient_id: 'uuid',
  p_from: '2026-10-01',
  p_to: '2026-10-31',
  p_tolerance: 0.10, // 10% default
});
```

#### `get_diary_with_comments(patient_id, from, to)`
Ottieni diario con commenti nutrizionista.

```typescript
const { data, error } = await supabase.rpc('get_diary_with_comments', {
  p_patient_id: 'uuid',
  p_from: '2026-10-01',
  p_to: '2026-10-31',
});
// Returns: Array di { entry_date, meal_slot, entries: [], comments: [] }
```

---

### Preferiti e Pasti Personali

#### `add_favorite_food(food_id, default_grams?, default_slot?)`
Aggiungi alimento ai preferiti.

```typescript
const { data: favoriteId, error } = await supabase.rpc('add_favorite_food', {
  p_food_id: 'uuid',
  p_default_grams: 100,
  p_default_slot: 'breakfast',
});
```

#### `get_favorite_foods()`
Ottieni preferiti utente.

```typescript
const { data, error } = await supabase.rpc('get_favorite_foods');
```

#### `create_personal_meal(name, items, default_slot?)`
Crea pasto personale.

```typescript
const { data: mealId, error } = await supabase.rpc('create_personal_meal', {
  p_name: 'Colazione tipica',
  p_items: [
    { food_id: 'uuid-1', grams: 50 },
    { food_id: 'uuid-2', grams: 100 },
  ],
  p_default_slot: 'breakfast',
});
```

#### `log_personal_meal(meal_id, date, slot)`
Registra pasto personale nel diario.

```typescript
const { data: count, error } = await supabase.rpc('log_personal_meal', {
  p_meal_id: 'uuid',
  p_date: '2026-10-04',
  p_slot: 'breakfast',
});
// Returns: numero di voci inserite
```

---

### Commenti Nutrizionista

#### `create_nutritionist_comment(patient_id, comment_date, body, meal_slot?, diary_entry_id?)`
Crea commento su diario paziente.

```typescript
const { data: commentId, error } = await supabase.rpc('create_nutritionist_comment', {
  p_patient_id: 'uuid',
  p_comment_date: '2026-10-04',
  p_body: 'Ottimo lavoro oggi!',
  p_meal_slot: 'lunch',
  p_diary_entry_id: 'uuid', // opzionale
});
```

#### `get_nutritionist_comments(patient_id, from?, to?)`
Ottieni commenti per paziente.

```typescript
const { data, error } = await supabase.rpc('get_nutritionist_comments', {
  p_patient_id: 'uuid',
  p_from: '2026-10-01',
  p_to: '2026-10-31',
});
```

#### `mark_comment_read(comment_id)`
Segna commento come letto.

```typescript
const { error } = await supabase.rpc('mark_comment_read', {
  p_comment_id: 'uuid',
});
```

---

### Porzioni Cibo

#### `get_food_portions(food_id)`
Ottieni porzioni predefinite per alimento.

```typescript
const { data, error } = await supabase.rpc('get_food_portions', {
  p_food_id: 'uuid',
});
```

#### `create_food_portion(food_id, label, grams)`
Crea porzione predefinita (solo nutrizionisti).

```typescript
const { data: portionId, error } = await supabase.rpc('create_food_portion', {
  p_food_id: 'uuid',
  p_label: '1 mela media',
  p_grams: 150,
});
```

---

### Notifiche

#### `get_unread_notifications()`
Ottieni notifiche non lette.

```typescript
const { data, error } = await supabase.rpc('get_unread_notifications');
```

#### `mark_notification_read(notification_id)`
Segna notifica come letta.

```typescript
const { error } = await supabase.rpc('mark_notification_read', {
  p_notification_id: 'uuid',
});
```

---

### Audit

#### `log_data_access(action, entity, entity_id, patient_id?, extra_data?)`
Logga accesso ai dati per audit.

```typescript
const { error } = await supabase.rpc('log_data_access', {
  p_action: 'view',
  p_entity: 'diary_entries',
  p_entity_id: 'uuid',
  p_patient_id: 'uuid',
  p_extra_data: { reason: 'clinical_review' },
});
```

---

## Edge Functions

### URL Base

```
DEV:  https://tcszsyzpvmsifclziujc.supabase.co/functions/v1/
PROD: https://ynnlfxgehbtlneiknrfr.supabase.co/functions/v1/
```

### `search-off`
Cerca alimenti su OpenFoodFacts API.

```typescript
const response = await fetch(`${SUPABASE_URL}/functions/v1/search-off`, {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({
    query: 'pasta barilla',
    limit: 10,
  }),
});

const { results } = await response.json();
// results: Array di alimenti OFF
```

### `import-off-barcode`
Importa alimento da OFF per barcode.

```typescript
const response = await fetch(`${SUPABASE_URL}/functions/v1/import-off-barcode`, {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({
    barcode: '8001234567890',
  }),
});

const { food_id, imported } = await response.json();
// imported: true se nuovo, false se già esistente
```

Gli alimenti importati hanno `source = 'openfoodfacts'` e `verification = 'unverified'`.
In errore il body è `{ error, code }`:

| HTTP | `code` | Significato |
|------|--------|-------------|
| 400 | `invalid_barcode` | barcode non valido (8-14 cifre) |
| 401 | `unauthorized` | JWT mancante o non valido |
| 404 | `product_not_found`, `incomplete_product` | prodotto assente su OFF o senza valori nutrizionali utilizzabili → trattare come "non trovato" |
| 429 | `upstream_rate_limited`, `rate_limited` | rate limit OFF o limite di 30 alimenti/24h → temporaneo, riprovare (rispettare `Retry-After`) |
| 502 / 503 / 504 | `upstream_error`, `upstream_unavailable` | OFF non disponibile → temporaneo, riprovare |
| 500 | `internal_error` | errore interno |

Secrets opzionali della funzione: `OFF_BASE_URI` (default: `https://world.openfoodfacts.net` su DEV, `.org` su PROD),
`OFF_USER_AGENT` (es. `Nutrimind/0.1-dev (email@dominio)`), `OFF_USERNAME` / `OFF_PASSWORD` (default `off`/`off` su staging).

### `sync-off-batch`
Sincronizza alimenti OFF in background (solo admin).

```typescript
const response = await fetch(`${SUPABASE_URL}/functions/v1/sync-off-batch`, {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
  },
});

const { synced, errors, total } = await response.json();
```

### `send-notification`
Invia push notification.

```typescript
const response = await fetch(`${SUPABASE_URL}/functions/v1/send-notification`, {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({
    title: 'Nuovo commento',
    body: 'Hai ricevuto un commento dal nutrizionista',
    user_id: 'uuid',
    data: { type: 'nutritionist_comment', comment_id: 'uuid' },
  }),
});

const { sent, total } = await response.json();
```

### `send-email`
Invia email.

```typescript
const response = await fetch(`${SUPABASE_URL}/functions/v1/send-email`, {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({
    to: 'user@example.com',
    subject: 'Benvenuto su NutriMind',
    text: 'Ciao, benvenuto!',
    html: '<p>Ciao, <strong>benvenuto</strong>!</p>',
  }),
});

const { success, email_id } = await response.json();
```

### `generate-meal-plan`
Genera piano pasti automatico.

```typescript
const response = await fetch(`${SUPABASE_URL}/functions/v1/generate-meal-plan`, {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({
    patient_id: 'uuid',
    date: '2026-10-04',
    preferences: { vegetarian: false }, // opzionale
  }),
});

const { suggestions, total_kcal, total_protein, total_carbs, total_fat } = await response.json();
```

### `analyze-adherence`
Analisi avanzata aderenza.

```typescript
const response = await fetch(`${SUPABASE_URL}/functions/v1/analyze-adherence`, {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({
    patient_id: 'uuid',
    from_date: '2026-10-01',
    to_date: '2026-10-31',
  }),
});

const {
  period,
  total_days,
  logged_days,
  on_target_days,
  adherence_rate,
  daily_breakdown,
} = await response.json();
```

---

## Row Level Security (RLS)

### Regole Principali

#### `profiles`
- **SELECT**: Tutti gli utenti autenticati possono vedere il proprio profilo
- **UPDATE**: Solo il proprietario può aggiornare il proprio profilo
- **INSERT**: Trigger automatico alla creazione utente

#### `foods`
- **SELECT**: Tutti gli utenti autenticati possono leggere alimenti attivi
- **INSERT**: Solo nutrizionisti verificati e admin
- **UPDATE**: Solo creatore o admin
- **DELETE**: Solo creatore o admin (soft delete)

#### `diary_entries`
- **SELECT**: Paziente proprietario o nutrizionista con link attivo
- **INSERT**: Solo il paziente proprietario
- **UPDATE**: Solo il paziente proprietario
- **DELETE**: Solo il paziente proprietario

#### `macro_plans`
- **SELECT**: Paziente proprietario o nutrizionista con link attivo
- **INSERT**: Nutrizionista con link attivo o paziente stesso
- **UPDATE**: Nutrizionista con link attivo o admin

#### `patient_links`
- **SELECT**: Paziente o nutrizionista coinvolti
- **INSERT**: Solo nutrizionisti
- **UPDATE/DELETE**: Solo nutrizionista proprietario o admin

---

## Best Practices

### 1. Gestione Errori

```typescript
try {
  const { data, error } = await supabase.rpc('search_foods', { p_query: 'pasta' });
  
  if (error) {
    if (error.code === '42501') {
      // Forbidden
      toast.error('Non hai i permessi per questa azione');
    } else if (error.code === 'P0002') {
      // Food not found
      toast.error('Alimento non trovato');
    } else {
      toast.error(error.message);
    }
    return;
  }
  
  // Usa data
} catch (err) {
  console.error('Unexpected error:', err);
  toast.error('Errore inaspettato');
}
```

### 2. Ottimizzazione Query

```typescript
// ✅ BUONO: Usa RPC per query complesse
const { data } = await supabase.rpc('get_diary_entries', { p_date: date });

// ❌ CATTIVO: Fetch manuale con join multipli
const { data } = await supabase
  .from('diary_entries')
  .select('*, foods(*)')
  .eq('entry_date', date);
```

### 3. Cache Local State

```typescript
// Usa React Query o SWR per cache
const { data: foods } = useQuery(
  ['foods', query],
  () => supabase.rpc('search_foods', { p_query: query }).then(r => r.data)
);
```

### 4. Real-time Updates

```typescript
// Sottoscrivi a cambiamenti per aggiornamenti in tempo reale
const channel = supabase
  .channel('diary-updates')
  .on('postgres_changes', {
    event: '*',
    schema: 'public',
    table: 'diary_entries',
    filter: `patient_id=eq.${userId}`,
  }, (payload) => {
    // Aggiorna UI
  })
  .subscribe();
```

---

## Esempi di Utilizzo

### Ricerca e Log Alimento

```typescript
async function searchAndLogFood(query: string, date: string, slot: MealSlot) {
  // 1. Cerca alimento
  const { data: foods } = await supabase.rpc('search_foods', {
    p_query: query,
    p_limit: 5,
  });
  
  if (!foods || foods.length === 0) {
    throw new Error('Nessun alimento trovato');
  }
  
  // 2. Log nel diario
  const { data: entryId, error } = await supabase.rpc('log_meal', {
    p_entry_date: date,
    p_meal_slot: slot,
    p_food_id: foods[0].id,
    p_grams: 100,
  });
  
  if (error) throw error;
  
  return entryId;
}
```

### Dashboard Nutrizionista

```typescript
async function loadNutritionistDashboard() {
  // 1. Ottieni lista pazienti
  const { data: patients } = await supabase.rpc('get_my_patients');
  
  // 2. Per ogni paziente, ottieni aderenza
  const patientsWithAdherence = await Promise.all(
    patients.map(async (patient) => {
      const { data: adherence } = await supabase.rpc('get_patient_adherence', {
        p_patient_id: patient.patient_id,
        p_from: startOfWeek,
        p_to: endOfWeek,
      });
      
      return { ...patient, adherence };
    })
  );
  
  return patientsWithAdherence;
}
```

### Crea Piano Macro

```typescript
async function createMacroPlan(patientId: string, targets: TargetInput[]) {
  // 1. Crea piano
  const { data: planId, error: planError } = await supabase.rpc('start_macro_plan', {
    p_patient_id: patientId,
    p_name: 'Piano Personalizzato',
    p_valid_from: new Date().toISOString().split('T')[0],
    p_targets: targets.map(t => ({
      day_of_week: t.day,
      meal_slot: t.slot,
      protein_g: t.protein,
      carbs_g: t.carbs,
      fat_g: t.fat,
    })),
  });
  
  if (planError) throw planError;
  
  return planId;
}
```

---

## Troubleshooting

### Errori Comuni

#### `error: "relation \"foods\" does not exist"`
**Causa:** Search path non impostato correttamente.
**Soluzione:** Assicurati che le funzioni usino `set search_path = 'public'`.

#### `error: "forbidden"`
**Causa:** RLS blocca l'accesso.
**Soluzione:** Verifica che l'utente abbia il ruolo corretto e i permessi necessari.

#### `error: "nutritionist_not_verified"`
**Causa:** Nutrizionista non ancora verificato da admin.
**Soluzione:** Attendere verifica o contattare admin.

#### `error: "food_not_found"`
**Causa:** Food ID non esiste o è stato eliminato.
**Soluzione:** Ricercare l'alimento o usare `custom_name`.

---

## Risorse

- **GitHub Repo:** https://github.com/Fatto-App-Post/Nutrimind
- **Supabase Dashboard DEV:** https://supabase.com/dashboard/project/tcszsyzpvmsifclziujc
- **Supabase Dashboard PROD:** https://supabase.com/dashboard/project/ynnlfxgehbtlneiknrfr
- **OpenFoodFacts API:** https://world.openfoodfacts.org/data

---

## Contatti

Per domande o supporto, contattare il team di sviluppo.
