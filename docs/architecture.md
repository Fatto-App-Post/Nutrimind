# Architettura Nutrimind

## Panoramica

Nutrimind è un'app di food tracking macro-first con:

- **Backend**: C# .NET 8, ASP.NET Core Minimal API
- **Database**: PostgreSQL su Supabase
- **Fonte esterna**: Open Food Facts API
- **Frontend**: Flutter (app mobile)

## Componenti principali

- **Api**: espone endpoint HTTP per alimenti, diario, piani, pazienti.
- **Application**: servizi, DTO, mapping, regole di business.
- **Domain**: modelli, value object, interfacce repository.
- **Infrastructure.Supabase**: client Supabase, repository, migrazioni.
- **Infrastructure.OpenFoodFacts**: client OFF, mapper, policy di cache.

## Flusso dati principale

1. Il frontend cerca un alimento (testo o barcode).
2. Il backend cerca prima in Supabase.
3. Se non trovato, chiama OFF e salva il risultato in Supabase.
4. Il diario e i piani usano solo dati locali verificati.
