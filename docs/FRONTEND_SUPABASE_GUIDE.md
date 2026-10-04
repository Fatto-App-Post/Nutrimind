# NutriMind - Guida Completa per il Frontend

## Indice
1. [Setup Supabase Client](#setup-supabase-client)
2. [Autenticazione](#autenticazione)
3. [Gestione Profilo](#gestione-profilo)
4. [Alimenti e Ricerca](#alimenti-e-ricerca)
5. [Diario Alimentare](#diario-alimentare)
6. [Piani Macro](#piani-macro)
7. [Preferiti e Pasti Personali](#preferiti-e-pasti-personali)
8. [Dashboard e Aderenza](#dashboard-e-aderenza)
9. [Collegamenti e Consensi](#collegamenti-e-consensi)
10. [Notifiche](#notifiche)

---

## Setup Supabase Client

```typescript
import { createClient } from '@supabase/supabase-js'

const supabaseUrl = 'https://tcszsyzpvmsifclziujc.supabase.co'
const supabaseAnonKey = 'sb_publishable_LjiP_fxK-yrZrD_8IRW9zw_Qv9Uq_cX'

export const supabase = createClient(supabaseUrl, supabaseAnonKey)
```

---

## Autenticazione

### Registrazione

```typescript
const { data, error } = await supabase.auth.signUp({
  email: 'mario.rossi@email.com',
  password: 'PasswordSicura123!',
  options: {
    data: {
      display_name: 'Mario Rossi',
      role: 'patient' // o 'nutritionist'
    }
  }
})

if (error) throw error

// Il trigger handle_new_user crea automaticamente:
// - profilo in profiles
// - impostazioni in patient_settings O nutritionist_details
```

### Login

```typescript
const { data, error } = await supabase.auth.signInWithPassword({
  email: 'mario.rossi@email.com',
  password: 'PasswordSicura123!'
})

if (error) throw error

// data.session contiene access_token e refresh_token
// Salvali in secure storage
```

### Logout

```typescript
await supabase.auth.signOut()
```

### Recupera Utente Corrente

```typescript
const { data: { user } } = await supabase.auth.getUser()
console.log(user.email) // Email dell'utente
```

### Listener Cambiamenti Auth

```typescript
supabase.auth.onAuthStateChange((event, session) => {
  if (event === 'SIGNED_IN') {
    console.log('Utente loggato')
  }
  if (event === 'SIGNED_OUT') {
    console.log('Utente loggato out')
  }
})
```

---

## Gestione Profilo

### Recupera Profilo

```typescript
const { data: { user } } = await supabase.auth.getUser()

const { data: profile, error } = await supabase
  .from('profiles')
  .select('*')
  .eq('id', user.id)
  .single()
```

### Aggiorna Profilo

```typescript
const { error } = await supabase
  .from('profiles')
  .update({
    display_name: 'Nuovo Nome',
    locale: 'en'
  })
  .eq('id', userId)
```

### Impostazioni Paziente

```typescript
// Recupera
const { data: settings } = await supabase
  .from('patient_settings')
  .select('*')
  .eq('user_id', userId)
  .single()

// Aggiorna
const { error } = await supabase
  .from('patient_settings')
  .update({
    dietary_restrictions: ['vegetarian', 'gluten_free'],
    timezone: 'Europe/London',
    reminders_enabled: false,
    reminder_after_hours: 48
  })
  .eq('user_id', userId)
```

### Dettagli Nutrizionista

```typescript
// Recupera
const { data: details } = await supabase
  .from('nutritionist_details')
  .select('*')
  .eq('user_id', userId)
  .single()

// Aggiorna
const { error } = await supabase
  .from('nutritionist_details')
  .update({
    studio_name: 'Studio Rossi',
    bio: 'Specializzato in...'
  })
  .eq('user_id', userId)
```

### Verifica Professionale (Nutrizionisti)

```typescript
// Richiedi verifica
const { data, error } = await supabase
  .from('professional_verifications')
  .insert({
    user_id: userId,
    license_body: 'Ordine dei Biologi del Lazio',
    license_number: '12345',
    status: 'pending'
  })
  .select()
  .single()

// Controlla stato
const { data: verification } = await supabase
  .from('professional_verifications')
  .select('*')
  .eq('user_id', userId)
  .order('created_at', { ascending: false })
  .limit(1)
  .single()
```

---

## Alimenti e Ricerca

### Cerca Alimenti

```typescript
const { data: foods, error } = await supabase
  .rpc('search_foods', {
    p_query: 'pasta',
    p_limit: 20
  })
```

### Cerca per Barcode

```typescript
const { data: foods, error } = await supabase
  .rpc('get_food_by_barcode', {
    p_barcode: '8000500310427'
  })
  .single()
```

### Dettaglio Alimento

```typescript
const { data: food, error } = await supabase
  .from('foods')
  .select('*')
  .eq('id', foodId)
  .single()
```

### Crea Alimento (Solo Nutrizionisti Verificati)

```typescript
const { data, error } = await supabase
  .rpc('create_food', {
    p_name: 'Pasta al pomodoro',
    p_brand: 'Barilla',
    p_barcode: '8076809513391',
    p_kcal: 350,
    p_protein_g: 12,
    p_carbs_g: 70,
    p_fat_g: 1.5
  })
```

### Aggiorna Alimento

```typescript
const { error } = await supabase
  .rpc('update_food', {
    p_id: foodId,
    p_name: 'Nuovo nome',
    p_kcal: 360
  })
```

### Elimina Alimento (Soft Delete)

```typescript
const { error } = await supabase
  .rpc('delete_food', { p_id: foodId })
```

---

## Diario Alimentare

### Registra Pasto

```typescript
const { data, error } = await supabase
  .rpc('log_meal', {
    p_entry_date: '2026-10-04',
    p_meal_slot: 'lunch',
    p_food_id: 'uuid-alimento',
    p_grams: 100
  })
  .single()
```

### Registra Pasto Personalizzato

```typescript
const { data, error } = await supabase
  .rpc('log_meal', {
    p_entry_date: '2026-10-04',
    p_meal_slot: 'breakfast',
    p_custom_name: 'Colazione casalinga',
    p_grams: 0
  })
```

### Ottieni Entrate del Giorno

```typescript
const { data: entries, error } = await supabase
  .rpc('get_diary_entries', {
    p_date: '2026-10-04'
  })
```

### Elimina Voce dal Diario

```typescript
const { error } = await supabase
  .rpc('delete_diary_entry', { p_entry_id: entryId })
```

---

## Piani Macro

### Inizia Nuovo Piano

```typescript
const { data, error } = await supabase
  .rpc('start_macro_plan', {
    p_patient_id: userId,
    p_name: 'Piano Autunno',
    p_valid_from: '2026-10-04',
    p_targets: [
      {
        day_of_week: 1, // Lunedì
        meal_slot: 'breakfast',
        protein_g: 20,
        carbs_g: 50,
        fat_g: 10
      },
      {
        day_of_week: null, // Tutti i giorni
        meal_slot: 'lunch',
        protein_g: 30,
        carbs_g: 70,
        fat_g: 15
      }
    ]
  })
  .single()
```

### Ottieni Piano Corrente

```typescript
const { data: plan, error } = await supabase
  .rpc('get_current_macro_plan')
  .single()

// Ottieni target del piano
const { data: targets } = await supabase
  .from('macro_plan_targets')
  .select('*')
  .eq('plan_id', plan.id)
```

---

## Preferiti e Pasti Personali

### Aggiungi ai Preferiti

```typescript
const { data, error } = await supabase
  .rpc('add_favorite_food', {
    p_food_id: foodId,
    p_default_grams: 100,
    p_default_slot: 'lunch'
  })
  .single()
```

### Ottieni Preferiti

```typescript
const { data: favorites, error } = await supabase
  .rpc('get_favorite_foods')
```

### Crea Pasto Personale

```typescript
const { data, error } = await supabase
  .rpc('create_personal_meal', {
    p_name: 'Pasta e fagioli',
    p_default_slot: 'lunch',
    p_items: [
      { food_id: 'uuid-pasta', grams: 80 },
      { food_id: 'uuid-fagioli', grams: 150 }
    ]
  })
  .single()
```

### Registra Pasto Personale nel Diario

```typescript
const { data, error } = await supabase
  .rpc('log_personal_meal', {
    p_meal_id: mealId,
    p_date: '2026-10-04',
    p_slot: 'lunch'
  })
```

---

## Dashboard e Aderenza

### Aderenza Paziente (Giorno per Giorno)

```typescript
const { data: adherence, error } = await supabase
  .rpc('get_patient_adherence', {
    p_patient_id: userId,
    p_from: '2026-10-01',
    p_to: '2026-10-07',
    p_tolerance: 0.10 // 10% tolleranza
  })

// Ritorna: { day, has_plan, logged, entries, proteing, carbsg, fatg, ... }
```

### Miei Pazienti (Per Nutrizionisti)

```typescript
const { data: patients, error } = await supabase
  .rpc('get_my_patients')

// Ritorna lista pazienti con:
// - display_name
// - attention_score (più alto = più bisogno di attenzione)
// - days_logged_last_7
// - shares_adherence (true se ha concesso consenso)
```

---

## Collegamenti e Consensi

### Nutrizionista: Crea Invito

```typescript
const { data, error } = await supabase
  .rpc('create_invitation')

const invitationCode = data // es: "ABC123XYZ9"
// Valido per 7 giorni
```

### Paziente: Riscatta Invito

```typescript
const { data, error } = await supabase
  .rpc('redeem_invitation', {
    p_code: 'ABC123XYZ9',
    p_scopes: ['adherence', 'diary'], // Cosa concedi
    p_policy_version: '1.0'
  })
  .single()

// data.linkId = ID del collegamento creato
```

### Interrompi Collegamento

```typescript
const { error } = await supabase
  .rpc('revoke_link', { p_link_id: linkId })
```

### Concedi Consenso

```typescript
const { error } = await supabase
  .rpc('grant_consent', {
    p_link_id: linkId,
    p_scope: 'diary', // o 'adherence' o 'profile'
    p_policy_version: '1.0'
  })
```

### Revoca Consenso

```typescript
const { error } = await supabase
  .rpc('revoke_consent', {
    p_link_id: linkId,
    p_scope: 'diary'
  })
```

---

## Notifiche

### Ottieni Notifiche Non Lette

```typescript
const { data: notifications, error } = await supabase
  .rpc('get_unread_notifications')
```

### Segna Come Letta

```typescript
const { error } = await supabase
  .rpc('mark_notification_read', { p_notification_id: notificationId })
```

---

## Realtime Subscriptions

### Iscriviti a Cambiamenti Diario

```typescript
const channel = supabase
  .channel('diary-changes')
  .on(
    'postgres_changes',
    {
      event: '*',
      schema: 'public',
      table: 'diary_entries',
      filter: `patient_id=eq.${userId}`
    },
    (payload) => {
      console.log('Diario modificato:', payload)
      // Aggiorna UI
    }
  )
  .subscribe()
```

### Iscriviti a Nuove Notifiche

```typescript
const channel = supabase
  .channel('notifications')
  .on(
    'postgres_changes',
    {
      event: 'INSERT',
      schema: 'public',
      table: 'notifications',
      filter: `user_id=eq.${userId}`
    },
    (payload) => {
      // Mostra notifica push
      showNotification(payload.new)
    }
  )
  .subscribe()
```

---

## Error Handling

```typescript
const { data, error } = await supabase
  .rpc('search_foods', { p_query: 'pasta' })

if (error) {
  if (error.code === 'PGRST116') {
    console.log('Nessun risultato trovato')
  }
  if (error.code === '42501') {
    console.log('Permesso negato')
  }
  if (error.code === 'P0002') {
    console.log('Risorsa non trovata')
  }
  throw error
}
```

---

## Best Practices

1. **Usa sempre RPC per operazioni complesse** - Le funzioni gestiscono permessi e logica
2. **RLS è tuo amico** - Gli utenti vedono solo i loro dati
3. **Cache le ricerche OFF** - La Edge Function fa cache automatico
4. **Usa realtime per aggiornamenti live** - Diario, notifiche, aderenza
5. **Gestisci i token in secure storage** - Non salvarli in localStorage in produzione

---

## Esempio Completo: Flusso Pasto

```typescript
// 1. Cerca alimento
const { data: foods } = await supabase
  .rpc('search_foods', { p_query: 'pasta', p_limit: 5 })

// 2. Aggiungi ai preferiti
await supabase.rpc('add_favorite_food', { 
  p_food_id: foods[0].id,
  p_default_grams: 100 
})

// 3. Registra nel diario
const { data: entry } = await supabase
  .rpc('log_meal', {
    p_entry_date: new Date().toISOString().split('T')[0],
    p_meal_slot: 'lunch',
    p_food_id: foods[0].id,
    p_grams: 100
  })
  .single()

// 4. Ottieni aderenza aggiornata
const { data: adherence } = await supabase
  .rpc('get_patient_adherence', {
    p_patient_id: userId,
    p_from: new Date().toISOString().split('T')[0],
    p_to: new Date().toISOString().split('T')[0]
  })
```

---

## Note Importanti

- **Email utente**: Usa `supabase.auth.getUser().email`, non è in `profiles`
- **Trigger automatici**: Alla registrazione, `handle_new_user` crea profilo e impostazioni
- **Service role key**: Mai usarla nel frontend! Solo nelle Edge Functions
- **Barcode search**: Se non trovato nel DB, chiama automaticamente OpenFoodFacts

---

## Deploy Edge Functions

Per deployare le Edge Functions:

```bash
# Installa Supabase CLI
npm install -g supabase

# Login
supabase login

# Link al progetto
supabase link --project-ref tcszsyzpvmsifclziujc

# Deploy
supabase functions deploy search-off
```

---

Hai tutto il necessario per integrare il frontend! 🚀
