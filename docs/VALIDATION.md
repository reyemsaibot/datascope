# Prüfung der Etappen A/B

10. Oktober 2026, lokaler technischer Prototyp. Kein Produktionsrelease.

## Verifiziert

- Swift-6-Debug- und Release-Build erfolgreich.
- Zehn XCTest-Tests bestanden: CSV-Rohwerte, getrennte NULL/leer/Whitespace-Zählung,
  deutsche Zahlen, XLSX-Blattwahl und Weiterlesen nach Leerzeile, Parserfehler,
  SQL-Sonderzeichen in Dateinamen/Spaltennamen, leere Tabellen, begrenzte Vorschau,
  Abbruch vor Start und laufender Abfrage mit anschließend erfolgreichem Neulauf sowie
  Typen für Ganzzahl, Dezimalzahl, Text, leere Spalten und drei Datumsformate.
- Der Release-Build vom 10. Oktober enthält die Spalten „Typ“ und „Max. Länge“.
  `plutil -lint` und `codesign --verify --deep --strict` bestanden. Die gebaute CLI
  bestätigte für `customers.csv`, dass die ID mit führenden Nullen Text bleibt.
- Build 8 enthält das transparente Seitenleisten-Logo und Spaltendetails nach der
  Auswahl einer Profilzeile; die erste Spalte ist nach der Analyse vorausgewählt.
  Der gebündelte Build wurde geöffnet, `customers.csv` gewählt und vollständig
  analysiert. Die UI zeigte 4 Zeilen, 4 Spalten, 5 leere/fehlende Zellen und die
  erwarteten Spaltenwerte. Die UI-Automation brach beim separaten Klick auf eine
  Tabellenzeile ab; dieser konkrete Klickpfad bleibt praktisch ungeprüft.
- Der Abbruchtest unterbricht eine echte DuckDB-Abfrage über zehn Milliarden
  generierte Werte nach etwa 0,1 Sekunden, Test einschließlich neuem Import ca. 0,12 s.
- UI-Prüfung im gebündelten App-Paket: customers.csv → 4 Zeilen, 4 Spalten,
  5 leere/fehlende Zellen; workbook.xlsx → 4 Zeilen, 3 Spalten, 4 leere/fehlende
  Zellen. Erwartete Einzelkennzahlen sichtbar. Screenshot des CSV-Ergebnisses geprüft.
- DuckDB und die Excel-Erweiterung liegen im App-Paket. Dynamische Bibliothek wird
  relativ zum App-Paket geladen, Excel-Extension aus den Bundle-Ressourcen.
  Automatische Extension-Downloads sind abgeschaltet. Kein externer Dienst nötig.
- Ad-hoc-Codesign-Prüfung erfolgreich. Noch keine Notarisierung oder Zweit-Mac-Prüfung.

## Erste Leistungsmessung

Hardware: MacBook Pro, Apple M4, 16 GB RAM, macOS 26.6.2, arm64.
DuckDB 1.4.3, Release-Build, vier Threads, 512 MB DuckDB-Pufferbudget.

| Messwert | Ergebnis |
|---|---:|
| Zeilen / Spalten | 1.000.000 / 8 |
| CSV-Dateigröße | 75.779.047 Bytes |
| Import einschließlich Engine-Initialisierung | 0,366 s |
| Import und vollständiges Profil | 0,680 s |
| Gesamter CLI-Prozess einschließlich Start und JSON-Ausgabe | 1,060 s |
| Peak RSS des Prozesses | 323.518.464 Bytes (ca. 309 MiB) |

Zeilenanzahl, acht Spalten, eine Million unterschiedliche IDs, 100.000 fehlende
E-Mail-Werte und die Vorschaugrenze wurden zusätzlich automatisch geprüft.
Rohdaten: [benchmark.json](benchmark.json). Reproduktion: `scripts/benchmark.py`.

Eine synthetische Einzelmessung mit ungeleertem OS-Dateicache. Keine allgemeine
Leistungsgarantie für beliebige breite Tabellen, große Textfelder oder Excel.

Vorläufiges Regressionsziel für genau diese Referenzdatei auf diesem Mac: vollständige
Analyse unter 5 Sekunden, Peak RSS unter 1 GB, Abbruch innerhalb von 3 Sekunden.
Die UI soll währenddessen bedienbar bleiben. Andere Datensätze separat messen.

## Bewusste Grenzen / Folgearbeit

- A verwendet noch Arbeitsannahmen und synthetische Dateien. Echte Anforderungen
  zu Quellen, Größe, Datenformaten und Mindest-macOS müssen damit abgeglichen werden.
- CSV-Encoding vorerst UTF-8. Keine Zeichensatzwahl oder Import-Vorschau vor Analyse.
- Die Typbestimmung ist streng: nur vollständig passende befüllte Werte werden als
  Ganzzahl, Dezimalzahl oder Datum eingestuft. Gemischte oder fehlerhafte Werte bleiben
  Text; die Anzahl numerisch interpretierbarer Werte zeigt die Abweichung. Unterstützt
  sind ISO-Datum, `TT.MM.JJJJ` und `TT/MM/JJJJ`; weitere regionale Datumsformate,
  Zeitstempel, Histogramme, Regeln, Problemzeilen-Navigation und Projektpersistenz
  folgen in C–E.
- XLSX-Import liest gespeicherte Werte. Excel-Anzeigeformate, Formelberechnung,
  Shared-Formula-Sonderfälle und sehr große Arbeitsmappen sind nicht vollständig geprüft.
- Intel, App Sandbox, Security-scoped Bookmarks, Notarisierung, Crash-Aufräumen
  und Installation auf einem zweiten Mac folgen in F.
- Keine Wiederverwendung oder Kompatibilitätszusage für DataCleaner-Jobdateien.
