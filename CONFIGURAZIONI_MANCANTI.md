# ⚠️ CONFIGURAZIONI MANCANTI - Da Completare

**Data:** 2026-10-04  
**Progetti:** DEV (tcszsyzpvmsifclziujc) | PROD (ynnlfxgehbtlneiknrfr)

---

## 🎯 Cosa Devi Fare ORA

Questa è la lista **completa e ordinata** di tutte le configurazioni che devi fare manualmente prima di poter usare l'app.

---

## 1️⃣ Firebase Cloud Messaging (Priorità: ALTA)

**Per cosa serve:** Notifiche push per reminder pasti, nuovi commenti, aggiornamenti piano

### **Passaggi:**

1. **Crea progetto Firebase:**
   - Vai su https://console.firebase.google.com/
   - Clicca "Add project"
   - Nome: `NutriMind`
   - Disabilita Google Analytics (opzionale)
   - Clicca "Create project"

2. **Abilita Cloud Messaging:**
   - Nella sidebar, clicca su **Build** > **Cloud Messaging**
   - Se non è già abilitato, clicca "Get started"

3. **Ottieni Server Key:**
   - Vai su **Project Settings** (ingranaggio in alto a sinistra)
   - Tab **Service accounts**
   - Clicca **Generate new private key**
   - Scarica il file JSON
   - Apri il file e copia il valore di `server_key` (è una stringa lunghissima che inizia con `AAAA...`)

4. **Configura su Supabase DEV:**
   - Vai su https://supabase.com/dashboard/project/tcszsyzpvmsifclziujc/settings/edge-functions
   - Clicca **New secret**
   - Name: `FIREBASE_SERVER_KEY`
   - Value: incolla la server key copiata prima
   - Clicca **Save secret**

5. **Configura su Supabase PROD:**
   - Vai su https://supabase.com/dashboard/project/ynnlfxgehbtlneiknrfr/settings/edge-functions
   - Ripeti lo stesso passaggio

### **Valore da Inserire:**

```env
FIREBASE_SERVER_KEY=AAAAxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx...
```

### **Come Verificare:**

```typescript
// Nel frontend, dopo aver configurato:
const response = await fetch('https://tcszsyzpvmsifclziujc.supabase.co/functions/v1/send-notification', {
  method: 'POST',
  headers: {
    'Authorization': 'Bearer YOUR_ANON_KEY',
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({
    title: 'Test',
    body: 'Se vedi questa notifica, Firebase è configurato!',
    user_id: 'tuo-user-id'
  })
});

console.log(await response.json()); // { sent: 0, message: 'No device tokens found' }
// "No device tokens found" va bene - significa che Firebase funziona!
```

### **Costo:**
- ✅ **Gratis** fino a 100 milioni di messaggi/mese

---

## 2️⃣ Resend (Priorità: MEDIA)

**Per cosa serve:** Email per inviti nutrizionisti, recovery password, conferme

### **Passaggi:**

1. **Crea account Resend:**
   - Vai su https://resend.com/
   - Clicca "Get Started" o "Sign Up"
   - Accedi con GitHub o Google (più veloce)

2. **Crea API Key:**
   - Dopo il login, vai su **API Keys** nella sidebar
   - Clicca **Create API Key**
   - Name: `NutriMind Production`
   - Permission: `Full Access`
   - Clicca **Create API Key**
   - **Copia subito la key** (inizia con `re_...`) - non la vedrai più!

3. **Configura Dominio (OPZIONALE per testing):**
   - Se vuoi usare il tuo dominio (es: `@nutrimind.app`):
     - Vai su **Domains** > **Add Domain**
     - Inserisci `nutrimind.app`
     - Segui le istruzioni per configurare i record DNS
   - **Per testing:** usa il dominio gratuito `@resend.dev`

4. **Configura su Supabase DEV:**
   - Vai su https://supabase.com/dashboard/project/tcszsyzpvmsifclziujc/settings/edge-functions
   - Crea due secrets:
     - Name: `RESEND_API_KEY`, Value: `re_xxxxxxxxxxxxxxxxxxxxx`
     - Name: `EMAIL_FROM`, Value: `NutriMind <onboarding@resend.dev>`

5. **Configura su Supabase PROD:**
   - Stessi passaggi, ma usa il dominio reale quando ce l'hai:
     - `EMAIL_FROM`: `NutriMind <noreply@nutrimind.app>`

### **Valori da Inserire:**

```env
# DEV
RESEND_API_KEY=re_xxxxxxxxxxxxxxxxxxxxx
EMAIL_FROM=NutriMind <onboarding@resend.dev>

# PROD (quando hai il dominio)
RESEND_API_KEY=re_xxxxxxxxxxxxxxxxxxxxx (stessa o diversa)
EMAIL_FROM=NutriMind <noreply@nutrimind.app>
```

### **Come Verificare:**

```typescript
const response = await fetch('https://tcszsyzpvmsifclziujc.supabase.co/functions/v1/send-email', {
  method: 'POST',
  headers: {
    'Authorization': 'Bearer YOUR_ANON_KEY',
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({
    to: 'tua-email@esempio.com',
    subject: 'Test Email',
    text: 'Se vedi questa email, Resend è configurato!'
  })
});

console.log(await response.json()); // { success: true, email_id: '...' }
```

### **Costo:**
- ✅ **Gratis:** 3,000 email/mese (100/giorno)
- 💰 **Paid:** $20/mese per 50,000 email/mese

---

## 3️⃣ Google OAuth (Priorità: BASSA - Opzionale)

**Per cosa serve:** Login con Google (opzionale, puoi usare solo email/password)

### **Passaggi:**

1. **Crea progetto Google Cloud:**
   - Vai su https://console.cloud.google.com/
   - Clicca "Select a project" > "New Project"
   - Nome: `NutriMind`
   - Clicca "Create"

2. **Configura OAuth:**
   - Vai su **APIs & Services** > **Credentials**
   - Clicca **Create Credentials** > **OAuth client ID**
   - Application type: **Web application**
   - Name: `NutriMind Web`

3. **Aggiungi Redirect URI:**
   - In **Authorized redirect URIs**, aggiungi:
     ```
     https://tcszsyzpvmsifclziujc.supabase.co/auth/v1/callback
     ```
   - Per PROD aggiungi anche:
     ```
     https://ynnlfxgehbtlneiknrfr.supabase.co/auth/v1/callback
     ```

4. **Copia le credenziali:**
   - **Client ID:** `xxxxxxxxxxxxx.apps.googleusercontent.com`
   - **Client Secret:** `GOCSPX-xxxxxxxxxxxxx`

5. **Configura su Supabase:**
   - **DEV:** https://supabase.com/dashboard/project/tcszsyzpvmsifclziujc/auth/providers
   - **PROD:** https://supabase.com/dashboard/project/ynnlfxgehbtlneiknrfr/auth/providers
   - Attiva **Google**
   - Inserisci Client ID e Client Secret
   - Clicca **Save**

### **Valori da Inserire:**

```env
# Non sono variabili ambiente, si configurano nella UI di Supabase Auth

# DEV + PROD
Google Client ID: xxxxxxxxxxxxxxx.apps.googleusercontent.com
Google Client Secret: GOCSPX-xxxxxxxxxxxxx
```

### **Come Verificare:**

```typescript
// Nel frontend dovrebbe apparire il bottone "Sign in with Google"
const { data, error } = await supabase.auth.signInWithOAuth({
  provider: 'google',
  options: {
    redirectTo: 'https://tua-app.com/auth/callback'
  }
});
```

### **Costo:**
- ✅ **Gratis**

---

## 4️⃣ Trigger Auth (Priorità: ALTA)

**Per cosa serve:** Creare automaticamente profili quando un utente si registra

### **Stato:**

- ✅ **DEV:** Trigger già creato (`handle_new_user`)
- ⏳ **PROD:** Da verificare/creare

### **Come Verificare su PROD:**

1. Vai su https://supabase.com/dashboard/project/ynnlfxgehbtlneiknrfr/sql/new
2. Esegui:

```sql
-- Verifica se il trigger esiste
SELECT * FROM pg_trigger WHERE tgname = 'on_auth_user_created';
-- Se non restituisce righe, il trigger non esiste

-- Verifica se la funzione esiste
SELECT * FROM pg_proc WHERE proname = 'handle_new_user';
-- Se non restituisce righe, la funzione non esiste
```

### **Se NON Esiste, Crealo:**

```sql
-- 1. Crea la funzione
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, role, display_name, locale)
  values (
    new.id,
    'patient',
    coalesce(split_part(new.email, '@', 1), 'Utente'),
    'it'
  );
  
  insert into public.patient_settings (user_id)
  values (new.id);
  
  return new;
end;
$$ language plpgsql security definer;

-- 2. Crea il trigger
-- NOTA: I trigger su auth.users vanno creati dalla dashboard Supabase
-- Vai su: Authentication > Users > (nessuno) > Triggers
-- Oppure contatta il supporto Supabase per crearlo
```

### **Come Testare:**

```typescript
// 1. Crea un nuovo utente
const { data, error } = await supabase.auth.signUp({
  email: 'test-' + Date.now() + '@example.com',
  password: 'password123'
});

// 2. Verifica che esista il profilo
const { data: profile } = await supabase
  .from('profiles')
  .select('*')
  .eq('id', data.user.id)
  .single();

console.log(profile); // Dovrebbe esistere!
```

---

## 5️⃣ Migration 012 su PROD (Priorità: ALTA)

**Per cosa serve:** Funzioni per commenti nutrizionisti e porzioni cibo

### **Stato:**

- ✅ **DEV:** Applicata
- ⏳ **PROD:** Da applicare

### **Come Applicare:**

1. Vai su https://supabase.com/dashboard/project/ynnlfxgehbtlneiknrfr/sql/new
2. Copia il contenuto da: https://github.com/Fatto-App-Post/Nutrimind/blob/develop/supabase/migrations/012_nuove_funzioni.sql
3. Incolla nel SQL Editor
4. Clicca **Run**

### **Come Verificare:**

```sql
-- Esegui questa query per vedere se le funzioni esistono
SELECT routine_name 
FROM information_schema.routines 
WHERE routine_schema = 'public' 
  AND routine_name IN (
    'create_nutritionist_comment',
    'get_food_portions',
    'create_food_portion'
  );
```

Se vedi le 3 funzioni, è applicata correttamente!

---

## 📋 Riepilogo Rapido

| Configurazione | DEV | PROD | Priorità |
|----------------|-----|------|----------|
| Firebase Server Key | ⏳ Da fare | ⏳ Da fare | 🔴 ALTA |
| Resend API Key | ⏳ Da fare | ⏳ Da fare | 🟡 MEDIA |
| Google OAuth | ⚪ Opzionale | ⚪ Opzionale | 🔵 BASSA |
| Trigger Auth | ✅ Fatto | ⏳ Da verificare | 🔴 ALTA |
| Migration 012 | ✅ Fatto | ⏳ Da applicare | 🔴 ALTA |

---

## 🚀 Ordine Consigliato

1. **Subito:** Applica migration 012 su PROD (5 minuti)
2. **Subito:** Verifica trigger auth su PROD (5 minuti)
3. **Oggi:** Configura Firebase (15 minuti)
4. **Oggi:** Configura Resend (10 minuti)
5. **Quando serve:** Configura Google OAuth (20 minuti)

**Tempo totale stimato:** ~1 ora

---

## ❓ Hai Bisogno di Aiuto?

Se incontri problemi:

1. **Controlla i log** su Supabase Dashboard > Logs
2. **Leggi la documentazione** nel file `SETUP_COMPLETO.md`
3. **Chiedi supporto** a Supabase: https://github.com/supabase/supabase/discussions

---

**Una volta completato tutto, il backend è 100% pronto per il frontend! 🎉**
