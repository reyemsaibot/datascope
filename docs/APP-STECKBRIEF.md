# DataScope – Steckbrief

Stand: 10. Oktober 2026.

| Feld | Entscheidung |
| --- | --- |
| Produkt | DataScope, lokales Profiling von Datei-Exporten für Fachanwender und Analysten. |
| Hauptablauf | Datei öffnen → Importoptionen prüfen → Profil berechnen → Spalte, Problemwerte und Regeln untersuchen. |
| Umfang | CSV, TSV und XLSX; Kennzahlen, Typen, Details, lokale Regeln. Bereinigung, Datenbanken, Projekte und Berichte folgen später. |
| Technik | macOS 14+, Apple Silicon, SwiftUI und DuckDB 1.4.3 über die C-API. |
| Identität | Bundle-ID `local.datascope.prototype`; Release-Bundle `output/DataScope.app`. |
| Daten | Quelle bleibt am gewählten Speicherort. Analyse läuft lokal; temporäre DuckDB-Dateien liegen im System-Temp-Ordner und werden am Ende entfernt. |
| Bedienung | Deutsche Oberfläche; `⌘O` öffnet eine Datei. Import und Detailanalyse laufen außerhalb des MainActor und können den Hauptimport abbrechen. |
| Gestaltung | Ruhige native macOS-Oberfläche, DataScope-Logo in der Seitenleiste, Profilübersicht mit auswählbaren Spalten und vertikal scrollbaren Details. |
| Abnahme | Synthetische CSV/XLSX-Fixtures, Swift-Tests, Bundle-/Signaturprüfung und native UI-Abläufe gemäß `APP-ABNAHME.md`. |
