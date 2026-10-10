# DataScope

DataScope ist eine native macOS-App für lokales Data Profiling. Sie hilft dabei,
CSV-, TSV- und Excel-Dateien vor einem Import, einer Auswertung oder einer Migration
zu prüfen. Die Analyse läuft auf dem Mac; während einer Analyse werden keine Daten an
einen Dienst übertragen.

> **Status:** Technischer Prototyp für Apple Silicon mit macOS 14 oder neuer. Die App
> ist lokal ad-hoc signiert und noch nicht notarisiert.

## Was DataScope prüft

- Zeilen- und Spaltenanzahl über den vollständigen Import
- `NULL`, leerer Text und Text, der nur aus Whitespace besteht
- Anzahl unterschiedlicher nichtleerer Rohwerte
- numerisch interpretierbare Werte sowie Minimum, Maximum und Mittelwert
- Spaltentyp: Ganzzahl, Dezimalzahl, Datum, Text oder leer
- maximale Länge des Rohwerts je Spalte
- Datenvorschau mit bis zu 100 Zeilen

Führende Nullen bleiben erhalten. Eine ID wie `00123` wird deshalb als Text
behandelt, auch wenn sie technisch als Zahl gelesen werden könnte.

## Voraussetzungen

- Apple-Silicon-Mac (`arm64`)
- macOS 14 oder neuer
- Xcode Command Line Tools mit Swift 6
- Python 3 für das Setup und die synthetischen Beispieldateien
- Internetzugang **nur** für das einmalige Setup

## Installation und Start

Repository klonen und in den Projektordner wechseln:

```sh
git clone https://github.com/reyemsaibot/datascope.git
cd datascope
```

Beim ersten Start lädt das Setup DuckDB 1.4.3 und die Excel-Erweiterung, prüft deren
SHA-256-Prüfsummen und erzeugt synthetische Beispieldateien:

```sh
./scripts/setup.sh
```

Danach die App bauen und öffnen:

```sh
./scripts/build-app.sh
open output/DataScope.app
```

Das Ergebnis liegt unter `output/DataScope.app`. Nach dem Setup funktionieren Build
und Profiling ohne Netzwerkverbindung.

## Erste Analyse in der App

1. **Datei öffnen …** wählen (`⌘O`).
2. Eine CSV-, TSV- oder XLSX-Datei auswählen.
3. Die Importoptionen prüfen:
   - **Erste Zeile enthält Überschriften** deaktivieren, wenn die Datei keine Header hat.
   - Für CSV/TSV das Trennzeichen automatisch erkennen lassen oder explizit auswählen.
   - Für Excel bei Bedarf den Blattnamen eintragen; ein leeres Feld verwendet das erste Blatt.
   - **Deutsche Zahlen** aktivieren, wenn Werte etwa als `1.234,50` vorliegen.
4. **Profil berechnen** auswählen. Der Lauf kann über **Abbrechen** beendet werden.
5. Das Spaltenprofil und die Datenvorschau prüfen.

Alle Kennzahlen beziehen sich auf die gesamte Datei. Nur die Vorschau ist auf 100
Zeilen begrenzt.

### Spaltenprofil lesen

| Spalte | Bedeutung |
| --- | --- |
| `NULL` | Fehlender Datenbankwert bzw. nicht zitierter leerer CSV-Wert |
| `Leer` | Explizit leerer Text, etwa `""` |
| `Whitespace` | Wert enthält nach dem Entfernen von Leerzeichen nichts mehr |
| `Verschieden` | Anzahl unterschiedlicher, nichtleerer Rohwerte |
| `Typ` | Einheitlicher Typ aller befüllten Werte |
| `Max. Länge` | Länge des längsten Rohwerts |
| `Numerisch` | Anzahl der Werte, die als endliche Zahl interpretierbar sind |
| `Min / Max / Ø` | Kennzahlen der numerisch interpretierbaren Werte |

Ein Typ wird nur dann als Ganzzahl, Dezimalzahl oder Datum ausgegeben, wenn **alle**
befüllten Werte dazu passen. Bei einer Spalte mit `10`, `20` und `oops` lautet der Typ
deshalb **Text**, während `Numerisch` weiterhin `2` anzeigt.

Erkannte Datumsformate sind `JJJJ-MM-TT`, `TT.MM.JJJJ` und `TT/MM/JJJJ`.

## Unterstützte Dateien und Grenzen

| Format | Unterstützung |
| --- | --- |
| CSV / TSV | UTF-8, automatisch oder manuell gewähltes Trennzeichen, Rohwerte bleiben Text |
| XLSX | Arbeitsblatt auswählbar, gespeicherte Zellwerte werden auch nach Leerzeilen gelesen |
| XLS | Nicht unterstützt |

- Excel-Formeln werden nicht neu berechnet. Excel-Anzeigeformate, etwa eine numerische
  ID mit Anzeigeformat `00000`, können nicht originalgetreu wiederhergestellt werden.
- Deutsche Zahlen werden bei aktivierter Option als Dezimalkomma mit korrekt gruppierten
  Tausenderpunkten interpretiert.
- Parserfehler brechen den Import mit einer sichtbaren Fehlermeldung ab; fehlerhafte
  Zeilen werden nicht stillschweigend übersprungen.
- DataScope ist ein Analysewerkzeug. Regeln, Histogramme, Problemzeilen-Navigation,
  Projekte und Berichts-Export folgen in späteren Etappen.

## Beispiele und Kommandozeile

Das Setup erzeugt synthetische Dateien in `Fixtures/`. Die Profiling-Engine kann auch
ohne die Oberfläche genutzt werden und schreibt dann JSON nach stdout:

```sh
swift build -c release --disable-sandbox

.build/release/profile Fixtures/customers.csv
.build/release/profile Fixtures/sales.csv --delimiter ';' --decimal-comma
.build/release/profile Fixtures/workbook.xlsx --sheet Umsatz
```

Verfügbare Optionen:

```text
profile DATEI [--delimiter ';'] [--sheet NAME] [--decimal-comma] [--no-header] [--cancel-after SEKUNDEN]
```

## Entwicklung und Tests

```sh
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/datascope-clang"
export SWIFTPM_MODULECACHE_OVERRIDE="${TMPDIR:-/tmp}/datascope-swift"
swift test --disable-sandbox
```

Für die definierte Million-Zeilen-Messung:

```sh
python3 scripts/fixtures.py --million
python3 scripts/benchmark.py
```

Der aktuelle Prüfstand und bekannte Grenzen sind in
[docs/VALIDATION.md](docs/VALIDATION.md) dokumentiert. Der geplante Ausbau steht in
[docs/PLAN.md](docs/PLAN.md).

## Architektur

`DataScope` ist die SwiftUI-Oberfläche. `ProfilingCore` enthält die Profiling-Logik
und verwendet DuckDB über dessen C-API. `ProfileCLI` verwendet dieselbe Engine für
reproduzierbare JSON-Ausgaben. Import und Analyse laufen außerhalb des MainActor;
die Oberfläche bleibt dabei bedienbar und kann eine DuckDB-Abfrage unterbrechen.

DuckDB ist unter der MIT-Lizenz verfügbar:
<https://github.com/duckdb/duckdb/blob/v1.4.3/LICENSE>. DataCleaner ist eine
funktionale Referenz; sein Code wird nicht eingebunden.
