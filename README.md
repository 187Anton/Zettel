# Zettel

Schlanke, native Scratchpad-App für macOS (Arbeitstitel). Läuft unauffällig in der
Menüleiste, ist per Hotkey sofort da und speichert alles lokal.

> Status: **Phase 5 – sum, avg, count.** Siehe [ROADMAP.md](ROADMAP.md).

## Voraussetzungen

- macOS 14 (Sonoma) oder neuer, Apple Silicon oder Intel
- Xcode 16 oder neuer (das Projekt nutzt synchronisierte Ordner, `objectVersion 77`)

## Bauen & Testen

```bash
xcodebuild -project Zettel.xcodeproj -scheme Zettel -destination 'platform=macOS' -derivedDataPath build/DerivedData test
```

```bash
xcodebuild -project Zettel.xcodeproj -scheme Zettel -configuration Release -destination 'generic/platform=macOS' -derivedDataPath build/DerivedData build
```

```bash
open build/DerivedData/Build/Products/Release/Zettel.app
```

Die App hat kein Dock-Icon. Nach dem Start erscheint ein Notiz-Symbol in der Menüleiste.

## Bedienung

| Kürzel | Wirkung |
|---|---|
| `⌥A` (global) | Notizfenster einblenden. Ist es schon im Fokus, wird es ausgeblendet. Ist es fixiert, aber nicht im Fokus, holt `⌥A` den Fokus zurück. |
| `⌘P` | Fenster im Vordergrund fixieren / Fixierung lösen (auch über das Pin-Symbol oben rechts) |
| `Esc`, `⌘W` | Fenster ausblenden |
| `⌘N` | Neue Notiz (eine leere aktuelle Notiz wird wiederverwendet) |
| `⌘[` / `⌘]` | Ältere / neuere Notiz. Auf deutscher Tastatur `⌘⌥5` / `⌘⌥6`; überall auch `⌥⌘←` / `⌥⌘→` |
| Zwei-Finger-Wischen | Nach rechts: ältere Notiz, nach links: neuere Notiz |
| `⌘1` | Stapel neu sortieren und neueste Notiz zeigen |
| `⌘⇧1` oder `⌥⌘↑` | Aktuelle Notiz nach vorn holen |
| `⌘D` | Aktuelle Notiz in den Papierkorb |
| `⌘Z` / `⇧⌘Z` | Widerrufen / Wiederholen – getrennt pro Notiz |
| `⌘⇧K` | Checkbox abhaken / Zeile zur Checkbox machen |
| `⌘⇧M` | Listentyp wechseln: Text → • → ☐ → 1. → Text |
| `Tab` / `⇧Tab` | Listeneintrag ein-/ausrücken (mehrere markierte Zeilen: alle) |
| `⌥↑` / `⌥↓` | Zeile(n) verschieben |

### Listen

Beim Tippen am Zeilenanfang werden Markdown-Kurzformen umgewandelt:

| Eingabe | Ergebnis |
|---|---|
| `[] ` oder `- [ ] ` | ☐ offene Checkbox |
| `[x] ` oder `- [x] ` | ☑ abgehakt |
| `- ` | • Aufzählungspunkt |
| `1. ` | nummerierte Liste |

- `⌘Z` direkt danach macht nur die Umwandlung rückgängig.
- `Return` setzt die Liste fort (Nummern zählen weiter). `Return` auf einem leeren Eintrag
  beendet die Liste bzw. rückt einen eingerückten Eintrag aus.
- `Backspace` direkt hinter dem Listenzeichen entfernt es.
- Klick auf eine Checkbox hakt ab; über Checkboxen erscheint der Pfeil statt des Textcursors.
- Einstellung „Abgehakte Einträge“: stehen lassen, nach unten verschieben (mit Untereinträgen,
  innerhalb der eigenen Liste) oder löschen. Gilt beim Abhaken; `⌘Z` holt alles zurück.
- Gespeichert wird reines Markdown (`- [ ] `, `- [x] `, `- `, `1. `, Einrückung mit Tabs).
  Kopieren liefert ebenfalls Markdown, Einfügen von Markdown-Listen zeigt sie als Listen an.

- Ohne Fixierung blendet sich das Fenster aus, sobald es den Fokus verliert.
- Fixier-Zustand, Größe und Position werden gespeichert. Liegt die gespeicherte Position
  auf einem nicht mehr angeschlossenen Bildschirm, erscheint das Fenster zentriert auf
  dem Bildschirm mit dem Mauszeiger.
- Notizen bilden einen Stapel, sortiert nach letzter Änderung. Die Reihenfolge wird beim
  Einblenden und mit `⌘1` aktualisiert, nicht beim Tippen – so springt die aktuelle Notiz
  beim Blättern nicht weg. Oben rechts steht die Position im Stapel (z. B. `2/5`).
- Gespeichert wird automatisch 500 ms nach der letzten Eingabe, außerdem beim Blättern,
  beim Ausblenden und beim Beenden.
- Leere Notizen werden nicht aufbewahrt: Verlässt man eine leere Notiz, wird sie gelöscht.
  Notizen mit Inhalt landen bei `⌘D` im Papierkorb (Wiederherstellen folgt in Phase 7).
- Einstellung „Mit neuer Notiz öffnen nach …“: War das Fenster so lange nicht im Fokus,
  beginnt es mit einer leeren Notiz.
- Das Fenster ist ein nicht-aktivierendes Panel: Die App, in der du gerade arbeitest,
  bleibt aktiv. Es erscheint auf allen Spaces und auch über Vollbild-Apps.
- Der Hotkey wird über Carbon `RegisterEventHotKey` registriert und braucht keine
  Bedienungshilfen-Berechtigung. Er ist in den Einstellungen gespeichert
  (`hotKey.toggleWindow`); eine Oberfläche zum Ändern folgt mit dem Einstellungsfenster.

### Keywords

Ein Keyword in der ersten Zeile schaltet die Notiz in einen Modus, optional mit Titel:
`math: Budget`. `/` am Zeilenanfang öffnet eine Auswahl (Ziffer, ↑/↓ + Return oder Klick
wählt; Esc schließt und lässt den `/` stehen; ein zweiter `/` ergibt einen `//`-Kommentar).

- **`list`** – jede Zeile wird automatisch eine Checkbox (Return und Tippen in eine leere
  Zeile). `/x` am Zeilenende hakt ab. Beim Wählen über `/` werden vorhandene Zeilen umgewandelt.
- **`math`** – Zeilen, die mit `=` enden, zeigen ihr Ergebnis rechtsbündig, live bei jeder Änderung.
- **`sum`** – Summe aller erkannten Zahlen, rechts in der Kopfzeile. Mehrere Zahlen in einer
  Zeile werden addiert (`Miete 800 Strom 60` → 860); bei Zeilen mit `=` zählt deren Ergebnis.
- **`avg`** – Durchschnitt aller erkannten Zahlen (`Ø …`); eine `=`-Zeile zählt als ein Wert.
- **`count`** – Einträge (nicht leere Zeilen), Zeilen, Wörter und Zeichen (ohne Listenzeichen).

Kommentare werden bei allen Auswertungen ignoriert und grau dargestellt: ganze Zeilen mit
`//` am Anfang und alles hinter ` //` (`Pfand 0,25 // zurück`). In einer Liste macht `//` direkt
hinter dem Listenzeichen aus dem Eintrag eine Kommentarzeile.
Zahlen im Text werden erkannt, auch mit Tausendertrennzeichen und Minus (`Rabatt -5`);
Zahlen direkt hinter Buchstaben (`H2O`) und Listennummern zählen nicht.

| Eingabe | Bedeutung |
|---|---|
| `2 + 3 * 4 =` | Punkt vor Strich, Klammern, `^` Potenz, `×`, `÷`, `:` |
| `preis : 25` | Variable (Groß-/Kleinschreibung egal), gilt für Zeilen darunter |
| `Preis pro Stück : 2,50` | Variablen dürfen aus bis zu 5 Wörtern bestehen |
| `ans * 2 =` | nächstes Ergebnis darüber |
| `total =` | Summe aller Ergebnisse darüber, ohne frühere `total`-Zeilen |
| `200 + 10% =` | 220 (Prozent vom linken Wert); `50%` allein = 0,5 |
| `sqrt(2)`, `round`, `abs`, `floor`, `ceil`, `ln`, `log`, `sin`, `cos`, `tan`, `pi` | Funktionen |
| `// …` | Kommentar, wird ignoriert |
| `Käse 3 * 1,99 =` | Text vor der Rechnung gilt als Beschriftung, auch vor Variablen (`Kosten preis * 3 =`) |

Zahlen: Dezimalzeichen und Tausendertrennzeichen laut Einstellungen (Standard: wie die
Region, z. B. `1.234,5`); `.` und `,` werden bei Eingaben auch sonst als Dezimalzeichen
erkannt, wenn sie nicht vor genau drei Ziffern stehen. Fehler werden kurz angezeigt
(`?`, `x?`, `÷ 0`), die App stürzt bei keiner Eingabe ab.

## Projektstruktur

```
Zettel/
  App/          Einstiegspunkt (AppDelegate), Einstellungen (UserDefaults), UI-Texte
  HotKey/       Tastenkombination (KeyCombo) und globaler Hotkey (Carbon)
  Panel/        Notizfenster (NSPanel), Steuerung, Logik für Kürzel und Position
  Notes/        Notiz-Datensatz, SQLite-Speicher (GRDB), Notizstapel, Keywords – ohne UI
  Lists/        Listenzeilen, Markdown ↔ Anzeige, Listen-Operationen – ohne UI
  Math/         Tokenizer, Recursive-Descent-Parser, Auswertung, math-Notizen – ohne UI
  Editor/       Texteditor (NSTextView, TextKit 1), Listen-Darstellung, Undo pro Notiz, Wischen
  Support/      Kleine Helfer (Debouncer)
  StatusBar/    Menüleisten-Icon und Menü
  LoginItem/    „Beim Login starten“ (SMAppService) – Logik getrennt von der UI
  Settings/     Einstellungsfenster (SwiftUI)
ZettelTests/    Unit-Tests (Swift Testing), laufen im App-Host
```

Neue Dateien in `Zettel/` bzw. `ZettelTests/` werden von Xcode automatisch
übernommen – die Projektdatei muss dafür nicht angepasst werden.

## Daten

Alle Notizen liegen in einer SQLite-Datenbank im Sandbox-Container:

```
~/Library/Containers/dev.zettel.Zettel/Data/Library/Application Support/Zettel/Zettel.sqlite
```

Einzige Fremdabhängigkeit ist [GRDB.swift](https://github.com/groue/GRDB.swift) (7.x,
per Swift Package Manager). Das Schema wird über GRDB-Migrationen versioniert.
Kann die Datenbank nicht geöffnet werden, warnt Zettel und läuft vorübergehend ohne Speichern.

## Grundsätze

- **Agent-App** (`LSUIElement = YES`): kein Dock-Icon, nur Menüleiste.
- **App Sandbox aktiv, kein Netzwerk-Entitlement.** Die App kann technisch keine
  Verbindungen aufbauen. (Ausnahme später: optionale Währungskurse, Phase 8, nur per Opt-in.)
- **Kein Polling.** Zustände (z. B. Login-Objekt) werden nur aktualisiert, wenn das
  Menü bzw. das Einstellungsfenster geöffnet wird.
- Das Einstellungsfenster wird erst bei Bedarf erzeugt und beim Schließen wieder freigegeben.
  Das Notizfenster wird beim ersten Einblenden erzeugt und danach nur versteckt, damit es sofort da ist.
- Autosave nutzt einen einmaligen Task, der nur nach einer Eingabe existiert – kein Dauer-Timer.
- Optischer Check des Editors: `TEST_RUNNER_ZETTEL_SNAPSHOT=1 xcodebuild … test` schreibt
  `editor-lists.png`, `editor-math.png`, `editor-sum.png` und `editor-count.png` in das temporäre Verzeichnis des Sandbox-Containers (Pfad steht im Log).
- Unit-Tests laufen im App-Host. Dort werden Menüleisten-Icon, Hotkey und die echte Datenbank
  nicht eingerichtet; Tests nutzen In-Memory-Datenbanken.

## Ressourcenverbrauch (Leerlauf)

Gemessen mit `top -pid <PID> -stats cpu,mem,idlew,threads,power` über 60 s und
`footprint <PID>`; „Speicher“ in der Aktivitätsanzeige entspricht dem Footprint.

| Stand | Build | CPU | Speicher (Footprint) | Idle-Wakeups | Threads |
|---|---|---|---|---|---|
| Phase 0 (2026-11-23) | Release, universal | 0,0 % | 13 MB | 0 | 3 |
| Phase 1 (2026-11-23) | Release, universal | 0,0 % | 13 MB | 0 | 3 |
| Phase 2 (2026-11-23) | Release, universal | 0,0 % | 14 MB | 0 | 3 |
| Phase 3 (2026-11-23) | Release, universal | 0,0 % | 14 MB | 0 | 3 |
| Phase 4 (2026-11-23) | Release, universal | 0,0 % | 14 MB | 0 | 3 |
| Phase 5 (2026-11-23) | Release, universal | 0,0 % | 14 MB | 0 | 3 |

Messumgebung: Apple M4, macOS 27.2. Ziel laut Anforderungen: ~0 % CPU, < 60 MB RAM.

Hinweis: `ps` zeigt einen RSS von ~70 MB, weil darin gemeinsam genutzte
System-Frameworks (AppKit usw.) mitgezählt werden. Relevant ist der Footprint.

## Beim Login starten

Umgesetzt mit `SMAppService.mainApp`. macOS verlangt beim ersten Aktivieren ggf. eine
Bestätigung unter *Systemeinstellungen › Allgemein › Anmeldeobjekte*. In diesem Fall
zeigt das Menü einen Strich statt Häkchen, und ein Klick öffnet die Systemeinstellungen.
Für einen zuverlässigen Autostart sollte die App in `/Programme` liegen.
