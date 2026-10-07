# NutriMind — prossimi passi

Proposte di lavoro al **7 ottobre 2026**, in ordine di priorità. Per lo
stato attuale e i vincoli del database vedere
[CONTESTO_PROGETTO.md](CONTESTO_PROGETTO.md).

Legenda impegno: **S** poche ore · **M** 1-2 giorni · **L** più giorni.

---

## 1. Da fare subito: cose rotte o incomplete

### 1.1 Provare l'app con utenti veri — **S**
Niente è ancora stato verificato con un utente collegato: il codice
compila e il database è allineato, ma nessun flusso è stato percorso.
Servono due utenti su DEV, un paziente e un professionista, e il
professionista va verificato a mano:

```sql
update public.profiles set professional_verified = true where id = '<uuid>';
```

Poi, dal suo profilo, attivare "Mostrami in Trova un nutrizionista".
Da provare in quest'ordine: registrazione, diario, ricerca con filtri,
codice a barre, ricetta inviata e approvata, invito, chat, progressi.

### 1.2 `generate-meal-plan` usa un valore inesistente — **S**
La funzione genera pasti con `meal_slot: 'snack'`, che non esiste
nell'enum: ogni inserimento verrebbe rifiutato. Va riscritta sui valori
corretti e, già che si tocca, dovrebbe proporre **le ricette del
nutrizionista** invece dei singoli alimenti. Oggi l'app non la usa.

### 1.3 Pannello per le verifiche professionali — **M**
Senza questo nessun professionista può essere abilitato se non via SQL.
Serve un ruolo admin nell'app con l'elenco delle richieste in
`professional_verifications` e due pulsanti (approva, rifiuta). Esiste
già `review_food`; va aggiunta una `review_professional_verification`.

### 1.4 Le notifiche push non vengono inviate — **M**
Il database crea le notifiche, ma nulla le inoltra a Firebase: la
funzione `send-notification` non viene chiamata da nessuno. Serve un
Database Webhook sulla tabella `notifications` (Database → Webhooks) che
la invochi a ogni inserimento. Da valutare un raggruppamento per non
mandare una push per ogni messaggio di chat.

---

## 2. Qualità di base

### 2.1 Test automatici — **M**
Il progetto non ha un solo test. I più utili, in ordine:
- test dei modelli: lettura dei dati dal database, filtri nutrizionali,
  conversione degli enum;
- test di `AppError`: ogni codice di errore dà il messaggio giusto;
- test delle schermate principali con i servizi finti (login, diario).

Da aggiungere anche al workflow GitHub Actions, che oggi esegue ancora i
test del backend .NET eliminato.

### 2.2 Il workflow CI è da riscrivere — **S**
`.github/workflows/ci.yml` fa `dotnet build` e `dotnet test` su progetti
che non esistono più. Dovrebbe invece: validare le migration,
`flutter analyze` e `flutter test` sul frontend.

### 2.3 Paginazione e liste lunghe — **S**
Ricerca alimenti, ricette, messaggi e conversazioni caricano un blocco
fisso (da 30 a 200 elementi) senza scorrimento infinito. Con il catalogo
che cresce diventerà un problema.

---

## 3. Funzioni che migliorerebbero molto l'esperienza

### 3.1 Foto delle ricette e degli alimenti — **M**
La colonna `image_url` esiste già ma nessuno la riempie. Serve un bucket
Supabase Storage con regole di accesso, il caricamento dalla galleria o
dalla fotocamera e il ridimensionamento. Le ricette con foto sono molto
più invitanti, e per i professionisti è la vetrina.

### 3.2 Lista della spesa — **M**
Generata dalle ricette scelte per la settimana e dal piano: somma gli
ingredienti, raggruppa per categoria, permette di spuntare. È la
funzione più richiesta nelle app di questo tipo e si appoggia a dati che
abbiamo già.

### 3.3 Peso, misure e grafici — **M**
Oggi i Progressi mostrano solo calorie e macro. Una tabella
`body_measurements` (peso, circonferenze, foto opzionali) con grafico
dell'andamento dà al paziente il riscontro che cerca e al professionista
un dato clinico utile.

### 3.4 Menu della settimana — **L**
Il nutrizionista compone un menu assegnando ricette ai pasti dei sette
giorni; il paziente lo vede nel diario e lo registra con un tocco.
Collega ricette, piani macro e diario, che già esistono separatamente.

### 3.5 Ricerca alimenti più furba — **S**
Oggi la ricerca testuale usa `ilike` su nome e marca. Con `pg_trgm`,
già installato, si potrebbe ordinare per somiglianza e tollerare errori
di battitura. Utile anche salvare le ricerche recenti.

---

## 4. Prodotto e crescita

### 4.1 Prenotazione e pagamenti — **L**
Nella vetrina il prezzo dei piani è solo un testo libero. Un percorso
vero (richiesta, accettazione, pagamento con Stripe, primo
appuntamento) trasformerebbe la vetrina in un canale di acquisizione.
Richiede valutazioni fiscali e contrattuali, non solo tecniche.

### 4.2 Condivisione social delle ricette — **S**
Le ricette hanno già il link al post social dell'autore. Manca il
contrario: condividere una ricetta dall'app con un'immagine
riconoscibile. Buon rapporto tra sforzo e visibilità.

### 4.3 Valutazioni e recensioni dei professionisti — **M**
Nella vetrina si vedono solo ricette e piani. Una valutazione dei
pazienti collegati aiuterebbe la scelta, ma va gestita con attenzione:
moderazione, diritto di replica, nessun giudizio clinico.

---

## 5. Conformità e privacy (da non rimandare troppo)

### 5.1 Informativa, consensi e cancellazione — **M**
Esistono `legal_documents` e `terms_acceptances`, ma l'app non li usa:
nessuna informativa all'iscrizione, nessuna accettazione registrata.
Esistono già `export_my_data` e `delete_my_account` nel database, ma non
sono raggiungibili dall'app. Trattandosi di dati sanitari servono:
informativa all'iscrizione con registrazione della versione accettata,
esportazione dei propri dati, cancellazione dell'account.

### 5.2 Moderazione di chat e ricette — **M**
Chiunque può scrivere in chat a un professionista pubblico e proporre
ricette. Manca la possibilità di segnalare e bloccare, e un registro per
chi modera. C'è già un limite anti-spam sui messaggi.

### 5.3 Conservazione dei dati — **S**
`audit_log` e `food_snapshots` crescono senza limite. Serve una regola
di conservazione e una pulizia periodica.

---

## 6. Debito tecnico minore

- **Riordinare le cartelle del frontend**: `create_food_screen.dart` sta
  in `features/nutritionist/` ma lo usa anche il paziente per gli
  alimenti personali.
- **Stato condiviso**: `flutter_riverpod` e `go_router` sono tra le
  dipendenze ma non vengono usati; ogni schermata ricarica da sola. Con
  la crescita servirà una cache condivisa (profilo, conteggi, catalogo).
- **`011_functions.sql` e `011_functions_fixed.sql`** convivono nel
  repo: tenere solo la versione valida per evitare confusione.
- **Messaggi duplicati**: `conversations.last_message_at` si aggiorna da
  RPC; un trigger sarebbe più solido.
- **Supabase CLI**: tutto viene applicato a mano dal SQL Editor. Con
  `supabase link` e `supabase db push` le migration sarebbero tracciate
  e ripetibili su PROD.
