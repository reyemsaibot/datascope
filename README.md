# DataScope

Native Mac-App für lokales Data Profiling. Arbeitsname; technischer Prototyp der
Etappen A/B. Der dauerhaft gespeicherte Ausbauplan steht in [docs/PLAN.md](docs/PLAN.md).
Bestehende Projekte im übergeordneten Workspace werden nicht verändert.

## Start

Voraussetzung: Apple Silicon, macOS 14+, Xcode/Swift 6 und Python 3 für Testdaten.

```sh
cd DataScope
./scripts/setup.sh
./scripts/build-app.sh
open output/DataScope.app
```

Setup lädt einmalig DuckDB 1.4.3 und die passende Excel-Erweiterung von den
offiziellen Downloadservern und prüft die fixierten SHA-256-Werte. Der Build und
das anschließende Profiling benötigen kein Netzwerk. Vendor-Dateien und die App
sind generierte Artefakte und nicht für Git vorgesehen.

## Bedienung

1. Datei öffnen, beispielsweise `Fixtures/customers.csv` oder `Fixtures/workbook.xlsx`.
2. Überschriften und Trennzeichen bzw. Blattnamen einstellen. Ohne Blattnamen wird
   das erste Blatt gelesen. Für `sales.csv` „Deutsche Zahlen“ einschalten.
3. „Profil berechnen“ starten. Ein laufender Import oder eine Analyse lässt sich abbrechen.
4. Kennzahlen und die auf 100 Zeilen begrenzte Datenvorschau ansehen.

Alle Kennzahlen betreffen den vollständigen Import, nicht eine Stichprobe.
Die Beispieldateien sind synthetisch; reale Anwenderdaten wurden nicht verwendet.

## Umfang und Grenzen

- CSV/TSV: UTF-8, explizites oder automatisch erkanntes Trennzeichen. Rohwerte als
  Text; führende Nullen bleiben erhalten. Unzitierte leere Felder = NULL, zitierte
  leere Felder = leerer Text; Whitespace wird separat gezählt.
- XLSX: Blattname, Rohzellwerte als Text und vollständiges Weiterlesen hinter leeren
  Zeilen. Kein XLS, keine Neuberechnung von Formeln. Anzeigeformate (z. B. numerische
  IDs mit Format `00000`, Datumsformatierung) werden nicht originalgetreu abgebildet.
  Nur als Text gespeicherte Excel-IDs behalten garantiert ihre führenden Nullen.
- Unterschiedliche Werte: exakte Anzahl nichtleerer Rohwerte, case-sensitive.
- Zahlen: endliche DOUBLE-Werte; Min/Max/Mittelwert nur dieser Teilmenge. Für deutsche
  Zahlen gelten Dezimalkomma und optional korrekt gruppierte Tausenderpunkte.
  Die Spaltentypen unterscheiden Ganzzahl, Dezimalzahl, Datum, Text und leer. Ein
  Typ erscheint nur, wenn alle befüllten Werte dazu passen; führende Nullen machen
  eine sonst numerische ID zu Text. Erkannt werden ISO-Datum (`JJJJ-MM-TT`) sowie
  `TT.MM.JJJJ` und `TT/MM/JJJJ`. „Max. Länge“ misst den längsten Rohwert.
- Parserfehler brechen den Import sichtbar ab. Fehlerzeilen-Export folgt später.
- Speicher: DuckDB-Pufferbudget 512 MB, vier Threads, temporäre Auslagerung auf Disk.
  Das Budget ist keine harte Grenze für den gesamten Prozess. Temporäre Dateien
  werden beim normalen Abschluss/Abbruch entfernt; Crash-Aufräumen folgt in F.
- Keine Projekte, Regeln, Filter-Drilldowns oder Berichte in dieser Etappe.
- Lokales, ad-hoc-signiertes App-Paket; noch nicht notarisiert oder auf einem zweiten
  Mac validiert. Intel-Unterstützung ist noch nicht eingerichtet.

## Tests und Messung

```sh
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/datascope-clang"
export SWIFTPM_MODULECACHE_OVERRIDE="${TMPDIR:-/tmp}/datascope-swift"
swift test --disable-sandbox
python3 scripts/fixtures.py --million
./scripts/build-app.sh
python3 scripts/benchmark.py
```

CLI mit JSON-Ausgabe (nützlich für reproduzierbare Vergleiche):

```sh
.build/release/profile Fixtures/customers.csv
.build/release/profile Fixtures/sales.csv --delimiter ';' --decimal-comma
.build/release/profile Fixtures/workbook.xlsx --sheet Umsatz
.build/release/profile Fixtures/million.csv --cancel-after 0.1
```

## Architektur

`ProfilingCore`: eigenständige DuckDB-Verbindung pro Lauf, C-API, explizite
Lebensdauer und thread-sicherer Interrupt-Handle. Synchrone Engine läuft im
App-Worker, nicht auf dem MainActor. `DataScope`: SwiftUI-Oberfläche.
`ProfileCLI`: dieselbe Engine ohne UI. Engine und Excel-Erweiterung sind im App-Paket
gebündelt; automatisches Installieren/Laden weiterer Erweiterungen ist abgeschaltet.

DuckDB ist MIT-lizenziert: https://github.com/duckdb/duckdb/blob/v1.4.3/LICENSE
DataCleaner dient als funktionale Referenz; sein Code wird nicht eingebunden.
