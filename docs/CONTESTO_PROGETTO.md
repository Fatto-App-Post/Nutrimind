# NutriMind — contesto del progetto

Documento unico di riferimento, aggiornato al **7 ottobre 2026**. Riassume e
sostituisce i file rimossi perché obsoleti o superati dal codice:
`SETUP_COMPLETO.md`, `CONFIGURAZIONI_MANCANTI.md`, `supabase/README.md`,
`docs/API_Utenze_Frontend.md`, `docs/FRONTEND_DEVELOPER_GUIDE.md`,
`docs/FRONTEND_SUPABASE_GUIDE.md`, `docs/frontend-integration.md`,
`docs/off-integration.md`.

In caso di contrasto, **vale sempre il database reale**: lo si verifica con
`supabase/verify_frontend_contract.sql`.

---

## 1. Com'è fatta l'app

App di food tracking macro-first con due ruoli: **paziente** e
**professionista** (nutrizionista, dietista, personal trainer).

| Parte | Tecnologia | Repository |
|---|---|---|
| App mobile e web | Flutter 3.47 / Dart 3.13 | `fattoapp-post/nutrimind-frontend` |
| Database, auth, API, funzioni | Supabase (PostgreSQL 17) | `Fatto-App-Post/Nutrimind` |

**Non esiste più un backend .NET.** È stato eliminato: l'app parla
direttamente con Supabase tramite funzioni del database (RPC) e Edge
Functions. I vecchi documenti che descrivevano endpoint `/api/auth/...` o
`/api/foods/...` sono quindi superati.

| Ambiente | Project ref | Open Food Facts |
|---|---|---|
| DEV | `tcszsyzpvmsifclziujc` | `world.openfoodfacts.net` (staging, basic auth `off/off`) |
| PROD | `ynnlfxgehbtlneiknrfr` | `world.openfoodfacts.org` |

Branch di lavoro: **`claude_code`** in entrambi i repo. `develop` è il ramo
di integrazione, `main` la produzione.

---

## 2. Cosa fa l'app oggi

**Paziente** — quattro schede: Diario, Alimenti, Progressi, Profilo.
- Diario per giorno: registrazione da ricerca, codice a barre, ricette,
  pasti salvati o copia dal giorno precedente; modifica dei grammi;
  obiettivi giornalieri e per pasto presi dal piano del nutrizionista.
- Ricerca alimenti con **filtri nutrizionali** (minimo e massimo su
  proteine, carboidrati, grassi, calorie per 100 g, più ordinamento). Si
  può cercare anche con i soli filtri. Quando il catalogo locale dà pochi
  risultati, l'app interroga automaticamente il catalogo esteso.
- Alimento personale se un prodotto non esiste; preferiti; pasti salvati.
- Ricette proprie, inviate al proprio nutrizionista per la verifica.
- Progressi: aderenza, giorni registrati, serie, kcal giornaliere
  rispetto all'obiettivo, medie dei macro (7 o 30 giorni).
- "Trova un nutrizionista": vetrina dei professionisti verificati con
  ricette, piani di base, social e contatto diretto in chat.
- Chat in tempo reale, notifiche in-app e push.

**Professionista** — quattro schede: Pazienti, Messaggi, Ricette, Profilo.
- Pazienti ordinati per priorità, con aderenza, diario e commenti.
- Piani macro per paziente; commenti sul diario.
- Ricette pubblicate senza revisione (per tutti o solo per i propri
  pazienti) e coda di verifica delle ricette dei pazienti.
- Profilo pubblico (vetrina), piani alimentari "di base", codici invito.

---

## 3. Database: cose da sapere prima di scrivere codice

### Valori ammessi (enum e vincoli)

Usare valori diversi da questi fa **rifiutare la scrittura** dal database.

| Dove | Valori |
|---|---|
| `meal_slot` | `breakfast`, `morning_snack`, `lunch`, `afternoon_snack`, `dinner`, `evening_snack` — **non esiste `snack`** |
| `user_role` | `patient`, `nutritionist`, `admin` |
| `consent_scope` | `adherence`, `diary`, `profile` |
| `approval_status` | `draft`, `pending_review`, `approved`, `rejected` |
| `food_source` | `usda`, `crea`, `openfoodfacts`, `user`, `professional` — **non esiste `off`** |
| `food_verification` | `verified`, `unverified`, `rejected` |
| `notification_type` | `logging_reminder`, `new_comment`, `plan_updated`, `link_event`, `meal_review`, `system` |
| `suggested_meals.goal_tags` | `high_protein`, `low_carb`, `low_fat`, `high_fiber`, `balanced` |
| `suggested_meals.restriction_tags` | `vegetarian`, `vegan`, `gluten_free`, `lactose_free`, `nut_free`, `halal`, `kosher`, `no_pork`, `no_fish` |

Le notifiche dei messaggi in chat usano il tipo `system` con
`data.kind = 'new_message'`: aggiungere un valore a un enum richiede un
`ALTER TYPE`, che il SQL Editor non può eseguire nella stessa transazione
del resto dello script.

### Vincoli che hanno già causato errori

- `suggested_meals.title`: da 3 a 100 caratteri. `description` ≤ 2000,
  `instructions` ≤ 8000, `review_notes` ≤ 1000.
- `suggested_meals.servings`: da 1 a 50.
- `meals_reviewer_not_proposer`: chi revisiona non può essere l'autore.
  Per questo `publish_own_meal` lascia `reviewed_by` vuoto.
- `meals_approved_stamped`: una ricetta `approved` deve avere
  `reviewed_at` e `published_at` valorizzati.
- `suggested_meal_items.grams`: da 1 a 5000.
- `nutritionist_details.bio` ≤ 1000, `studio_name` ≤ 120.
- `foods`: `protein_g + carbs_g + fat_g <= 100.5`.

### Colonne calcolate dal database

- `suggested_meals.kcal_per_serving`, `protein_g_per_serving`,
  `carbs_g_per_serving`, `fat_g_per_serving` sono **generate** come
  `round(totale / servings, 2)`: **non vanno scritte**, si aggiornano da
  sole. `meal_recalc` aggiorna solo i totali.
- `foods.trust_level` è generata da `verification` e `source`.
- `foods.name_search` la riempie un trigger (nome + marca senza accenti).
- `diary_entries`: kcal e macro li calcola **sempre il trigger**
  `diary_entries_before_write` a partire dall'alimento e dai grammi. Il
  client non li invia.

### Sicurezza

- Tutte le tabelle hanno la protezione per riga (RLS) attiva. L'app usa
  solo la chiave pubblica: i permessi li applica il database.
- Le funzioni sono `security definer` e fanno i propri controlli di
  autorizzazione. Hanno `EXECUTE` solo per `authenticated`, mai per
  `anon`.
- **Attenzione**: le funzioni usate *dentro* una policy RLS
  (`can_review_meals_of`, `is_public_nutritionist`,
  `is_conversation_member`, `is_my_nutritionist`, `has_active_link`,
  `is_admin`) sono valutate come il chiamante. Se si toglie loro
  `EXECUTE`, la lettura della tabella protetta va in errore.
- Il nutrizionista vede i dati del paziente solo con un collegamento
  attivo **e** il consenso adeguato (`adherence`, `diary`, `profile`).

---

## 4. Migration

Numerate in `supabase/migrations/`, da eseguire in ordine nel SQL Editor.
Quelle da 014 in poi sono **rieseguibili** senza errori.

| File | Contenuto |
|---|---|
| 001-003b | Fondamenta: enum, utenti, collegamenti, consensi, alimenti |
| 011, 012 | Funzioni per il frontend, commenti, porzioni |
| 012_off_functions | **Non applicata e da non applicare**: faceva chiamate HTTP sincrone da Postgres |
| 013 | Catalogo alimenti normalizzato (tag, nutrienti, ingredienti, immagini) |
| 014 | Permessi delle funzioni, controlli di autorizzazione, RLS sulle tabelle usate dall'app |
| 015 | Alimenti personali del paziente, eliminazione pasti salvati |
| 016 | Ricette: visibilità, pubblicazione, revisione, salvataggio transazionale |
| 017 | Vetrina dei professionisti e piani alimentari di base |
| 018 | Chat: conversazioni, messaggi, notifiche, tempo reale |
| 019 | Ricerca alimenti per valori nutrizionali |
| 020 | Rimuove il richiamo a una funzione inesistente in `search_foods` e `get_food_by_barcode` |

**Lezione imparata:** il SQL Editor annulla l'intero script al primo
errore. Conviene tenere le migration piccole e divise per area, e
verificarle una per una.

Dopo ogni migration: eseguire `supabase/verify_frontend_contract.sql`.
Restituisce il totale dei controlli, quanti passano e il solo elenco dei
problemi. Al 7 ottobre 2026 su DEV: **107 su 107**.

---

## 5. Edge Functions

Tutte attive su DEV. Il codice sta in `supabase/functions/`.

| Funzione | A cosa serve | Note |
|---|---|---|
| `search-off` | Ricerca nel catalogo esteso | Normalizza i campi come la tabella `foods`. Usa `cgi/search.pl`: `/api/v2/search` **ignora la ricerca testuale** e restituisce prodotti casuali |
| `import-off-barcode` | Importa un prodotto per codice a barre | Scrive con privilegi di servizio dopo aver validato l'utente |
| `sync-off-batch` | Sincronizzazione in blocco (solo admin) | Mai verificata |
| `send-notification` | Push tramite Firebase | API FCM HTTP v1 con il secret `FIREBASE_SERVICE_ACCOUNT`. La vecchia API con "server key" è stata dismessa da Google a luglio 2024 |
| `send-email` | Email trasazionali | Richiede Resend, non ancora configurato |
| `generate-meal-plan` | Proposta di menu | **Da correggere**: usa il valore `snack`, che non esiste |
| `analyze-adherence` | Aderenza al piano, giorno per giorno | Riscritta: controlla consenso e usa il piano valido in ciascun giorno |

Le funzioni che l'app chiama hanno la verifica del token attiva. L'app
non chiama mai Open Food Facts direttamente.

---

## 6. Configurazione

### App (Flutter)

Le chiavi non stanno nel codice: si passano alla compilazione.

```bash
flutter run -d chrome --dart-define-from-file=env/dev.json
```

`env/dev.json` (escluso da git; il modello è `env/dev.example.json`)
contiene URL e chiave pubblica di Supabase e i valori `FIREBASE_*`.
**Mai** la chiave segreta: l'app si rifiuta di partire se la riceve.

Per il push sul web serve anche `web/firebase-config.js`.

### Firebase

Progetto `nutrimind-f9d35`; app Android `com.fattoappost.nutrimind`
(`android/app/google-services.json`). Il secret
`FIREBASE_SERVICE_ACCOUNT` è configurato su DEV.
**Google Analytics non è integrato di proposito**: in un'app con dati
sanitari richiede un consenso a parte.

### Da configurare ancora

- **Resend** per le email (`RESEND_API_KEY`, `EMAIL_FROM`).
- **Google OAuth**, opzionale.
- **Protezione password compromesse**: Authentication → Providers →
  Email. Richiede il **piano Pro**.
- **Tutto l'ambiente PROD**: migration, funzioni, secret Firebase.

---

## 7. Avvertenze di sicurezza aperte

1. **Chiavi esposte da ruotare.** Le secret key di DEV e PROD sono
   finite in chiaro nei file del repo (ora rimosse dal codice, ma
   restano nella cronologia git) e il repo è pubblico. Vanno rigenerate
   da Dashboard → Project Settings → API Keys, partendo da PROD, e
   aggiornate nei secret di GitHub Actions.
2. **Chiave privata Firebase** incollata in chat durante lo sviluppo:
   conviene generarne una nuova e sostituire il secret.
3. Non esiste un pannello admin: le verifiche professionali si approvano
   a mano con `update public.profiles set professional_verified = true
   where id = '<uuid>'`.

---

## 8. Come lavorare su questo progetto

1. **Prima di scrivere codice, guardare il database reale**, non i
   documenti: enum, vincoli e colonne generate sono la fonte di verità.
2. Ogni modifica allo schema è una **nuova migration numerata**,
   rieseguibile, piccola e di un'area sola.
3. Dopo ogni migration, eseguire lo script di verifica.
4. Nel frontend: un solo punto di accesso a Supabase
   (`lib/core/supabase.dart`), servizi in `lib/core/*_service.dart`,
   errori normalizzati in `lib/core/app_error.dart` (mai mostrare
   all'utente messaggi SQL o tecnici).
5. Controllare sempre con `flutter analyze` prima di considerare finito.
