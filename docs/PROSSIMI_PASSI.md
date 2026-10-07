# NutriMind — prossimi passi

Aggiornato all'**8 ottobre 2026**. A questo punto i tre ruoli — paziente,
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

## Da dove ripartire

Le migration sono tutte applicate e i tre ruoli funzionano. Le cose
ferme non sono più difetti dell'app, sono pezzi che mancano. In ordine di
quanto pesano:

1. **Il catalogo alimenti è quasi vuoto** (punto 2.1): quattro righe. È
   il collo di bottiglia di tutto il resto — ricerca per valori
   nutrizionali, ricette composte, consigli mirati. Richiede una
   decisione sulla fonte, non solo del codice.
2. **Le notifiche push non partono** (punto 2.2): il database le crea e
   nessuno le inoltra. Serve attivare i Webhooks dalla dashboard, poi è
   mezz'ora di lavoro.
3. **Android e iOS non sono mai stati compilati**: serve l'SDK Android
   in locale. Finché resta solo il web, un'app di food tracking non si
   può provare davvero: la fotocamera per il codice a barre è il suo
   gesto principale.
4. **`flutter drive` con `integration_test`** (punto 1.3): renderebbe
   ripetibile tutto quello che oggi si prova a mano, e tolgo di mezzo gli
   eventi sintetici.

Il resto (menu della settimana, foto, lista della spesa, peso) sono
funzioni nuove: valgono dopo che il catalogo c'è.

---

## 1. Da applicare (serve un tuo passaggio)

### 1.1 Tutte le migration sono applicate
Da 014 a 026, nessuna in sospeso. Dopo ogni migration conviene eseguire
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

### 3.2 CI — in piedi, da rafforzare — **S**
- backend: migration analizzate col parser di PostgreSQL, Edge Functions
  con esbuild;
- frontend: `flutter analyze`, `flutter test`, compilazione web.

Due passi successivi, ognuno in un commit a sé perché produrranno molte
modifiche:
- `deno check supabase/functions/*/index.ts`: il **controllo dei tipi**
  delle funzioni non è mai stato eseguito;
- `dart format`: la maggior parte dei file non è formattata. Una volta
  allineati, aggiungere `--set-exit-if-changed` alla CI.

### 3.3 Paginazione — **S**
Ricerca, ricette, messaggi e conversazioni caricano un blocco fisso (da
30 a 200 elementi) senza scorrimento infinito.

### 3.4 La tavolozza è unica, le schermate no — **S**
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

### 6.2 Moderazione di chat e ricette — **M**
Chiunque può scrivere a un professionista pubblico e proporre ricette.
Manca segnalare e bloccare, e un registro per chi modera.

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
- **`011_functions.sql` e `011_functions_fixed.sql`** convivono: tenere
  solo la versione valida.
- **Supabase CLI**: tutto si applica a mano dal SQL Editor. Con
  `supabase link` e `supabase db push` le migration sarebbero tracciate
  e ripetibili su PROD.
- **Chiavi esposte**: restano da rigenerare (vedi CONTESTO_PROGETTO.md).
