# 🚀 NutriMind - Setup & Configurazione Completa

**Ultimo aggiornamento:** 2026-10-04  
**Stato:** Backend 100% completo - Pronto per sviluppo frontend

---

## 📋 Indice

1. [Servizi Esterni da Configurare](#servizi-esterni-da-configurare)
2. [Variabili Ambiente](#variabili-ambiente)
3. [Configurazione Auth](#configurazione-auth)
4. [Setup Frontend](#setup-frontend)
5. [Esempi di Utilizzo](#esempi-di-utilizzo)
6. [Troubleshooting](#troubleshooting)

---

## 🎯 Servizi Esterni da Configurare

### **1. Firebase Cloud Messaging (FCM)** - Per Push Notifications

**Perché serve:** Inviare notifiche push ai dispositivi mobili (reminder pasti, commenti, etc.)

**Come ottenerlo:**

1. Vai su [Firebase Console](https://console.firebase.google.com/)
2. Crea un nuovo progetto "NutriMind"
3. Abilita **Cloud Messaging**
4. Vai su **Project Settings** > **Service Accounts**
5. Clicca **Generate New Private Key**
6. Scarica il file JSON
7. Copia il valore di `server_key` (o `cloud_messaging_sender_id`)

**Configura su Supabase:**

```bash
# Vai su:
# DEV: https://supabase.com/dashboard/project/tcszsyzpvmsifclziujc/settings/edge-functions
# PROD: https://supabase.com/dashboard/project/ynnlfxgehbtlneiknrfr/settings/edge-functions

# Aggiungi questa variabile:
FIREBASE_SERVER_KEY=AAAA... (la tua server key da Firebase)
```

**Costo:** Gratis fino a 100M messaggi/mese

---

### **2. Resend** - Per Email Transazionali

**Perché serve:** Inviare email (inviti nutrizionisti, recovery password, newsletter)

**Come ottenerlo:**

1. Vai su [Resend.com](https://resend.com/)
2. Registrati con GitHub/Google
3. Crea un nuovo API Key
4. Verifica il dominio (opzionale per testing, usa `@resend.dev`)

**Configura su Supabase:**

```bash
# Aggiungi queste variabili:
RESEND_API_KEY=re_xxxxxxxxxxxxxxxxxxxxx
EMAIL_FROM=NutriMind <onboarding@resend.dev>
```

**Costo:** Gratis fino a 3,000 email/mese (100/giorno)

---

### **3. OpenFoodFacts** - Database Alimenti

**Perché serve:** Cercare e importare alimenti dal database mondiale

**Configurazione:** Nessuna! È gratuito e pubblico.

**Limiti:** 1 richiesta/secondo (per utente anonimo)

**Documentazione:** https://world.openfoodfacts.org/data

---

### **4. Google OAuth (Opzionale)** - Login con Google

**Perché serve:** Permettere login rapido con account Google

**Come ottenerlo:**

1. Vai su [Google Cloud Console](https://console.cloud.google.com/)
2. Crea un nuovo progetto
3. Vai su **APIs & Services** > **Credentials**
4. Crea **OAuth 2.0 Client ID**
5. Aggiungi redirect URL: `https://tcszsyzpvmsifclziujc.supabase.co/auth/v1/callback`
6. Copia **Client ID** e **Client Secret**

**Configura su Supabase:**

```bash
# Vai su:
# DEV: https://supabase.com/dashboard/project/tcszsyzpvmsifclziujc/auth/providers
# PROD: https://supabase.com/dashboard/project/ynnlfxgehbtlneiknrfr/auth/providers

# Abilita Google e inserisci:
Google Client ID: xxxxxxxx.apps.googleusercontent.com
Google Client Secret: GOCSPX-xxxxxxxxxxxxx
```

**Costo:** Gratis

---

## 🔐 Variabili Ambiente

### **DEV (tcszsyzpvmsifclziujc)**

| Variabile | Valore | Dove Configurarla |
|-----------|--------|-------------------|
| `FIREBASE_SERVER_KEY` | `AAAA...` (da Firebase) | Edge Functions Settings |
| `RESEND_API_KEY` | `re_xxxxx` (da Resend) | Edge Functions Settings |
| `EMAIL_FROM` | `NutriMind <onboarding@resend.dev>` | Edge Functions Settings |
| `SUPABASE_URL` | `https://tcszsyzpvmsifclziujc.supabase.co` | Auto |
| `SUPABASE_ANON_KEY` | `eyJhbG...` (dalla dashboard) | Auto |
| `SUPABASE_SERVICE_ROLE_KEY` | `eyJhbG...` (dalla dashboard) | Auto |

### **PROD (ynnlfxgehbtlneiknrfr)**

| Variabile | Valore | Dove Configurarla |
|-----------|--------|-------------------|
| `FIREBASE_SERVER_KEY` | `AAAA...` (da Firebase - stessa o diversa) | Edge Functions Settings |
| `RESEND_API_KEY` | `re_xxxxx` (da Resend - stessa o diversa) | Edge Functions Settings |
| `EMAIL_FROM` | `NutriMind <noreply@nutrimind.app>` | Edge Functions Settings |
| `SUPABASE_URL` | `https://ynnlfxgehbtlneiknrfr.supabase.co` | Auto |
| `SUPABASE_ANON_KEY` | `eyJhbG...` (dalla dashboard) | Auto |
| `SUPABASE_SERVICE_ROLE_KEY` | `eyJhbG...` (dalla dashboard) | Auto |

---

## ⚙️ Configurazione Auth

### **Trigger per Nuovi Utenti**

I trigger sono già configurati! Quando un utente si registra:

1. Viene creato automaticamente il record in `profiles` (ruolo: `patient`)
2. Viene creato `patient_settings` con valori default

**Per testare:**

```typescript
// Frontend
const { data, error } = await supabase.auth.signUp({
  email: 'test@example.com',
  password: 'password123'
});

// Dopo il signup, verifica che esista il profilo:
const { data: profile } = await supabase
  .from('profiles')
  .select('*')
  .eq('id', data.user.id)
  .single();

console.log(profile); // Dovrebbe esistere!
```

---

## 💻 Setup Frontend

### **1. Installa Dipendenze**

```bash
npm install @supabase/supabase-js
```

### **2. Configura Client**

Crea un file `.env.local`:

```env
# DEV
NEXT_PUBLIC_SUPABASE_URL=https://tcszsyzpvmsifclziujc.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...

# PROD (quando sei pronto)
# NEXT_PUBLIC_SUPABASE_URL=https://ynnlfxgehbtlneiknrfr.supabase.co
# NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

### **3. Crea Client Supabase**

```typescript
// lib/supabaseClient.ts
import { createClient } from '@supabase/supabase-js'

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!

export const supabase = createClient(supabaseUrl, supabaseAnonKey)
```

---

## 📚 Esempi di Utilizzo

### **Auth - Login/Signup**

```typescript
// Signup
const { data, error } = await supabase.auth.signUp({
  email: 'mario@example.com',
  password: 'password123',
  options: {
    data: { display_name: 'Mario Rossi' } // Opzionale
  }
});

// Login
const { data, error } = await supabase.auth.signInWithPassword({
  email: 'mario@example.com',
  password: 'password123'
});

// Logout
await supabase.auth.signOut();

// Ottieni utente corrente
const { data: { user } } = await supabase.auth.getUser();
const role = user?.user_metadata?.role || 'patient';
```

### **Cerca Alimenti**

```typescript
// Cerca nel DB locale + OpenFoodFacts
const { data: foods, error } = await supabase
  .rpc('search_foods', { 
    p_query: 'nutella', 
    p_limit: 20 
  });

console.log(foods); // Array di alimenti
```

### **Registra Pasto**

```typescript
const { data: entryId, error } = await supabase
  .rpc('log_meal', {
    p_entry_date: '2026-10-04',
    p_meal_slot: 'lunch',
    p_food_id: 'uuid-del-cibo',
    p_grams: 100
  });

console.log('Pasto registrato con ID:', entryId);
```

### **Ottieni Diario del Giorno**

```typescript
const { data: entries, error } = await supabase
  .rpc('get_diary_entries', { 
    p_date: '2026-10-04' 
  });

console.log(entries);
// [
//   { id: '...', meal_slot: 'breakfast', food_name: '...', kcal: 350, ... },
//   { id: '...', meal_slot: 'lunch', food_name: '...', kcal: 650, ... }
// ]
```

### **Edge Function - Cerca su OpenFoodFacts**

```typescript
const response = await fetch(
  `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/search-off`,
  {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ query: 'nutella', limit: 10 })
  }
);

const { results, error } = await response.json();
console.log(results); // Alimenti da OpenFoodFacts
```

### **Edge Function - Importa da Barcode**

```typescript
const response = await fetch(
  `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/import-off-barcode`,
  {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ barcode: '8000500037453' }) // Nutella
  }
);

const { food_id, imported } = await response.json();
console.log(`Alimento ${imported ? 'importato' : 'già esistente'} con ID:`, food_id);
```

### **Inizia Piano Macro**

```typescript
const targets = [
  { day_of_week: 1, meal_slot: 'breakfast', protein_g: 30, carbs_g: 50, fat_g: 15 },
  { day_of_week: 1, meal_slot: 'lunch', protein_g: 40, carbs_g: 70, fat_g: 20 },
  { day_of_week: 1, meal_slot: 'dinner', protein_g: 35, carbs_g: 60, fat_g: 18 },
];

const { data: planId, error } = await supabase
  .rpc('start_macro_plan', {
    p_patient_id: user.id,
    p_name: 'Piano Settimanale',
    p_targets: targets
  });
```

### **Ottieni Aderenza**

```typescript
const { data: adherence, error } = await supabase
  .rpc('get_patient_adherence', {
    p_patient_id: user.id,
    p_from: '2026-10-01',
    p_to: '2026-10-07',
    p_tolerance: 0.10 // 10% di tolleranza
  });

console.log(adherence);
// [
//   { entry_date: '2026-10-01', on_target: true, deviation_pct: 5, ... },
//   { entry_date: '2026-10-02', on_target: false, deviation_pct: 25, ... }
// ]
```

---

## 🐛 Troubleshooting

### **Errore: "relation 'foods' does not exist"**

**Soluzione:** Assicurati di aver eseguito tutte le migration in ordine:

1. Vai su SQL Editor
2. Esegui in ordine: 001 → 002 → 003 → 004 → 005 → 006 → 007 → 008 → 011 → 012

### **Errore: "type 'user_role' does not exist"**

**Soluzione:** Il tipo enum non è stato creato. Esegui:

```sql
create type public.user_role as enum ('patient', 'nutritionist', 'admin');
```

Oppure esegui la migration `001_foundation.sql`.

### **Edge Function restituisce 401 Unauthorized**

**Soluzione:** Assicurati di inviare l'header Authorization:

```typescript
headers: {
  'Authorization': `Bearer ${SUPABASE_ANON_KEY}`
}
```

### **Email non vengono inviate**

**Soluzione:** Verifica che `RESEND_API_KEY` sia configurata correttamente nelle Edge Functions Settings.

### **Push notifications non arrivano**

**Soluzione:** 
1. Verifica che `FIREBASE_SERVER_KEY` sia configurata
2. Assicurati che il dispositivo abbia registrato il token in `device_tokens`
3. Controlla i log della Edge Function `send-notification`

---

## 📞 Supporto

**Documentazione Ufficiale Supabase:**
- Auth: https://supabase.com/docs/guides/auth
- Database: https://supabase.com/docs/guides/database
- Edge Functions: https://supabase.com/docs/guides/functions
- RLS: https://supabase.com/docs/guides/auth/row-level-security

**Link Utili:**
- Dashboard DEV: https://supabase.com/dashboard/project/tcszsyzpvmsifclziujc
- Dashboard PROD: https://supabase.com/dashboard/project/ynnlfxgehbtlneiknrfr
- Repo GitHub: https://github.com/Fatto-App-Post/Nutrimind

---

## ✅ Checklist Finale

Prima di iniziare lo sviluppo frontend, verifica di avere:

- [ ] Configurato **Firebase** (FIREBASE_SERVER_KEY)
- [ ] Configurato **Resend** (RESEND_API_KEY, EMAIL_FROM)
- [ ] Verificato che le **migration** siano tutte applicate (001-012)
- [ ] Verificato che le **Edge Functions** siano deployate (7 funzioni)
- [ ] Testato **signup/login** (i trigger creano profili automaticamente)
- [ ] Testato almeno una **chiamata RPC** (es: `search_foods`)
- [ ] Testato almeno una **Edge Function** (es: `search-off`)

**Se tutto è verde, sei pronto per sviluppare! 🚀**
