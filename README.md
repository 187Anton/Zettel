# Zettel

Schlanke, native Scratchpad-App für macOS. Zettel wartet unauffällig in der Menüleiste,
ist per Tastenkürzel sofort da und speichert alles lokal auf deinem Mac.

- **Sofort da:** `⌥A` blendet das Notizfenster über jeder App ein, auch über Vollbild-Apps.
- **Notizstapel:** Notizen nach letzter Änderung sortiert, dazu 9 feste Plätze, Archiv und Papierkorb.
- **Listen:** Checkboxen, Aufzählungen und nummerierte Listen per Markdown-Kurzform.
- **Rechnen:** `math`-Notizen mit Variablen, Prozent, Einheiten und Währungen, live berechnet.
- **Auswerten:** `sum`, `avg` und `count` für schnelle Summen, Durchschnitte und Zählungen.
- **Timer:** Countdown, Stoppuhr und Pomodoro direkt aus einer Textzeile.
- **Komfort:** Markdown-Formatierung, Code mit Syntaxfarben, Zwischenablage-Sammler, Export, Touch-ID-Sperre.
- **Sparsam und privat:** im Leerlauf 0 % CPU und ca. 15 MB Speicher, kein Konto, keine Telemetrie,
  standardmäßig kein Netzwerkzugriff.

## Installation

Es gibt (noch) keine fertige Download-Version. Zettel wird mit Xcode gebaut.

**Voraussetzungen:** macOS 14 (Sonoma) oder neuer (Apple Silicon oder Intel), Xcode 16 oder neuer.

```bash
git clone https://github.com/187Anton/Zettel.git
```

```bash
cd Zettel
```

```bash
xcodebuild -project Zettel.xcodeproj -scheme Zettel -configuration Release -destination 'generic/platform=macOS' -derivedDataPath build/DerivedData build
```

```bash
cp -R build/DerivedData/Build/Products/Release/Zettel.app /Applications/
```

```bash
open /Applications/Zettel.app
```

Zettel hat kein Dock-Icon. Nach dem Start erscheint ein Notiz-Symbol in der Menüleiste.
Dort findest du „Neue Notiz“, die Einstellungen, „Beim Login starten“ und „Beenden“.

**Beim Login starten:** macOS verlangt beim ersten Aktivieren eventuell eine Bestätigung unter
*Systemeinstellungen › Allgemein › Anmeldeobjekte*. Solange sie fehlt, zeigt das Menü einen
Strich statt eines Häkchens; ein Klick darauf öffnet die Systemeinstellungen. Für einen
zuverlässigen Autostart sollte die App im Ordner `/Programme` liegen.

## Bedienung

| Kürzel | Wirkung |
|---|---|
| `⌥A` (global) | Notizfenster ein- und ausblenden (in den Einstellungen änderbar) |
| `⌘P` | Fenster im Vordergrund fixieren; ohne Fixierung blendet es sich bei Fokusverlust aus |
| `Esc`, `⌘W` | Fenster ausblenden |
| `⌘N` | Neue Notiz |
| `⌘[` / `⌘]` | Ältere / neuere Notiz (deutsche Tastatur: `⌘⌥5` / `⌘⌥6`, überall auch `⌥⌘←` / `⌥⌘→`) |
| Zwei-Finger-Wischen | Nach rechts: ältere Notiz, nach links: neuere Notiz |
| `⌘1` | Neueste Notiz |
| `⌘⇧1` oder `⌥⌘↑` | Aktuelle Notiz nach vorn holen |
| `⌘T` | Zwischen Stapel und den 9 Plätzen wechseln |
| `⌘1`–`⌘9` | In den Plätzen: Platz wählen (im Stapel optional, siehe Einstellungen) |
| `⌘D` | Notiz in den Papierkorb |
| `⌘⇧A` | Notiz archivieren |
| `⌘Z` / `⇧⌘Z` | Widerrufen / Wiederholen, getrennt pro Notiz |
| `⌘F` | Alle Notizen durchsuchen |
| `⌘⇧F` | Suchen und Ersetzen in der aktuellen Notiz (`⌘G` / `⇧⌘G` weitersuchen) |
| `⌘B` / `⌘I` / `⌘U` / `⌘⇧X` | Fett / kursiv / unterstrichen / durchgestrichen |
| `⌘/` | Zeilen aus- und einkommentieren |
| `⌘⇧K` | Checkbox abhaken bzw. Zeile zur Checkbox machen |
| `⌘⇧M` | Listentyp wechseln: Text → • → ☐ → 1. → Text |
| `Tab` / `⇧Tab` | Listeneintrag ein- und ausrücken |
| `⌥↑` / `⌥↓` | Zeilen verschieben |
| `⌘C` ohne Auswahl | Ganze Notiz kopieren |
| `⌘↩` | Link unter dem Cursor öffnen |
| `⌘⇧E` | Notiz exportieren (Markdown, Text, PDF) |
| `⌘⇧L` | Notiz mit Touch ID sperren bzw. entsperren |
| `⌘⇧R` | Schreibschutz an/aus |
| `⌘+` / `⌘−` / `⌘0` | Textgröße |

Das Fenster nimmt der App, in der du gerade arbeitest, nicht den Fokus weg, erscheint auf allen
Spaces und merkt sich Größe, Position und Fixierung.

## Notizen

- **Stapel:** Notizen sind nach letzter Änderung sortiert. Oben rechts steht die Position (z. B. `2/5`).
  Die Reihenfolge wird beim Einblenden und mit `⌘1` aktualisiert, nicht beim Tippen, damit die
  aktuelle Notiz beim Blättern nicht wegspringt.
- **Automatisch gespeichert:** kurz nach jeder Eingabe, beim Blättern, Ausblenden und Beenden.
  Leere Notizen werden nicht aufbewahrt.
- **Plätze:** 9 feste Notizen, die nie ablaufen und nicht im Stapel stehen. `⌘T` wechselt hin und
  zurück, `⌘[` / `⌘]` blättern zwischen den Plätzen.
- **Archiv** (`⌘⇧A`): raus aus dem Stapel, läuft nie ab, über die Suche zurückholbar.
- **Papierkorb** (`⌘D`): über die Suche wiederherstellbar. Er leert sich nach 7, 30 oder 90 Tagen
  oder nie (Standard: 30 Tage).
- **Ablauf (optional):** Unveränderte Notizen wandern nach einer einstellbaren Frist in den
  Papierkorb (Ende des Tages, Woche, Monat, Jahr oder nie; Standard: nie).
- **Frisch starten (optional):** Nach einer einstellbaren Zeit ohne Fokus öffnet Zettel mit einer leeren Notiz.
- **Suche** (`⌘F`): über alle Notizen, mit Filter für Stapel, Plätze, Archiv und Papierkorb.
- **Backups:** automatisch stündlich, täglich (Standard) oder wöchentlich; die letzten 10 bleiben
  erhalten. Wiederherstellen geht in den Einstellungen, vorher wird der aktuelle Stand zusätzlich gesichert.

## Listen

Am Zeilenanfang werden Markdown-Kurzformen beim Tippen umgewandelt:

| Eingabe | Ergebnis |
|---|---|
| `[] ` oder `- [ ] ` | ☐ offene Checkbox |
| `[x] ` oder `- [x] ` | ☑ abgehakte Checkbox |
| `- ` | • Aufzählungspunkt |
| `1. ` | Nummerierte Liste |

- `⌘Z` direkt danach macht nur die Umwandlung rückgängig.
- `Return` setzt die Liste fort, `Return` auf einem leeren Eintrag beendet sie.
- `Backspace` direkt hinter dem Listenzeichen entfernt es.
- Ein Klick auf eine Checkbox hakt sie ab.
- Abgehakte Einträge können stehen bleiben, nach unten wandern oder gelöscht werden (Einstellung).
- Gespeichert und kopiert wird reines Markdown; eingefügte Markdown-Listen erscheinen als Listen.

## Keywords

Ein Keyword in der ersten Zeile schaltet die Notiz in einen Modus, optional mit Titel, z. B.
`math: Budget`. Ein `/` am Zeilenanfang öffnet eine Auswahl; Weitertippen filtert sie
(`/pa` → `paste`), `Return` wählt.

| Keyword | Wirkung |
|---|---|
| `list` | Jede Zeile wird automatisch eine Checkbox; `/x` am Zeilenende hakt ab |
| `math` | Zeilen, die mit `=` enden, zeigen ihr Ergebnis rechtsbündig |
| `sum` | Summe aller Zahlen in der Notiz |
| `avg` | Durchschnitt aller Zahlen |
| `count` | Einträge, Zeilen, Wörter und Zeichen |
| `code`, `code: py` | Monospace-Schrift und Syntaxfarben (Python, JavaScript/TypeScript, Swift, Shell, Ruby, SQL, JSON, C-artige Sprachen) |
| `paste` | Sammelt alles, was du kopierst, in dieser Notiz |

Kommentare werden bei allen Auswertungen ignoriert und grau dargestellt: ganze Zeilen mit `//`
am Anfang und alles hinter ` //` (`Pfand 0,25 // zurück`).

### Rechnen mit `math`

| Eingabe | Bedeutung |
|---|---|
| `2 + 3 * 4 =` | Punkt vor Strich, Klammern, `^` Potenz, `×`, `÷` |
| `preis : 25` | Variable, gilt für alle Zeilen darunter |
| `Preis pro Stück : 2,50` | Variablen dürfen aus mehreren Wörtern bestehen |
| `Käse 3 * 1,99 =` | Text vor der Rechnung ist eine Beschriftung |
| `ans * 2 =` | Rechnet mit dem nächsten Ergebnis darüber weiter |
| `total =` | Summe aller Ergebnisse darüber, ohne frühere `total`-Zeilen |
| `200 + 10% =` | 220 (Prozent vom linken Wert) |
| `sqrt(2) =` | Funktionen: `sqrt`, `round`, `abs`, `floor`, `ceil`, `ln`, `log`, `sin`, `cos`, `tan`, `pi` |

Dezimal- und Tausendertrennzeichen richten sich nach den Einstellungen (Standard: wie die Region,
z. B. `1.234,5`). Fehler werden kurz neben der Zeile angezeigt.

### Einheiten und Währungen

| Eingabe | Ergebnis |
|---|---|
| `10 cm to inch =` | `3,937 in` (statt `to` auch `in`, `→`, `als`, `nach`) |
| `20°C in °F =` | `68 °F` |
| `strecke : 420 km`, dann `strecke km to mi =` | Variablen mit Einheit |
| `200 € in USD =` | Umrechnung mit eingetragenem Kurs |

- **Einheiten:** Länge, Fläche, Volumen, Masse und Temperatur, metrisch und angloamerikanisch.
- **Währungen:** Codes (`EUR`, `USD`, …) und die Zeichen `€ $ £ ¥`. Kurse trägst du in den
  Einstellungen ein.
- **Kurs-Update (optional, standardmäßig aus):** lädt höchstens einmal am Tag die öffentlichen
  Referenzkurse der Europäischen Zentralbank. Das ist der einzige Netzwerkzugriff von Zettel;
  dabei werden keine Daten gesendet. Eigene Kurse haben Vorrang.

### Sammeln mit `paste`

Solange eine `paste`-Notiz aktiv ist, wird neu Kopiertes automatisch angehängt, auch bei
geschlossenem Fenster. Inhalte aus Passwort-Managern werden ignoriert. `Esc` in der Notiz beendet
den Modus. macOS fragt beim ersten Mal um Erlaubnis (*Datenschutz & Sicherheit › Einfügen aus
anderen Apps*); dort „Immer erlauben“ wählen.

## Timer

Eine Zeile, die mit `timer` beginnt, startet mit `Return` einen Timer. Die Restzeit steht rechts
in der Zeile und optional in der Menüleiste. Timer laufen weiter, wenn das Fenster geschlossen ist.

| Zeile | Wirkung |
|---|---|
| `timer` | Stoppuhr (`timer: Name` mit Namen) |
| `timer 10` | 10 Minuten |
| `timer 3.5`, `timer 3:30` | 3 Minuten 30 Sekunden |
| `timer 21:15` | Countdown bis 21:15 Uhr |
| `timer 5: Wäsche` | Benannter Countdown |
| `timer pomo` | Pomodoro: 25 Minuten Arbeit, 5 Minuten Pause, im Wechsel |
| `timer 5 1` | Eigene Intervalle: 5 Minuten Arbeit, 1 Minute Pause |
| `timer p` | Pausieren / fortsetzen |
| `timer r` | Neu starten |
| `timer s`, `timer 0` | Stoppen |

- Laufende Timer lassen sich auch im Menüleisten-Menü pausieren, neu starten und stoppen.
- Bei Ablauf gibt es eine Mitteilung und einen Ton, beides abschaltbar, der Ton ist wählbar.
- Timer überstehen kein Beenden der App.

## Weitere Funktionen

- **Markdown:** Überschriften (`#` bis `######`), **fett**, _kursiv_, unterstrichen, durchgestrichen
  und `` `Code` ``. Die Markierungen sind standardmäßig nur in der Zeile mit dem Cursor sichtbar.
- **Lange Links** werden gekürzt angezeigt, solange der Cursor nicht darin steht.
- **Export:** einzelne Notiz als Markdown, Text oder PDF; alle Notizen auf einmal als ZIP
  (Menüleiste › „Alle Notizen exportieren …“).
- **Sperren** (`⌘⇧L`): Der Inhalt ist erst nach Touch ID oder Passwort sichtbar und erscheint
  nicht in Suche und Export. **Hinweis:** Das ist ein Sichtschutz, keine Verschlüsselung; in der
  Datenbank und in Backups steht der Text weiterhin im Klartext.
- **Darstellung:** Hell, Dunkel oder wie das System, Textgröße und optional ein transparentes Fenster.

## Datenschutz und Ressourcen

- **Alles lokal:** Notizen liegen in einer SQLite-Datenbank im Sandbox-Container von Zettel:
  `~/Library/Containers/dev.zettel.Zettel/Data/Library/Application Support/Zettel/`.
  Kein Konto, keine Telemetrie, keine Cloud.
- **Kein Netzwerk:** Ohne das optionale Kurs-Update öffnet Zettel keine einzige Verbindung.
- **Sparsam:** Kein Polling und keine Dauer-Timer. Gemessen auf einem Apple M4:

| Zustand | CPU | Speicher | Idle-Wakeups |
|---|---|---|---|
| Leerlauf | 0,0 % | ca. 15 MB | 0 |
| Timer läuft | 0,0 % | ca. 16 MB | 0 |
| `paste` aktiv | 0,0 % | ca. 15 MB | 0 |

Gemessen wurde der Footprint, der dem Wert „Speicher“ in der Aktivitätsanzeige entspricht.

## Entwicklung

Zettel ist in Swift geschrieben: AppKit für Fenster und Editor, SwiftUI für die Einstellungen.
Einzige Fremdabhängigkeit ist [GRDB.swift](https://github.com/groue/GRDB.swift) für SQLite.
Die Logik (Rechnen, Listen, Timer, Notizverwaltung) ist von der Oberfläche getrennt und mit
Unit-Tests abgedeckt.

Tests ausführen:

```bash
xcodebuild -project Zettel.xcodeproj -scheme Zettel -destination 'platform=macOS' -derivedDataPath build/DerivedData test
```

```
Zettel/
  App/          Einstiegspunkt, Einstellungen, UI-Texte, Hauptmenü
  HotKey/       Globaler Hotkey (Carbon)
  Panel/        Notizfenster und Tastenkürzel
  Notes/        Notizen, Datenbank, Stapel und Plätze, Keywords, Suche, Backups, Export
  Lists/        Listen, Markdown, Formatierung, Syntaxfarben, Links
  Math/         Rechen-Engine, Einheiten, Währungen, sum/avg/count
  Timer/        Timer-Befehle, Ablauf, Mitteilungen
  Editor/       Texteditor (NSTextView) und Darstellung
  Search/       Suchansicht
  Settings/     Einstellungsfenster
  StatusBar/    Menüleisten-Symbol und Menü
  LoginItem/    Beim Login starten
  Support/      Kleine Helfer
ZettelTests/    Unit-Tests (Swift Testing)
```

Geplante Erweiterungen und bekannte Einschränkungen stehen in der [ROADMAP](ROADMAP.md).

## Lizenz

Copyright (C) 2026 187Anton (https://github.com/187Anton)

Zettel ist freie Software: Du kannst sie unter den Bedingungen der
[GNU General Public License, Version 3](LICENSE) weitergeben und/oder verändern.
Zettel wird ohne jede Gewährleistung bereitgestellt; Details stehen in der Lizenz.

Verwendete Bibliothek: [GRDB.swift](https://github.com/groue/GRDB.swift) (MIT-Lizenz).
