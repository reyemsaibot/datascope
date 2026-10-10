# DataScope – Umsetzungsplan

Stand: 10. Oktober 2026. Arbeitsname: DataScope.

## Aktueller Stand

- **A: fachlicher Entwurf erstellt.** Ablauf, Zielnutzer, Umfang und drei synthetische
  Referenzfälle festgehalten. Echte Beispieldaten und Rückmeldung zu den Annahmen offen.
- **B: technischer Prototyp umgesetzt und geprüft.** CSV/XLSX, gemeinsame Engine,
  native App, CLI, Abbruch, Tests und Million-Zeilen-Messung.
  Ergebnisse und Grenzen: [VALIDATION.md](VALIDATION.md).
- **C: erster durchgängiger Detailablauf umgesetzt.** Spaltenauswahl, fehlende und
  typverletzende Werte, bis zu 200 betroffene Originalzeilen sowie Detailkennzahlen.
- **D: erster Ausbauschritt umgesetzt.** Häufige Werte, Textmuster, Quartile,
  Fünf-Balken-Verteilung und vier manuelle Regeltypen.
- **E–F: geplant, noch nicht umgesetzt.** Nächster Schritt: Regel-/Importkonfiguration
  speichern und Berichte exportieren.

## Auftrag und Entscheidungen

Native macOS-App für lokales Data Profiling, fachlich orientiert an DataCleaner.
Die Etappen A und B sind zur Umsetzung beauftragt. Die weiteren Etappen bleiben
der gespeicherte Ausbauplan. Keine Kompatibilität mit DataCleaner-Jobs zugesagt.

Arbeitsannahmen bis zur Rückmeldung: CSV/TSV und XLSX, Analyse statt Bereinigung,
bis etwa eine Million Zeilen, zuerst Apple Silicon und macOS 14 oder neuer.
Diese Annahmen sind keine bestätigten Nutzerentscheidungen.

## A – Fachlicher Zuschnitt

Zielnutzer: Fachanwender und Analysten, die Exporte vor Migration, Auswertung oder
Import in andere Systeme auf Qualität prüfen möchten.

Kernablauf: Datei öffnen → Importoptionen prüfen → Profil berechnen → auffällige
Spalte untersuchen → betroffene Zeilen anzeigen → Bericht exportieren.

Bildschirm: Seitenleiste mit Datenquelle; Inhaltsbereich mit Zeilenanzahl,
Spaltenprofilen und Vorschau; Importoptionen vor dem Start; sichtbarer Status,
Abbruch und verständliche Fehler. Detailnavigation folgt in C.

Erste fachliche Referenzfälle (synthetisch, keine echten Kundendaten):
1. Kundenexport: führende Nullen, fehlend vs. leer vs. Leerzeichen, doppelte IDs.
2. Umsatzexport: deutsche Dezimalzahlen, gemischte Werte und mehrzeiliger Text.
3. XLSX-Arbeitsmappe: mehrere Blätter, Text-IDs, Zahlen, leere Zellen.

Offen: reale Beispieldateien, wichtigste Datenquellen, tatsächliche Datenmengen,
Intel-Unterstützung, Mindest-macOS und späterer Vertriebsweg.

## B – Technischer Prototyp

- Native SwiftUI-App und gemeinsame ProfilingCore-Bibliothek, CLI für Tests.
- DuckDB über kleine C-API-Anbindung; dadurch explizite Kontrolle über Interrupt,
  Lebensdauer und die gebündelte Bibliotheksversion.
- CSV streng importieren, Rohwerte als Text erhalten. Keine still übersprungenen
  Parserfehler. NULL, leere Texte und Leerzeichen getrennt zählen.
- XLSX mit gebündelter Excel-Erweiterung; Blattname einstellbar. Keine Formel-
  Neuberechnung, keine Zusage für originalgetreue Excel-Anzeigeformate.
- Alle Profilkennzahlen auf vollständigem Import; Vorschau auf 100 Zeilen begrenzt.
- Zeilenanzahl, Null/leer/Whitespace, unterschiedliche nichtleere Werte,
  numerisch interpretierbare Werte und Min/Max/Mittelwert dieser Teilmenge.
- Off-main-thread-Berechnung, Abbruch auch während einer DuckDB-Abfrage.
- Tests mit Sollwerten und Benchmark für eine Million Zeilen. Hardware, Dateigröße,
  Spaltenzahl, Laufzeit und Speicherbedarf dokumentieren.

Abnahme B: CSV und XLSX funktionieren offline im App-Paket; erwartete Kennzahlen
stimmen; Parserfehler sind sichtbar; Abbruch funktioniert; Messwerte dokumentiert.

## C – Erste durchgängige App

Datei öffnen, Spaltenprofil auswählen, fehlende Werte anklicken, betreffende Zeilen
anzeigen. Die Detailansicht importiert die Quelldatei pro Auswahl lokal erneut und
zeigt maximal 200 Zeilen; dies schützt den Speicher, ist bei sehr großen Dateien aber
noch kein optimierter Cache. UX mit echten Beispieldaten abstimmen.

## D – Profiling und Regeln

Häufige Werte, Textmuster, Quartile, Fünf-Balken-Verteilung sowie Pflichtfeld,
Eindeutigkeit, Zahlenbereich und Regex sind umgesetzt. Regeln sind noch temporär pro
geöffneter Analyse; kombinierte Schlüssel, Datumsregeln und persistierte Regelsets
folgen. Kennzahlen klar definieren, Typverletzungen sichtbar halten und Regeln testen.

## E – Projekte und Berichte

Importkonfiguration, Regeln, Datenfingerabdruck und Analyseversion speichern,
öffnen und wiederholen. HTML-Berichte und Problemzeilen als CSV exportieren.

## F – Mac-Beta

Große/beschädigte Dateien und Dateiberechtigungen prüfen, Caches begrenzen,
App signieren/notarisieren und Installation auf zweitem Mac verifizieren.

## Spätere Erweiterungen

SQL-Datenquellen, Beziehungen zwischen Tabellen, Vergleich von Analyseläufen,
explizite Bereinigungsschritte und gegebenenfalls visueller Workflow-Editor.

## Referenzen

- https://datacleaner.github.io/docs/5.7.0/html/ch05.html
- https://duckdb.org/docs/current/clients/c/overview
- https://duckdb.org/docs/current/core_extensions/excel
