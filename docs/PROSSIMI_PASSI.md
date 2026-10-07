# NutriMind — prossimi passi

Aggiornato al **7 ottobre 2026**, dopo la prova del lato professionista.
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

**Non provato cliccando**: tutto ciò che richiede un paziente collegato,
il pannello di amministrazione (manca la 025) e le notifiche push. Le
funzioni nuove del database sono però state eseguite in sola lettura,
con i parametri veri, prima di consegnarle.

---

## 1. Da applicare (serve un tuo passaggio)

### 1.1 Migration 026 — **S**
Nel SQL Editor, poi `supabase/verify_frontend_contract.sql`.

| Migration | Cosa porta |
|---|---|
| `026_fix_plan_targets_generated.sql` | **Correzione**: la 023 scriveva `macro_plan_targets.kcal_estimated`, che è una colonna generata. Nessun piano macro si poteva salvare (errore 428C9), né dal professionista né in autogestione |

È venuto fuori provando per la prima volta a creare un piano con un
paziente collegato: è lo stesso errore in cui era incappata
`meal_recalc` con le colonne `*_per_serving`. Da qui il controllo nuovo
nello script di verifica, che elenca le colonne generate delle due
tabelle su cui ci siamo già sbagliati.

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

Il quadro generale ora dice cosa aspetta una decisione. Tre cose che
mancano e che un amministratore si trova a dover fare prima o poi:

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
