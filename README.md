# Finanzplaner/Haushaltsplaner App

Eine Haushaltsplaner-App zum Tracken von Einnahmen & Ausgaben (Flutter + lokale SQLite DB via Drift). \
Fokus: schnelle Eingabe, Kategorienverwaltung, Filter (Zeitraum/Kategorie) und Backup/Restore.

## Features

- Anzeige von Einnahmen vs. Ausgaben und Saldo
- Buchungen erfassen (Einnahme/Ausgabe, Betrag, Datum, Kategorie, Notiz)
- Buchungen bearbeiten & löschen (Soft-Delete)
- Kategorien anlegen/umbenennen/löschen (Soft-Delete + Wiederherstellen bei gleichem Namen)
- Beim Löschen einer Kategorie: Buchungen wahlweise
    - löschen (Soft-Delete),
    - in andere Kategorie verschieben,
    - ins Archiv verschieben
- Filter im HomeScreen:
    - Zeitraum (Komplett, Monat, Spanne, YTD, etc.)
    - Kategorie
- Backup:
    - Export als JSON (Share Sheet: z.B. Google Drive)
    - Import aus JSON

### Kommende Features

- Screen für Statistiken & Charts zur graphischen Übersicht
- PC & IOS Version (momentan nur für Android verfügbar)
- Synchronisation zwischen eigenen Geräten (Handy ⟷ Tablet ⟷ Laptop/PC)