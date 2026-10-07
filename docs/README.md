# Documentazione NutriMind

- **[CONTESTO_PROGETTO.md](CONTESTO_PROGETTO.md)** — da leggere per primo:
  com'è fatta l'app, valori ammessi e vincoli del database, migration,
  Edge Functions, configurazione, avvertenze di sicurezza.
- **[PROSSIMI_PASSI.md](PROSSIMI_PASSI.md)** — proposte di lavoro in
  ordine di priorità.

I file precedenti (guide frontend, documentazione degli endpoint REST del
backend .NET, setup e configurazioni mancanti) sono stati rimossi perché
superati: descrivevano un'architettura che non esiste più o firme di
funzioni cambiate. Il loro contenuto ancora valido è in
`CONTESTO_PROGETTO.md`; il resto è nella cronologia git.

La fonte di verità è il database: si verifica con
`supabase/verify_frontend_contract.sql`.
