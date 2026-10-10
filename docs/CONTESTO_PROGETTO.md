# NutriMind — contesto del progetto

Documento unico di riferimento, aggiornato al **10 ottobre 2026**. Riassume e
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
  risultati, l'app interroga automaticamente il catalogo esteso. Dalla
  migration 022 la ricerca tollera gli errori di battitura. C'è una sola
  schermata di ricerca in tutta l'app (`search_food_screen.dart`): la usa
  sia il diario sia la scheda Catalogo.
- Alimento personale se un prodotto non esiste; preferiti; pasti salvati.
- Ricette proprie, inviate al proprio nutrizionista per la verifica.
- **Autogestione**: chi non ha un professionista collegato si imposta da
  solo gli obiettivi, dallo stesso editor che usa il professionista. Con
  un collegamento attivo il piano torna in mano a lui e il database
  rifiuta la scrittura del paziente (`plan_managed_by_nutritionist`):
  altrimenti l'aderenza calcolata sul piano non vorrebbe dire niente.
- Progressi: aderenza, giorni registrati, serie, kcal giornaliere
  rispetto all'obiettivo, medie dei macro (7 o 30 giorni).
- "Trova un nutrizionista": vetrina dei professionisti verificati con
  ricette, piani di base, social e contatto diretto in chat.
- Chat in tempo reale, notifiche in-app e push.

**Professionista** — quattro schede: Pazienti, Messaggi, Ricette, Profilo.
- Pazienti ordinati per priorità, con aderenza, diario e commenti.
- Piani macro per paziente: si parte da calorie e ripartizione dei macro,
  si correggono i grammi pasto per pasto e si scrivono le **istruzioni**
  su come seguirli (il paziente le legge nel diario, sopra gli
  obiettivi).
- **Consigli mirati**: una ricetta o un alimento scelti per *quel*
  paziente, con una nota. Il paziente li trova in "Consigliati per te"
  quando aggiunge un pasto. Restano distinti dalle ricette pubblicate,
  che valgono per tutti.
- Con il ruolo `admin`: quadro generale (cosa aspetta una decisione e i
  numeri del progetto), abilitazioni professionali, coda degli alimenti
  da verificare. La coda degli alimenti la vede anche un professionista
  verificato, ma non vi trova i propri: `review_food` non glielo
  consente.
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
- `macro_plan_targets.kcal_estimated` è **generata** come
  `protein_g*4 + carbs_g*4 + fat_g*9`: non va scritta. La 023 lo faceva
  e nessun piano macro si poteva salvare (428C9); corretto dalla 026.
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
| 021 | Il ruolo scelto alla registrazione finisce nel profilo; crea i profili mancanti |
| 022 | Ricerca alimenti per somiglianza (pg_trgm) e ordinata per pertinenza |
| 023 | Piani con istruzioni, autogestione del paziente, consigli mirati a un singolo paziente |
| 024 | Approvazione delle verifiche professionali dall'app, senza SQL |
| 025 | Coda degli alimenti da verificare, quadro per l'amministratore, esportazione dati completa |
| 026 | Correzione della 023: `kcal_estimated` è generata e non va scritta |

**Lezione imparata:** il SQL Editor annulla l'intero script al primo
errore. Conviene tenere le migration piccole e divise per area, e
verificarle una per una.

Dopo ogni migration: eseguire `supabase/verify_frontend_contract.sql`.
Restituisce il totale dei controlli, quanti passano e il solo elenco dei
problemi. Lo script copre **112** controlli; con le migration fino alla
020 applicate ne passano 109, e i tre che restano sono esattamente
quelli che sistemano la 021 e la 022.

---

## 5. Edge Functions

Tutte attive su DEV. Il codice sta in `supabase/functions/`.

| Funzione | A cosa serve | Note |
|---|---|---|
| `search-off` | Ricerca nel catalogo esteso | Normalizza i campi come la tabella `foods`. Usa `cgi/search.pl`: `/api/v2/search` **ignora la ricerca testuale** e restituisce prodotti casuali |
| `import-off-barcode` | Importa un prodotto per codice a barre | Scrive con privilegi di servizio dopo aver validato l'utente. Preferisce i campi italiani e traduce gli allergeni dai tag |
| `sync-off-batch` | Sincronizzazione in blocco (solo admin, o job con chiave di servizio) | Riscritta: scriveva un valore di `source` inesistente e marcava gli import come verificati. Mai usata finora |
| `send-notification` | Push tramite Firebase | API FCM HTTP v1 con il secret `FIREBASE_SERVICE_ACCOUNT`. La vecchia API con "server key" è stata dismessa da Google a luglio 2024 |
| `send-email` | Email trasazionali | Richiede Resend, non ancora configurato |
| `generate-meal-plan` | Proposta di menu | Funziona ma propone alimenti sfusi, non ricette; l'app non la usa |
| `analyze-adherence` | Aderenza al piano, giorno per giorno | Riscritta: controlla consenso e usa il piano valido in ciascun giorno |

Le funzioni che l'app chiama hanno la verifica del token attiva. L'app
non chiama mai Open Food Facts direttamente.

---

## 6. Configurazione

### App (Flutter)

Le chiavi non stanno nel codice: si passano alla compilazione.

`env/dev.json` (escluso da git; il modello è `env/dev.example.json`)
contiene URL e chiave pubblica di Supabase e i valori `FIREBASE_*`.
**Mai** la chiave segreta: l'app si rifiuta di partire se la riceve.

Per il push sul web serve anche `web/firebase-config.js`.

### Come si avvia l'app: tre modi diversi

Sono stati misurati tutti e tre il 10 ottobre su questa macchina.

**1. In Chrome, con hot reload** — il modo normale per sviluppare:

```bash
flutter run -d chrome --dart-define-from-file=env/dev.json
```

Due cose da sapere, perché generano confusione. Primo: è **lento**, e il
tempo sta tutto in "Waiting for connection from debug service on
Chrome" — 103 secondi a cache fredda (dopo un `pub get`), 33 a cache
calda. Non è bloccato, sta compilando l'app in JavaScript; va aspettato.
Secondo: **non stampa nessun indirizzo dell'app.** Apre da sé una
finestra di Chrome e gli unici URL che scrive a terminale sono quelli del
debug service e di DevTools (`127.0.0.1:<porta casuale>`). Aprirli
pensando di trovare l'app non porta all'app, e se si chiude la finestra
che ha aperto Flutter non c'è nessun indirizzo a cui tornare.

**2. Come server, con un indirizzo stabile** — quando si vuole solo
usare l'app, aprirla in un browser a scelta, riaprirla più volte:

```bash
flutter run -d web-server --web-port=8080 --dart-define-from-file=env/dev.json
```

Scrive `lib\main.dart is being served at http://localhost:8080`.
**Attenzione all'indirizzo:** il dev server si lega al solo loopback
**IPv6**, cioè `[::1]:8080`. Verificato con tre richieste:
`http://localhost:8080` risponde 200, `http://[::1]:8080` risponde 200,
`http://127.0.0.1:8080` **non si connette**. Chi usa `127.0.0.1` per
abitudine non ottiene un errore che spieghi il motivo, solo una
connessione che non va. Per avere anche IPv4 serve
`--web-hostname=127.0.0.1`; per raggiungere l'app dal telefono sulla
stessa rete, `--web-hostname=0.0.0.0`, ricordando che così la si espone
a tutta la rete locale.

**3. Compilata, servita da un file server** — è quello che usa
l'anteprima dentro Claude Code (`.claude/launch.json`, porta 8090):

```bash
flutter build web --dart-define-from-file=env/dev.json
npx -y http-server build/web -p 8090 -c-1
```

La compilazione richiede circa 85 secondi e il risultato è statico: non
c'è hot reload, ogni modifica va ricompilata. In compenso l'indirizzo è
stabile e non dipende da un processo `flutter` in ascolto. Nota: quel
server vive quanto la sessione che lo ha avviato — a sessione chiusa su
`localhost:8090` non risponde più niente.

Per i test automatici del browser va aggiunto un define:

```bash
flutter build web --dart-define-from-file=env/dev.json --dart-define=ENABLE_SEMANTICS=true
```

`ENABLE_SEMANTICS` tiene acceso l'albero di accessibilità, che Flutter
sul web costruisce solo dopo che l'utente ha premuto il pulsante
nascosto "Enable accessibility". Serve ai test automatici del browser:
senza di esso la pagina è una sola tela e non si può né leggere né
toccare niente. **Non va usato in produzione**: tenere l'albero
aggiornato ha un costo.

### Cosa si riesce a compilare su questa macchina

`flutter doctor` al 10 ottobre: **l'unico bersaglio che compila è il
web.** Tre cose mancano, indipendenti fra loro:

- **SDK Android assente**: niente build Android, né emulatore né
  dispositivo. È la più importante, perché la fotocamera per il codice a
  barre non si può provare sul web di un portatile.
- **Visual Studio senza il carico "Desktop development with C++"**
  (mancano MSVC v142, CMake per Windows, Windows 10 SDK): niente build
  Windows desktop, anche se il dispositivo compare in `flutter devices`.
- **Developer Mode di Windows disattivo**, quindi niente symlink.
  `flutter pub get` lo segnala da sé: *"Building with plugins requires
  symlink support"*. Si attiva con `start ms-settings:developers` e
  serve a qualunque build nativa con plugin.

Il risultato pratico è che `flutter run` senza `-d` offre anche Windows
fra i dispositivi, ma scegliendolo la build fallisce. Finché le tre cose
sopra restano così, va indicato sempre un bersaglio web (`-d chrome` o
`-d web-server`).

### Dipendenze

Aggiornate il 10 ottobre con `flutter pub upgrade` (13 pacchetti erano
fermi al `pubspec.lock`, non ai vincoli) e un solo cambio di vincolo a
mano, `cupertino_icons` da `^1.0.8` a `^2.0.0`: è un major, ma la classe
`CupertinoIcons` non è usata da nessuna parte nel codice, quindi non
tocca niente. Dopo l'aggiornamento: analyzer pulito, 40 test verdi,
build web e avvio verificati.

Due pacchetti restano indietro e **non si possono aggiornare**:
`material_color_utilities` e `test_api` sono fissati dall'SDK Flutter
(`flutter pub outdated` li segna non risolvibili). Si muovono solo
aggiornando Flutter, che oggi è 3.47.6 con una versione più recente
disponibile. È un aggiornamento da fare a parte, non insieme ad altro.

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
3. Promuovere un professionista ad `admin` gli svuota la lista pazienti:
   `my_patients_overview` esce subito se il ruolo non è `nutritionist`.
   Il collegamento resta nel database. Meglio tenere i due ruoli su
   utenze separate.
4. Le verifiche professionali si approvano dall'app (migration 024), ma
   **il primo amministratore lo si nomina a mano**, ed è giusto che resti
   l'unica cosa fuori dall'app:

   ```sql
   update public.profiles set role = 'admin'
    where id = (select id from auth.users where email = 'tu@esempio.it');
   ```

---

## 7bis. Due cose da sapere sullo stato dei dati

- **Il catalogo alimenti è praticamente vuoto.** Su DEV `public.foods`
  conteneva zero righe: ogni ricerca finiva sul catalogo esteso e la
  ricerca per valori nutrizionali non poteva restituire niente. Vedere
  il punto 2.1 di [PROSSIMI_PASSI.md](PROSSIMI_PASSI.md).
- **Tema chiaro o scuro, scelto dall'utente** col pulsante sole/luna nel
  profilo (prima metà app era chiara e metà scura). La tavolozza sta solo
  in `core/theme.dart` — `lightPalette` e `darkPalette` — e la scelta si
  salva sul dispositivo. Due regole da rispettare scrivendo schermate:
  1. i colori si leggono **dentro** `build`, mai salvati in un campo
     dello `State`;
  2. ogni `build` che li usa chiama `context.watchTheme()` come prima
     istruzione. Senza, al cambio di tema quella schermata resta dei
     colori vecchi: Flutter salta la ricostruzione di un widget quando il
     genitore gli passa la stessa istanza `const`, e la dipendenza
     esplicita dal tema è l'unico modo per aggirare la cosa.

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
5. Controllare sempre con `flutter analyze` e `flutter test` prima di
   considerare finito. I test stanno in `nutrimind-frontend/test/` e
   servono soprattutto a tenere i modelli allineati agli enum e ai
   vincoli del database.
6. La CI dei due repository fa questo:
   - backend: `node scripts/check-sql.mjs` (parser di PostgreSQL su ogni
     `.sql`) e `node scripts/check-functions.mjs` (esbuild su ogni Edge
     Function). Si possono eseguire anche a mano.
   - frontend: `flutter analyze`, `flutter test`, compilazione web con
     `env/dev.example.json`.
7. **Si può verificare una funzione SQL senza applicarla**: basta
   riscriverne il corpo come `SELECT` con i parametri come letterali ed
   eseguirlo in sola lettura. È così che si è controllata la 022 prima
   di consegnarla.
