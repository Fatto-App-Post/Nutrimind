# NutriMind — prossimi passi

Aggiornato al **7 ottobre 2026**, dopo la prima prova dell'app nel
browser con un'utenza vera. Per lo stato e i vincoli del database vedere
[CONTESTO_PROGETTO.md](CONTESTO_PROGETTO.md).

Legenda impegno: **S** poche ore · **M** 1-2 giorni · **L** più giorni.

---

## 0. Cosa è stato provato davvero

Compilata per il web e percorsa a mano come paziente
(`pasquinapoli1@gmail.com`). **Funziona**: accesso, diario del giorno,
ricerca testuale, passaggio automatico al catalogo esteso quando il
catalogo locale non basta, import del prodotto, dettaglio con tabella
nutrizionale e allergeni, aggiunta al diario con ricalcolo dei macro,
import di un codice a barre digitato a mano, ricerca per soli valori
nutrizionali, Progressi, Profilo e tutte le sue voci, vetrina e chat
(vuote ma con il messaggio giusto, non più in errore).

**Non ancora provato**: tutto il lato professionista (serve
un'abilitazione, punto 1.3), le notifiche push, Android e iOS.

---

## 1. Da applicare (serve un tuo passaggio)

### 1.1 Eseguire le migration 021 e 022 — **S**
Nel SQL Editor, una per volta, poi
`supabase/verify_frontend_contract.sql`: i tre problemi che segnala ora
("handle_new_user", "utenze senza profilo", "search_foods") devono
sparire.

| Migration | Perché |
|---|---|
| `021_signup_role.sql` | Chi si registra come nutrizionista veniva creato **come paziente**: il trigger ignorava il ruolo scelto. Crea anche il profilo mancante di un'utenza che ne è priva |
| `022_food_search_relevance.sql` | La ricerca testuale non tollerava errori di battitura e ordinava per affidabilità invece che per pertinenza |

### 1.2 Ripubblicare tre Edge Functions — **S**
`import-off-barcode`, `search-off`, `sync-off-batch`: ingredienti e
allergeni in italiano quando il catalogo esterno li ha, allergeni
tradotti dai tag (prima la Nutella mostrava "lait, fruits à coque,
soja"), porzione "Porzione 47.5 g" invece di "1 serving (47.5 g)".

### 1.3 Abilitare un professionista e provare il suo lato — **S**
Dopo la 021 basta registrare un'utenza scegliendo "nutrizionista". Poi:

```sql
update public.profiles set professional_verified = true
 where id = (select id from auth.users where email = 'indirizzo@esempio.it');
```

e dal profilo nell'app attivare "Mostrami in Trova un nutrizionista".
Da provare: pazienti, invito, piano macro, commenti sul diario, ricette
pubblicate, coda di verifica, piani di base, chat da entrambi i lati.

---

## 2. Cose rotte o incomplete

### 2.1 Il catalogo alimenti è vuoto — **M**
`public.foods` conteneva **zero righe**: ogni ricerca finiva sul
catalogo esterno, e la ricerca per valori nutrizionali non poteva
restituire niente. Ora ci sono i due prodotti importati durante la
prova.

Senza un catalogo di base l'app non è usabile: servono gli alimenti
sfusi (pasta, riso, pollo, uova, olio...), che nel catalogo esterno non
ci sono come voci generiche affidabili.

Due strade, in ordine di preferenza:
1. **importare una tabella di riferimento** (CREA per l'Italia, USDA
   FoodData Central): sono i valori che `trust_level` considera di
   livello 3. Serve una funzione di import e, per USDA, una chiave API;
2. **precaricare i prodotti confezionati più comuni** inserendo i
   codici a barre in `food_off_sync_log` ed eseguendo `sync-off-batch`,
   che oggi non è mai stata usata.

Non conviene scrivere a mano i valori nutrizionali: in un'app che
gestisce dati alimentari la provenienza del dato conta, e
`trust_level` la deduce da `source` e `verification`.

### 2.2 Pannello per le verifiche professionali — **M**
Senza questo nessun professionista si abilita se non via SQL (1.3).
Serve un ruolo admin nell'app con l'elenco delle richieste in
`professional_verifications` e due pulsanti. Esiste già `review_food`;
va aggiunta una `review_professional_verification`.

### 2.3 Le notifiche push non partono — **M**
Il database crea le notifiche, ma nessuno chiama `send-notification`.
Il Database Webhook **non si può creare da una migration**: su questo
progetto manca `pg_net` e manca lo schema `supabase_functions`. Vanno
attivati i Webhooks dalla dashboard (Database → Webhooks), poi un
webhook su INSERT di `notifications`.

Non usare l'estensione `http`, che è installata: farebbe una chiamata
sincrona dentro la transazione, lo stesso errore per cui
`012_off_functions.sql` è stata scartata.

### 2.4 `generate-meal-plan` propone solo alimenti sfusi — **M**
Funziona ma suggerisce singoli alimenti dal catalogo. Dovrebbe proporre
**le ricette del nutrizionista** adatte al pasto e alle restrizioni, che
ora esistono. Oggi l'app non la usa: va collegata al diario come terza
via di aggiunta ("Proponi tu") oppure rimossa.

---

## 3. Qualità

### 3.1 Primi test automatici — fatto, da ampliare — **M**
Ci sono 40 test su modelli e messaggi di errore
(`nutrimind-frontend/test/`). Hanno già trovato un difetto reale: un
valore numerico che arrivasse come stringa faceva fallire l'intera
schermata.

Da aggiungere: test delle schermate principali con servizi finti
(accesso, diario, ricerca), e test della conversione delle ricette.

### 3.2 CI — fatto, da rafforzare — **S**
Il vecchio workflow eseguiva `dotnet build` e `dotnet test` su progetti
cancellati: falliva a ogni push. Adesso:

- backend: le migration vengono analizzate col parser di PostgreSQL, le
  Edge Functions con esbuild;
- frontend: `flutter analyze`, `flutter test`, compilazione web.

Due passi successivi, entrambi da fare in un commit a parte perché
produrranno molte modifiche:
- `deno check supabase/functions/*/index.ts`: il **controllo dei tipi**
  delle funzioni non è mai stato eseguito;
- `dart format`: 41 file su 51 non sono formattati. Una volta allineati,
  aggiungere `--set-exit-if-changed` alla CI.

### 3.3 Paginazione — **S**
Ricerca, ricette, messaggi e conversazioni caricano un blocco fisso (da
30 a 200 elementi) senza scorrimento infinito.

---

## 4. Aspetto: metà app è chiara, metà è scura

Non è una questione di gusto, è un'incoerenza: ogni schermata dichiara i
propri colori e le dichiarazioni non concordano.

| Sfondo | Schermate |
|---|---|
| Scuro `#101817` | Diario, ricerca alimenti, filtri nutrizionali |
| Chiaro `#FAFAFA` | tutte le altre (17 file) |

Inoltre `buildTheme()` è un tema Material **chiaro** generato da un
colore seme, quindi finestre di dialogo, avvisi e campi di testo seguono
un terzo schema. La stessa tavolozza (`primaryTeal`, `colorP/C/G`...) è
ripetuta in venti file.

Serve una decisione di prodotto, poi il lavoro è meccanico:
- **tutto scuro** (l'identità del Diario, la schermata principale): va
  rifatto il colore del testo e delle schede nelle 17 schermate chiare;
- **tutto chiaro**: cambiano solo 3 schermate, ma l'app perde il suo
  aspetto attuale.

In entrambi i casi: tavolozza unica in `core/theme.dart` e `ThemeData`
coerente, così dialoghi e avvisi smettono di stonare. **S** se si
sceglie chiaro, **M** se si sceglie scuro.

---

## 5. Funzioni che migliorerebbero molto l'esperienza

### 5.1 Foto delle ricette e degli alimenti — **M**
La colonna `image_url` esiste ma nessuno la riempie. Serve un bucket
Supabase Storage con le sue regole, il caricamento da galleria o
fotocamera e il ridimensionamento. Per i professionisti la vetrina senza
foto non vende.

### 5.2 Lista della spesa — **M**
Dalle ricette scelte per la settimana: somma gli ingredienti, raggruppa
per categoria, si spunta. Si appoggia a dati che già abbiamo.

### 5.3 Peso, misure e grafici — **M**
I Progressi mostrano solo calorie e macro. Una tabella
`body_measurements` con l'andamento dà al paziente il riscontro che
cerca e al professionista un dato utile.

### 5.4 Menu della settimana — **L**
Il nutrizionista assegna ricette ai pasti dei sette giorni; il paziente
lo vede nel diario e lo registra con un tocco. Collega ricette, piani
macro e diario, che oggi esistono separati.

### 5.5 Ricerche recenti — **S**
La ricerca ora tollera gli errori di battitura (migration 022). Manca
ricordare le ultime ricerche e gli alimenti usati più spesso in cima.

---

## 6. Prodotto e crescita

### 6.1 Prenotazione e pagamenti — **L**
Nella vetrina il prezzo dei piani è testo libero. Un percorso vero
(richiesta, accettazione, pagamento, primo appuntamento) trasformerebbe
la vetrina in un canale di acquisizione. Richiede valutazioni fiscali e
contrattuali, non solo tecniche.

### 6.2 Condivisione social delle ricette — **S**
Le ricette hanno il link al post dell'autore. Manca il contrario:
condividere una ricetta dall'app con un'immagine riconoscibile.

### 6.3 Valutazioni dei professionisti — **M**
Aiuterebbe la scelta, ma va gestita con attenzione: moderazione, diritto
di replica, nessun giudizio clinico.

---

## 7. Conformità e privacy (da non rimandare troppo)

### 7.1 Informativa, consensi, cancellazione — **M**
`legal_documents` e `terms_acceptances` esistono ma l'app non li usa:
nessuna informativa all'iscrizione, nessuna accettazione registrata.
`export_my_data` e `delete_my_account` esistono nel database ma non sono
raggiungibili dall'app. Trattandosi di dati alimentari e sanitari
servono tutti e tre.

### 7.2 Moderazione di chat e ricette — **M**
Chiunque può scrivere a un professionista pubblico e proporre ricette.
Manca segnalare e bloccare, e un registro per chi modera. Il limite
anti-spam sui messaggi c'è già.

### 7.3 Conservazione dei dati — **S**
`audit_log` e `food_snapshots` crescono senza limite.

---

## 8. Debito tecnico minore

- **Allergeni e ingredienti**: la traduzione dai tag copre i 14
  allergeni obbligatori. Gli ingredienti restano nella lingua di chi ha
  inserito il prodotto quando manca la versione italiana.
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
