# NutriMind — prossimi passi

Aggiornato al **13 ottobre 2026**. A questo punto i tre ruoli — paziente,
professionista, amministratore — sono stati percorsi tutti a schermo.
Per lo stato e i vincoli del database vedere
[CONTESTO_PROGETTO.md](CONTESTO_PROGETTO.md).

Legenda impegno: **S** poche ore · **M** 1-2 giorni · **L** più giorni.

---

## 0. Cosa è stato provato davvero

**Come paziente** (prima che l'utenza diventasse professionista):
accesso, diario, ricerca testuale, passaggio al catalogo esteso, import
del prodotto, dettaglio con tabella nutrizionale, aggiunta al diario con
ricalcolo dei macro, import di un codice a barre digitato, ricerca per
soli valori nutrizionali, Progressi, Profilo, vetrina e chat.

**Come professionista**: le quattro schede si aprono e il profilo mostra
vetrina, piani di base, ricette e inviti. Il tema chiaro/scuro cambia su
tutte le schermate, comprese quelle aperte sopra le altre.

**Percorso completo fra i due ruoli**, con le utenze del punto 1.2:
invito generato, riscattato con i tre consensi, paziente che compare
nella lista del professionista; piano macro con obiettivi per pasto e
istruzioni; consiglio mirato su un alimento con nota. Dal lato paziente,
sullo schermo:

- giornata `236 / 2054 kcal`, `P 2/145 g`, `C 5/220 g`, `G 23/66 g`;
- `Piano "Ricomposizione · ottobre" del nutrizionista` con le istruzioni
  sotto, dove il paziente guarda i numeri ogni giorno;
- colazione `P 2/30 g · C 5/55 g · G 23/12 g`, `236 / 448 kcal`,
  `-212 kcal`; i pasti ancora vuoti mostrano il proprio obiettivo
  (`Obiettivo: P 45 · C 80 · G 20 g`) invece di "Nessun alimento";
- `Consigliati per te` con l'alimento, l'autore e la nota;
- campanella con il contatore delle notifiche a 1.

**Come amministratore** (`nutri.prova` promosso a `admin`): il quadro
generale conta le decisioni in attesa e fa scattare i due avvisi sui
numeri ("nessuno si è reso visibile", "catalogo molto piccolo"); la coda
degli alimenti mostra i due alimenti scritti dal paziente e segnala da sé
l'incoerenza (*"Le calorie dichiarate (90) non tornano con i macro (480
kcal)"*). Verificato uno e rifiutato l'altro: nel database il primo passa
a `verified` con `trust_level` da 1 a 2, `verified_by` e `verified_at`
valorizzati; il secondo a `rejected`, `trust_level` 0. `review_food`
esisteva dalla prima migration e questa è la prima volta che viene
eseguita.

**Non provato cliccando**: le notifiche push, che non partono ancora
(punto 2.2), e Android e iOS, mai compilati (manca l'SDK Android in
locale).

**Un effetto da tenere a mente**: promuovere un professionista ad `admin`
gli svuota la lista pazienti, perché `get_my_patients` filtra per ruolo.
Il collegamento resta nel database, ma non si vede più. Se un
amministratore deve anche seguire pazienti, va deciso come trattare il
caso; per ora conviene tenere i due ruoli su utenze separate.

---

## Difetti trovati e corretti il 13 ottobre

Tutti verificati a schermo, tranne dove indicato.

- **Ricollegarsi con un codice già usato diceva "Collegamento creato"
  senza collegare niente.** `redeem_invitation` restituisce `null` — non
  un errore — quando il codice è sbagliato, scaduto o **già consumato**,
  e lo fa di proposito: prima registra il tentativo fallito, e un
  `raise` annullerebbe anche quella scrittura, cioè il conteggio che
  protegge dai tentativi a raffica. Il client non guardava il valore di
  ritorno. Corretto nel servizio, così valgono tutti i chiamanti.
- **L'editor degli obiettivi si piantava.** Ogni casella era
  identificata da una `ValueKey` che conteneva *il valore digitato nella
  casella stessa*: a ogni carattere la chiave cambiava e Flutter
  distruggeva e ricreava il campo con un controller nuovo. Diciotto
  caselle sulla stessa schermata. Ora i controller sono persistenti.
- **Nel tema chiaro molti testi erano invisibili.** Erano scritti
  `Colors.white` perché l'app è nata solo scura. Non c'era nessun
  gradiente sotto, come si era creduto: il diario è `bgColor` e
  `cardColor`. Invisibili: il saluto, "Macros di oggi", i grammi dei
  macro, "I tuoi pasti", i titoli dei pasti, le icone di chat e
  notifiche, il nome e le calorie di ogni alimento registrato, il
  titolo e il campo del dialogo di modifica, **il testo che si digita
  nella ricerca**, il titolo di **ogni risultato di ricerca**, la
  freccia indietro e il titolo della schermata di ricerca, il titolo e i
  campi dei filtri nutrizionali. Più tre superfici chiare fisse che nel
  tema scuro facevano il danno opposto, ora `tealSoft`.
- **I grammi si muovevano solo di dieci in dieci** e il minimo era 10,
  mentre il database ammette da 1 a 10000
  (`diary_entries_grams_check`): cinque grammi di olio non si potevano
  registrare. Ora il numero si tocca e si scrive.
- **Gli alimenti personali di chiunque uscivano nelle ricerche di
  tutti** (migration 027, punto 1.1).
- **I due controlli della CI del backend non funzionavano** (vedi
  CONTESTO_PROGETTO.md, punto 7 di "Come lavorare"). Ora girano: 24/24
  file SQL e 7/7 Edge Functions.
- **Gli errori ora si fermano in una finestra** invece di passare in uno
  snackbar: 39 punti convertiti.
- **L'intestazione del diario sforava** su schermi stretti: il nome
  dell'utente stava in un `Row` senza `Expanded`. Cercati gli altri casi
  dello stesso tipo in tutta l'app: non ce ne sono con testo scritto
  dall'utente.

**Non verificato cliccando:** il nuovo flusso del codice a barre. Serve
una fotocamera, che nell'anteprima web del portatile non c'è; la logica
di ricerca sotto (`get_food_by_barcode` poi import da Open Food Facts)
è invece la stessa di prima e quella è provata.

---

## Da dove ripartire

Prima di tutto: **applicare la 027 e la 028** (punto 1.1), e
**ripubblicare le tre funzioni di Open Food Facts** — `import-off-barcode`,
`search-off`, `sync-off-batch` — senza cui le immagini non si salvano.

Poi c'è un programma nuovo, chiesto il 13 ottobre, descritto alla
sezione 8: utenti base, scheda Community, commenti alle ricette, foto e
video delle ricette. È la cosa più grossa mai aggiunta all'app in un
colpo e cambia la barra di navigazione, quindi conviene farla a pezzi
nell'ordine indicato lì.

Le altre cose ferme non sono difetti, sono pezzi che mancano. In ordine
di quanto pesano:

1. **Il catalogo alimenti è quasi vuoto** (punto 2.1): quattro righe. È
   il collo di bottiglia di tutto il resto — ricerca per valori
   nutrizionali, ricette composte, consigli mirati. Richiede una
   decisione sulla fonte, non solo del codice. **Nota nuova:** adesso
   che gli alimenti hanno un'immagine, un catalogo importato da CREA o
   USDA arriverebbe *senza foto*, perché quelle tabelle non ne hanno.
   Gli alimenti sfusi (pasta, riso, pollo) non hanno una confezione da
   fotografare, quindi per loro il segnaposto è la cosa giusta e non un
   ripiego: non è una ragione per preferire l'import da codici a barre.
2. **Le notifiche push non partono** (punto 2.2): il database le crea e
   nessuno le inoltra. Serve attivare i Webhooks dalla dashboard, poi è
   mezz'ora di lavoro.
3. **Android e iOS non sono mai stati compilati.** Guardando
   `flutter doctor` il 10 ottobre, non è una cosa sola ma tre, tutte da
   fare prima di vedere l'app su un telefono: manca l'**SDK Android**;
   manca il carico **"Desktop development with C++"** di Visual Studio
   (che serve al bersaglio Windows, non ad Android, ma è l'altra ragione
   per cui oggi compila solo il web); ed è disattivo il **Developer Mode
   di Windows**, senza cui non c'è supporto per i symlink e nessuna build
   con plugin passa — `flutter pub get` lo dice già a ogni esecuzione.
   Finché resta solo il web, un'app di food tracking non si può provare
   davvero: la fotocamera per il codice a barre è il suo gesto
   principale. Dettagli in [CONTESTO_PROGETTO.md](CONTESTO_PROGETTO.md),
   "Cosa si riesce a compilare su questa macchina".
4. **`flutter drive` con `integration_test`** (punto 1.3): renderebbe
   ripetibile tutto quello che oggi si prova a mano, e tolgo di mezzo gli
   eventi sintetici.

Il resto (menu della settimana, foto, lista della spesa, peso) sono
funzioni nuove: valgono dopo che il catalogo c'è.

---

## 1. Da applicare (serve un tuo passaggio)

### 1.0 Sui freeze durante le prove — risposta

Domanda del 13 ottobre: *«la navigazione fra elementi continua a dare
problemi di freeze: è un problema del localhost o le schede non sono
reattive?»* Misurato, sono **due cose diverse e nessuna delle due è la
barra di navigazione**.

1. **Un difetto vero, ora corretto**, ma in un punto solo: l'editor
   degli obiettivi. Ogni casella era identificata da una `ValueKey` che
   conteneva il valore digitato nella casella stessa, quindi a ogni
   tasto Flutter buttava via il campo e lo ricreava. Diciotto caselle
   sulla stessa schermata: quello si piantava davvero.
2. **Il resto è il modo in cui si prova l'app, non l'app.** Sul web la
   build di *debug* carica l'applicazione come ~**978 moduli JavaScript
   separati** (si legge nella console: `DDC is about to load 978/978
   scripts`) e fa passare ogni fotogramma per il compilatore di
   sviluppo. È lenta di natura, dieci volte e più della build di
   release. Nella build servita a `localhost:8090` la navigazione fra
   le schede è immediata: provate a mano Diario → Alimenti → ricerca →
   dettaglio → Profilo, nessuna attesa.

La barra e lo shell sono stati letti: `CustomBottomNav` cambia solo un
indice (`tab?.value = index`), nessun push di route, e `PatientShell`
tiene le quattro schede in un `IndexedStack`, quindi cambiare scheda non
ricostruisce niente e non ricarica nulla da zero. Strutturalmente non
c'è niente da sistemare.

**Come provare la velocità vera:** `flutter build web` e servire
`build/web` (vedi CONTESTO_PROGETTO.md, "Come si avvia l'app", modo 3).
Con `flutter run -d chrome` si misura il compilatore, non l'app.

Resta un dubbio che si chiarirà solo su un telefono: sul web ogni
`setState` ridisegna su tela, e su un dispositivo lento certe schermate
possono restare pesanti. Ma è un discorso che ha senso aprire dopo aver
compilato per Android, non adesso (punto 3 di "Da dove ripartire").

### 1.1 Da applicare: la 027
Da 014 a 026 sono applicate. **La 027 no**, ed è la più importante delle
ultime: `search_foods` e `get_food_by_barcode` leggevano `public.foods`
senza distinguere il catalogo dagli **alimenti personali**, quindi
cercando una parola qualsiasi si ottenevano quelli di chiunque, col nome
che l'autore ha scelto. Per il codice a barre non serviva nemmeno
indovinare un identificativo: i codici stanno stampati sulle confezioni.
E siccome `get_food_by_barcode` non aveva né ordine né limite e il client
prende il primo risultato, il primo alimento personale con un codice
vero sarebbe diventato la risposta di tutti per quel prodotto, al posto
della voce verificata — proprio quello che crea il percorso
"Inseriscilo tu" dello scanner.

Trovata controllando una per una le 68 RPC esposte: cinque non facevano
nessun controllo, tre a ragione, due no.

**E la 028**, che aggiunge a `foods` le due colonne per le immagini.
Insieme alla migration vanno **ripubblicate tre Edge Functions**:
`import-off-barcode` e `sync-off-batch` (salvano e riaggiornano
l'immagine) e `search-off` (la restituisce con i nomi nuovi). Senza la
migration le funzioni non possono scrivere quelle colonne; senza le
funzioni la migration resta vuota. Nell'app il codice c'è già e si
arrangia: dove l'immagine manca disegna un segnaposto.

Dopo ogni migration conviene eseguire
`supabase/verify_frontend_contract.sql`: lo script ora controlla anche le
colonne generate delle due tabelle su cui ci siamo sbagliati, perché è
un errore che si vede solo a runtime, quando qualcuno prova a salvare.

### 1.2 Utenze di prova su DEV
Le due password fornite non funzionavano (400 da
`/auth/v1/token?grant_type=password`), così le utenze di prova sono state
create dalla registrazione pubblica dell'app. **Da cancellare prima di
andare in produzione.**

| Utenza | Ruolo | Password |
|---|---|---|
| `paziente.prova@example.com` | paziente | `NutriMind2026!` |
| `nutri.prova@example.com` | professionista (non abilitato) | `NutriMind2026!` |

Sono collegate fra loro (invito riscattato con i tre consensi) e il
professionista ha già mandato un consiglio mirato al paziente. Il domìnio
`example.com` è riservato dalla RFC 2606 e non riceve posta: sono utenze
che non possono recuperare la password, e va bene così su DEV.

Nota: su questo progetto la conferma via email è **disattivata**, quindi
chi si registra entra subito. In produzione va riattivata.

### 1.3 Automazione dell'interfaccia: limite noto
Le prove cliccando passano per eventi sintetici sull'albero di
accessibilità. Funzionano su `FilledButton`, `IconButton`, `ListTile` e
`InkWell` di prima generazione, **non** su `TextButton` e sulle schede
dei pasti: lì l'evento arriva ma il gesto non viene riconosciuto. Per
quei percorsi si verificano le RPC con la sessione dell'utente (è la
stessa chiamata che fa l'app) e si guarda il risultato a schermo.

Un `flutter drive` con `integration_test` risolverebbe alla radice:
guida l'app dall'interno, senza eventi sintetici. È il modo giusto di
rendere ripetibili queste prove.

---

## 2. Cose rotte o incomplete

### 2.1 Il catalogo alimenti è quasi vuoto — **M**
`public.foods` aveva zero righe; ora ci sono i due prodotti importati
durante le prove. Mancano gli alimenti sfusi (pasta, riso, pollo, uova,
olio), che nel catalogo esterno non esistono come voci generiche
affidabili. Senza di loro la ricerca per valori nutrizionali ha poco da
filtrare e le ricette sono difficili da comporre.

Due strade, in ordine di preferenza:
1. **importare una tabella di riferimento** (CREA per l'Italia, USDA
   FoodData Central): sono i valori che `trust_level` considera di
   livello 3. Serve una funzione di import e, per USDA, una chiave API;
2. **precaricare i prodotti confezionati più comuni** inserendo i codici
   a barre in `food_off_sync_log` ed eseguendo `sync-off-batch`, che non
   è mai stata usata.

Non conviene scrivere a mano i valori nutrizionali: la provenienza del
dato è parte del dato, e `trust_level` la deduce da `source` e
`verification`.

### 2.2 Le notifiche push non partono — **M**
Il database crea le notifiche, ma nessuno chiama `send-notification`.
Il Database Webhook **non si può creare da una migration**: su questo
progetto mancano `pg_net` e lo schema `supabase_functions`. Vanno
attivati i Webhooks dalla dashboard (Database → Webhooks), poi un
webhook su INSERT di `notifications`.

Non usare l'estensione `http`, che è installata: farebbe una chiamata
sincrona dentro la transazione, lo stesso errore per cui
`012_off_functions.sql` è stata scartata.

### 2.3 `generate-meal-plan` propone solo alimenti sfusi — **M**
Dovrebbe proporre **le ricette del professionista** adatte al pasto e
alle restrizioni, che ora esistono, e tenere conto degli obiettivi per
pasto del piano. Oggi l'app non la chiama affatto: va collegata al
diario come terza via di aggiunta ("Proponi tu") oppure rimossa.

### 2.4 Il piano vale per tutti i giorni — **M**
`macro_plan_targets.day_of_week` esiste e il diario lo rispetta, ma
l'editor scrive solo obiettivi uguali tutti i giorni. Per chi si allena
a giorni alterni servirebbe distinguere almeno "giorni di allenamento" e
"giorni di riposo".


### 2.5 Suggerimenti per chi amministra — **M**

Il pannello funziona (quadro, abilitazioni, coda alimenti). Tre cose
che mancano e che un amministratore si trova a dover fare prima o poi:

- **cercare una persona**: non si può aprire un profilo partendo da un
  indirizzo email, quindi ogni richiesta di assistenza finisce in una
  query SQL. Serve una ricerca utenti con le azioni minime (vedere i
  collegamenti, togliere l'abilitazione, bloccare);
- **sospendere invece di cancellare**: oggi esiste solo
  `delete_my_account`, definitivo. Per abusi serve una sospensione
  reversibile, che il database può già esprimere con
  `auth.users.banned_until`;
- **leggere il registro**: `audit_log` registra cambi di ruolo,
  verifiche, esportazioni e cancellazioni, e nessuno lo legge. Una
  schermata con gli ultimi eventi rende verificabile quello che
  succede, che è il punto di avere un registro.

---

## 3. Qualità

### 3.1 Test — 40, da ampliare — **M**
Ci sono 40 test su modelli e messaggi di errore
(`nutrimind-frontend/test/`). Hanno già trovato un difetto reale.
Da aggiungere: test di `PlanService.distribute` (la ripartizione dei
macro è aritmetica pura, facile da coprire) e test delle schermate
principali con servizi finti.

### 3.2 SDK Flutter — fatto, con un avvertimento — **S**
Aggiornato il 13 ottobre a **3.47.7** (Dart resta 3.13.5): analyzer
pulito, 40 test verdi, build e avvio verificati. Nessuna rottura.

L'avvertimento: `material_color_utilities` e `test_api` **non si sono
mossi**. Erano l'unica ragione per aggiornare e un rilascio di patch non
cambia i pin dell'SDK. Per quei due serve un rilascio minore di Flutter,
quindi non vale rincorrerlo.

### 3.3 CI — in piedi, da rafforzare — **S**
- backend: migration analizzate col parser di PostgreSQL, Edge Functions
  con esbuild;
- frontend: `flutter analyze`, `flutter test`, compilazione web.

Due passi successivi, ognuno in un commit a sé perché produrranno molte
modifiche:
- `deno check supabase/functions/*/index.ts`: il **controllo dei tipi**
  delle funzioni non è mai stato eseguito;
- `dart format`: la maggior parte dei file non è formattata. Una volta
  allineati, aggiungere `--set-exit-if-changed` alla CI.

### 3.4 Paginazione — **S**
Ricerca, ricette, messaggi e conversazioni caricano un blocco fisso (da
30 a 200 elementi) senza scorrimento infinito.

### 3.5 La tavolozza è unica, le schermate no — **S**
Il tema ora è uno (`core/theme.dart`), ma le schermate costruiscono
ancora a mano le proprie schede e i propri titoli: `Container` +
`BoxDecoration` ripetuti decine di volte. Estrarre tre o quattro widget
comuni (scheda, titolo di sezione, riga di macro) ridurrebbe molto il
codice e le occasioni di sbagliare un colore.

---

## 4. Funzioni che migliorerebbero molto l'esperienza

### 4.1 Foto delle ricette e degli alimenti — **M**
La colonna `image_url` esiste ma nessuno la riempie. Serve un bucket
Supabase Storage con le sue regole, il caricamento da galleria o
fotocamera e il ridimensionamento. Per i professionisti la vetrina senza
foto non vende.

### 4.2 Lista della spesa — **M**
Dalle ricette scelte per la settimana: somma gli ingredienti, raggruppa
per categoria, si spunta.

### 4.3 Peso, misure e grafici — **M**
I Progressi mostrano solo calorie e macro. Una tabella
`body_measurements` con l'andamento dà al paziente il riscontro che
cerca e al professionista un dato utile. Serve anche per calcolare un
fabbisogno calorico invece di farlo scrivere a mano nell'editor.

### 4.4 Menu della settimana — **L**
Il professionista assegna ricette ai pasti dei sette giorni; il paziente
lo vede nel diario e lo registra con un tocco. Collega ricette, piani
macro e diario. Ora che esistono i consigli mirati
(`patient_suggestions`), è il passo naturale successivo.

### 4.5 Ricerche recenti — **S**
La ricerca tollera gli errori di battitura (022). Manca ricordare le
ultime ricerche e mettere in cima gli alimenti usati più spesso.

---

## 5. Prodotto e crescita

### 5.1 Prenotazione e pagamenti — **L**
Nella vetrina il prezzo dei piani è testo libero. Un percorso vero
(richiesta, accettazione, pagamento, primo appuntamento) trasformerebbe
la vetrina in un canale di acquisizione. Richiede valutazioni fiscali e
contrattuali, non solo tecniche.

### 5.2 Condivisione social delle ricette — **S**
Le ricette hanno il link al post dell'autore. Manca il contrario:
condividere una ricetta dall'app con un'immagine riconoscibile.

### 5.3 Valutazioni dei professionisti — **M**
Aiuterebbe la scelta, ma va gestita con attenzione: moderazione, diritto
di replica, nessun giudizio clinico.

---

## 6. Conformità e privacy (da non rimandare troppo)

### 6.1 Informativa all'iscrizione — **M**
Esportazione dei propri dati e cancellazione dell'account ora si fanno
da Profilo → Dati personali → "I tuoi dati": `export_my_data` e
`delete_my_account` esistevano nel database e non erano raggiungibili da
nessuna schermata. L'esportazione finisce negli appunti; salvarla come
file richiede un pacchetto per piattaforma ed è il passo successivo.

Resta la parte più impegnativa: `legal_documents` e `terms_acceptances`
esistono ma nessuno li usa, quindi non c'è informativa all'iscrizione né
registrazione della versione accettata. Per dati alimentari e sanitari
serve.

### 6.2 Moderazione di chat e ricette — **M, diventata urgente**
Chiunque può scrivere a un professionista pubblico e proporre ricette.
Manca segnalare e bloccare, e un registro per chi modera.

**Da rimandabile a bloccante.** Finché le ricette passavano dalla
revisione di un professionista, la moderazione era una rete di
sicurezza. Con la Community del punto 8 — ricette pubblicate da tutti,
commenti aperti a tutti, foto e video caricati dagli utenti — diventa il
primo giorno un problema concreto e non più un'ipotesi. **Non va dopo la
Community: va insieme**, almeno nella forma minima (segnalare, una coda
per chi amministra, sospendere un utente). Vedere anche il punto 2.5,
che chiedeva già la sospensione reversibile al posto della sola
cancellazione definitiva.

### 6.3 Conservazione dei dati — **S**
`audit_log` e `food_snapshots` crescono senza limite.

---

## 7. Debito tecnico minore

- **Tre funzioni normalizzano gli stessi campi** del catalogo esterno
  (`import-off-barcode`, `search-off`, `sync-off-batch`): la logica
  comune andrebbe in `supabase/functions/_shared/`.
- **`create_food_screen.dart`** sta in `features/nutritionist/` ma lo usa
  anche il paziente per gli alimenti personali.
- **Stato condiviso**: `flutter_riverpod` e `go_router` sono tra le
  dipendenze e non vengono usati; ogni schermata ricarica da sola.
- ~~**`011_functions.sql` e `011_functions_fixed.sql`** convivono~~ —
  **fatto il 13 ottobre.** Eliminata la prima, che era la versione
  precedente delle stesse venti funzioni, e messo un avviso in testa
  alla seconda. Il pericolo non era avere due file: era rieseguirli.
  `search_foods`, `get_food_by_barcode` e `start_macro_plan` sono state
  ricreate con **firme diverse** dalle migration successive, e
  `create or replace` non sostituisce una funzione con parametri
  diversi, **ne aggiunge una seconda**. Siccome l'app manda alla RPC
  soltanto i parametri impostati, una ricerca per solo testo sarebbe
  finita sul sovraccarico a due parametri e i filtri nutrizionali
  sarebbero stati ignorati **in silenzio**. Verificato che nel database
  di sviluppo esiste una sola versione di ciascuna.
- **Supabase CLI**: tutto si applica a mano dal SQL Editor. Con
  `supabase link` e `supabase db push` le migration sarebbero tracciate
  e ripetibili su PROD.
- **Chiavi esposte**: restano da rigenerare (vedi CONTESTO_PROGETTO.md).

---

## 8. Il programma chiesto il 13 ottobre

Sei richieste arrivate insieme. Due sono già fatte (8.4 in parte e 8.5),
le altre sono una funzione nuova e grossa che cambia anche la barra di
navigazione. Qui sotto l'ordine con cui conviene affrontarle, le
decisioni che ho preso e quelle che restano da prendere.

**Perché quest'ordine:** la Community non si può scrivere prima di aver
deciso chi è «utente base», perché è la vista che distingue i due. I
commenti vengono dopo che c'è una schermata dove metterli. Le foto sono
indipendenti da tutto e si possono infilare quando si vuole.

### 8.1 «Utente Base» accanto a «Paziente» — **M**

Richiesta: un utente nuovo che non ha (o non vuole) un nutrizionista è
un **Utente Base**; quando si collega diventa **Paziente**; quando il
collegamento si interrompe torna Utente Base.

**Deciso: un valore vero nell'enum `user_role`** (migration 029 e 030,
scritte, da applicare). Avevo proposto uno stato derivato dal
collegamento ed è stato scelto il ruolo salvato.

**Devo correggere una mia stima, perché era sbagliata e in modo
importante.** Avevo scritto che «decine di funzioni e tutte le policy
RLS controllano `role = 'patient'`». Controllato invece di stimare:

- **nessuna policy RLS guarda il ruolo.** Usano `patient_id =
  auth.uid()` e le funzioni d'aiuto (`has_active_link`,
  `can_nutritionist_see`, …). È questo che rende l'operazione
  ragionevole: la sicurezza del database non va rimessa in discussione;
- **nove funzioni** contengono `'patient'`, non decine. Due lo usano
  solo come etichetta nel registro di controllo e non vanno toccate;
  una, `start_new_plan`, è superata e non è chiamata da nessuna parte.
  Restano **sei**, più `revoke_link`.

Due controlli fatti prima di scrivere, che avrebbero cambiato il
risultato:

- **niente legge il ruolo dal token** (`auth.jwt()`, `app_metadata`):
  tutto legge `profiles`. Quindi la promozione ha effetto subito e il
  client non deve rinnovare la sessione dopo essersi collegato;
- i cambi di ruolo li registra **già** il trigger `profiles_audit`, con
  valore di partenza e arrivo. Le mie chiamate a `log_audit` erano
  doppioni e sono state togliere.

Come funziona: chi si iscrive nasce `base_user`; `redeem_invitation`
promuove a `patient` nella **stessa transazione** del collegamento;
`revoke_link` riporta a `base_user` solo se non resta nessun altro
collegamento attivo (nulla vieta due professionisti). Tenere le
transizioni dentro quelle due funzioni è ciò che impedisce al ruolo e ai
collegamenti di contraddirsi — il rischio che mi preoccupava — e lo
script di contratto ora lo verifica con un controllo apposta.

La 030 allinea anche chi c'è già: sul database di sviluppo **3 utenti su
5** risultano `patient` senza collegamento attivo e tornano utenti base.

Resta da fare nel frontend: leggere `my_status()` all'avvio, mostrare
l'etichetta «Utente Base» nel profilo e cambiare le due voci della
registrazione («Utente» e «Professionista», non «Paziente»). Nessun'altra
schermata cambia: l'autogestione del piano era già governata da «nessun
collegamento attivo», che è la stessa condizione.

### 8.2 Scheda Community, al centro di cinque — **L**

Tre viste: **Dal Mondo** (le ricette pubblicate dai professionisti per
tutti, più quelle aggiunte da pazienti e utenti base), **Dal Mio
Nutrizionista** (solo per chi è Paziente) e **Le Mie Ricette**.

**Nodo da sciogliere subito: al centro della barra oggi c'è il pulsante
`+` del diario**, incastonato nella tacca della `BottomAppBar`
(`CircularNotchedRectangle`). Non possono stare entrambi nello stesso
posto. Tre strade, in ordine di preferenza:

**Deciso: Community al centro, il `+` resta al centro ma più in alto**,
staccato dalla barra e sopra di essa. In Flutter è
`FloatingActionButtonLocation.centerFloating` con la tacca della
`BottomAppBar` rimossa (`shape: null`), altrimenti resta il buco dove
non c'è più niente.

Due cose da tenere d'occhio quando si scrive: il `+` sospeso copre il
fondo del contenuto, quindi le liste scorrevoli hanno bisogno di
`padding` in basso per non finire sotto il pulsante (il diario ne ha già
uno, va ricontrollato); e il pulsante ha senso solo sulle schede Diario
e Alimenti — sulle altre tre va nascosto, non disabilitato.

Sul database serve poco di nuovo: `suggested_meals` ha già `visibility`,
`status` e `proposed_by`, e `get_recipes_for_me` esiste. Manca **la via
di pubblicazione per chi non è professionista**: `publish_own_meal`
richiede la verifica professionale, quindi oggi un paziente può solo
*proporre* una ricetta al proprio nutrizionista e aspettare la
revisione.

**Deciso: si pubblica subito**, senza revisione preventiva, con il
pulsante «segnala» e la possibilità di rimuovere. Quindi serve:

- una RPC `publish_to_community` aperta a `patient` e `base_user`, che
  porti la ricetta a `approved` con `visibility` pubblica. Attenzione a
  `meals_reviewer_not_proposer` e `meals_approved_stamped`: il primo
  vieta che chi revisiona sia l'autore, il secondo pretende
  `reviewed_at` e `published_at` valorizzati. `publish_own_meal` lo
  risolve lasciando `reviewed_by` vuoto, e qui va fatto allo stesso
  modo;
- la coda di segnalazioni e la rimozione, che è il punto 6.2 e **va
  fatto insieme**, non dopo: pubblicare subito senza avere il modo di
  togliere è la combinazione peggiore.

### 8.3 Commenti alle ricette, con le risposte — **M**

Solo testo ed emoji, nessuna immagine; si risponde sia alla ricetta sia
a un commento. Serve una tabella `recipe_comments` con un `parent_id`
che punta a sé stessa, RLS che lasci leggere i commenti delle ricette
che si possono già vedere, scrivere a chiunque sia autenticato e
cancellare solo i propri (più chi modera).

Due cose da decidere bene, perché sono quelle che trasformano i commenti
da funzione a problema:

- **la profondità**: due livelli (ricetta → commento → risposta)
  bastano e si disegnano; un albero senza fondo è illeggibile su un
  telefono e pesante da leggere in una query;
- **la moderazione, prima di aprire** e non dopo: pulsante «segnala»,
  una coda per chi amministra, e il blocco di un utente. Il punto 6.2
  chiedeva già moderazione per chat e ricette e non è mai stato fatto.
  Aprire i commenti a tutti senza niente di tutto questo significa che
  il primo giorno in cui qualcuno scrive una cosa sbagliata non si ha
  nessuno strumento per toglierla, se non una query SQL.

Che siano «solo testo ed emoji» aiuta ma non basta: le emoji non si
filtrano, le parole sì, e un indirizzo web dentro un commento è testo.

### 8.4 Condividere una ricetta in chat — **S**

Il paziente manda al proprio nutrizionista una ricetta per chiedere
sostituzioni o correzioni. **Questa è quasi fatta e non lo sapevamo:**
`send_message` accetta già `p_kind` e `p_payload`, e la chat sa già
disegnare la scheda di una ricetta e aprirla (`_openRecipe` in
`chat_screen.dart`, usato per i consigli mirati). Manca solo il gesto di
partenza: un «Condividi col mio nutrizionista» sulla ricetta, visibile a
chi ha un collegamento attivo.

È il pezzo col rapporto migliore fra valore e lavoro di tutto il
programma: **da fare per primo**, prima della Community.

### 8.5 Immagini degli alimenti — **fatto**

Migration 028, le tre Edge Functions, e nell'app le foto negli elenchi,
nella ricerca e nella scheda del prodotto. Da applicare e ripubblicare
(punto 1.1). Verificato a schermo: i prodotti del catalogo esterno
mostrano la confezione, i nostri il segnaposto finché la 028 non è
applicata.

Una cosa da sapere: **sul web le immagini dipendono dalle intestazioni
CORS** del sito che le ospita, e la prova fatta qui **non vale**, perché
l'ambiente dell'anteprima è permissivo e c'è di mezzo il proxy
aziendale. Su Android e iOS il CORS non si applica e si vedranno. Se sul
web non si vedessero, la via è una Edge Function che faccia da tramite
per le immagini: mezza giornata, da fare solo se serve davvero.

### 8.6 Foto e video delle proprie ricette — **M, da fare**

È l'unico punto dell'app in cui un utente carica un file. Richiede:

- un **bucket Supabase Storage** con le sue regole: chi carica scrive
  solo nella propria cartella, la lettura è pubblica per le ricette
  pubblicate. Si crea da migration inserendo in `storage.buckets`,
  quindi senza passare dalla dashboard;
- una tabella `recipe_media` e non una colonna: `suggested_meals` ha una
  sola `image_url`, e qui servono **più** file e due tipi diversi;
- limiti scritti **nel bucket** e non solo nell'app: dimensione massima
  e tipi MIME ammessi. Un video girato con un telefono moderno sono
  decine di megabyte e il piano gratuito di Supabase dà **1 GB**: con
  cinquanta video si è fuori. Conviene decidere subito un tetto per
  utente e una durata massima;
- ridimensionamento e miniatura dal lato dell'app prima di caricare:
  mandare 8 MB per mostrare un riquadro da 300 pixel li paga l'utente in
  dati;
- la moderazione del punto 8.3, che con immagini e video pesa molto più
  che col testo.

**Considerazione da non aggirare:** i file caricati dagli utenti sono la
cosa più delicata di tutto il programma, più dei commenti. Finché l'app
sta su DEV con tre utenze di prova non si vede, ma vanno decisi insieme
il tetto di spazio, la moderazione e **cosa succede ai file quando
qualcuno cancella il proprio account**: `delete_my_account` oggi non sa
niente dello Storage, quindi i file resterebbero dopo la cancellazione,
ed è esattamente il genere di cosa che un'informativa privacy promette
di non fare.

### 8.7 Immagini anche nel diario — **S, suggerimento mio**

Non è stato chiesto ma è lo stesso lavoro già fatto: nel diario le voci
registrate hanno ancora un rientro vuoto largo 57 pixel dove starebbe la
miniatura. Oggi non si può riempire perché `get_diary_entries` non
restituisce l'immagine dell'alimento: va aggiunta ai campi che quella
RPC espone. Mezz'ora, e il diario si legge a colpo d'occhio come la
ricerca.
