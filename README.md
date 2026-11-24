# Zettel

Schlanke, native Scratchpad-App für macOS (Arbeitstitel). Läuft unauffällig in der
Menüleiste, ist per Hotkey sofort da und speichert alles lokal.

> Status: **Alle neun Phasen umgesetzt und freigegeben.** Offene Punkte stehen in der ROADMAP. Siehe [ROADMAP.md](ROADMAP.md).

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
| `⌘T` | Zwischen Stapel und den 9 Plätzen wechseln |
| `⌘1`–`⌘9` | In den Plätzen: Platz wählen (im Stapel nur, wenn in den Einstellungen aktiviert; sonst `⌘1` = neueste Notiz) |
| `⌘⇧A` | Notiz archivieren |
| `⌘F` | Alle Notizen durchsuchen (Liste mit Filter; ↑/↓, Return öffnet, Esc schließt) |
| `⌘⇧F` | Suchen & Ersetzen in der aktuellen Notiz (`⌘G` / `⇧⌘G` weitersuchen) |
| `⌘B` / `⌘I` / `⌘U` / `⌘⇧X` | fett / kursiv / unterstrichen / durchgestrichen (Markdown: `**…**`, `_…_`, `<u>…</u>`, `~~…~~`) |
| `⌘/` | Zeilen aus-/einkommentieren (`//`, in `code`-Notizen das Kommentarzeichen der Sprache) |
| `⌘C` ohne Auswahl | ganze Notiz kopieren |
| `⌘↩` | Link unter dem Cursor (oder den ersten der Zeile) öffnen |
| `⌘⇧E` | Notiz exportieren (.md, .txt, PDF) |
| `⌘⇧L` | Notiz sperren / mit Touch ID anzeigen / Sperre aufheben |
| `⌘⇧R` | schreibgeschützt an/aus |
| `⌘+` / `⌘−` / `⌘0` | Textgröße |
| `⌘⇧K` | Checkbox abhaken / Zeile zur Checkbox machen |
| `⌘⇧M` | Listentyp wechseln: Text → • → ☐ → 1. → Text |
| `Tab` / `⇧Tab` | Listeneintrag ein-/ausrücken (mehrere markierte Zeilen: alle) |
| `⌥↑` / `⌥↓` | Zeile(n) verschieben |

### Plätze, Archiv, Papierkorb

- **Plätze:** 9 feste Notizen, die nie ablaufen und nicht im Stapel stehen. `⌘T` wechselt
  zum zuletzt benutzten Platz, `⌘[` / `⌘]` blättern zwischen den Plätzen, oben steht „Platz 3“.
- **Archiv** (`⌘⇧A`): raus aus dem Stapel, läuft nie ab, über die Suche („Archiv“) zurückholbar.
- **Papierkorb** (`⌘D`): über die Suche („Papierkorb“) wiederherstellbar – zurück auf den
  alten Platz, wenn der noch frei ist, sonst oben in den Stapel.
- **Ablauf:** Unveränderte Stapel-Notizen wandern nach einer einstellbaren Frist in den
  Papierkorb (Ende des Tages / 1 Woche / 1 Monat / 1 Jahr / nie – Standard: nie).
  Der Papierkorb leert sich nach 7 / 30 / 90 Tagen oder nie (Standard: 30 Tage).
- **Backups:** automatisch stündlich / täglich (Standard) / wöchentlich / nie, die letzten 10
  werden behalten, Ordner `…/Application Support/Zettel/Backups`. Wiederherstellen in den
  Einstellungen; vorher wird der aktuelle Stand zusätzlich gesichert.
- Ablauf, Papierkorb und Backups werden beim Start und beim Öffnen des Fensters geprüft –
  ohne eigenen Timer.

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
`math: Budget`. `/` am Zeilenanfang öffnet eine Auswahl. Weitertippen filtert sie
(`/pa` → `paste`), Return wählt; außerdem Ziffer, ↑/↓ oder Klick. Esc schließt und lässt den
`/` stehen; ein zweiter `/` ergibt einen `//`-Kommentar.

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

**Einheiten & Währungen** (in `math`, auch in `=`-Zeilen von `sum`/`avg`):

| Eingabe | Ergebnis |
|---|---|
| `10 cm to inch =` | `3,937 in` (auch `in`, `→`, `->`, `als`, `nach`) |
| `20°C in °F =` | `68 °F` |
| `strecke : 420 km` dann `strecke km to mi =` | Variablen mit Einheit |
| `5 km =` | `5 km` |
| `200 € in USD =` | mit Kurs aus den Einstellungen |

- Länge (mm … km, in, ft, yd, mi, nmi), Fläche (cm², m²/qm, ha, km², ft², acre),
  Volumen (ml … l, m³, TL, EL, cup, fl oz, pt, qt, gal), Masse (mg … t, oz, lb,
  Pfund = 500 g, stone), Temperatur (°C, °F, K). Alles aus lokalen Tabellen.
- Währungen: Codes (`EUR`, `USD`, …) und `€ $ £ ¥`. Kurse „1 EUR = …“ trägst du in den
  Einstellungen ein; eigene Kurse haben Vorrang. Ohne Kurs erscheint `Kurs USD?`.
- **Kurs-Update (Opt-in, standardmäßig aus):** lädt höchstens einmal am Tag die öffentlichen
  Referenzkurse der Europäischen Zentralbank (`ecb.europa.eu`, ca. 30 Währungen). Das ist der
  einzige Netzwerkzugriff von Zettel; es werden keine Daten gesendet (ephemere Sitzung, keine Cookies).

Zahlen: Dezimalzeichen und Tausendertrennzeichen laut Einstellungen (Standard: wie die
Region, z. B. `1.234,5`); `.` und `,` werden bei Eingaben auch sonst als Dezimalzeichen
erkannt, wenn sie nicht vor genau drei Ziffern stehen. Fehler werden kurz angezeigt
(`?`, `x?`, `÷ 0`), die App stürzt bei keiner Eingabe ab.

### Komfort (Phase 9)

- **Markdown:** Überschriften `#` bis `######`, fett, kursiv, unterstrichen, durchgestrichen,
  `` `Code` ``. Die Zeichen bleiben im Text (gespeichert wird Markdown). Standardmäßig sind sie
  ausgeblendet und nur in der Zeile mit dem Cursor sichtbar (Einstellung „Darstellung“).
- **`code`** / **`code: py`** (auch js/ts, swift, sh, sql, json, c/java/go/rust …): Text bleibt
  unverändert (keine Listen-Umwandlung), Monospace-Schrift, Syntaxfarben, Return übernimmt die Einrückung.
- **`paste`:** Solange aktiv, wird neu Kopiertes an die Notiz angehängt – auch bei geschlossenem
  Fenster. Geprüft wird nur der Änderungszähler der Zwischenablage, einmal pro Sekunde und nur im
  aktiven Modus. Inhalte von Passwort-Managern (`Concealed`/`Transient`) und eigene Kopien werden
  ignoriert. `Esc` in der Notiz beendet den Modus (erst das nächste Esc schließt das Fenster);
  `/paste` + Return startet ihn wieder. macOS fragt beim ersten Auslesen um Erlaubnis
  („Einfügen aus anderen Apps“, Datenschutz & Sicherheit) – dort „Immer erlauben“ wählen.
- **Lange Links** werden als „Anfang…Ende“ gezeigt, solange der Cursor nicht darin steht.
- **Export:** einzelne Notiz als Markdown, Text oder PDF (A4, mehrseitig); alle Notizen als ZIP
  (Menüleiste → „Alle Notizen exportieren …“, Ordner Stapel/Plätze/Archiv). Gesperrte und
  gelöschte Notizen werden nicht exportiert.
- **Sperren (`⌘⇧L`):** Der Inhalt ist erst nach Touch ID (oder Passwort) sichtbar, bis das Fenster
  schließt; in Suche und Export erscheint er nicht. **Hinweis:** Das ist ein Sichtschutz, keine
  Verschlüsselung – in der Datenbank und in Backups steht der Text weiterhin im Klartext.
- **Darstellung:** Hell/Dunkel/System, Textgröße, transparentes Fenster; der globale Hotkey ist
  unter „Allgemein“ frei wählbar (mindestens ⌘, ⌥ oder ⌃).

### Timer

Eine Zeile, die mit `timer` beginnt, startet mit `Return` am Zeilenende einen Timer.
Die Restzeit steht rechts in der Zeile. Timer laufen weiter, wenn das Fenster zu ist.

| Zeile | Wirkung |
|---|---|
| `timer` | Stoppuhr (`timer: Name` mit Namen) |
| `timer 10` | 10 Minuten |
| `timer 3.5`, `timer 3,5`, `timer 3:30` | 3:30 Minuten |
| `timer 21:15` | Countdown bis 21:15 (zweistellige Stunde 00–23, sonst Minuten:Sekunden) |
| `timer 5: Wäsche` | benannter Countdown |
| `timer pomo` | 25 Min. Arbeit / 5 Min. Pause, im Wechsel |
| `timer 5 1` | eigene Intervalle: 5 Min. Arbeit / 1 Min. Pause |
| `timer p` | pausieren / fortsetzen |
| `timer r` | neu starten |
| `timer s`, `timer 0` | stoppen |

- Steuerbefehle wirken auf den nächsten Timer darüber in derselben Notiz (sonst den
  zuletzt gestarteten) und verschwinden nach der Ausführung aus der Notiz.
- Laufende Timer stehen oben im Menüleisten-Menü (Pausieren, Neu starten, Stoppen).
- Restzeit in der Menüleiste (abschaltbar): in Minuten, in der letzten Minute sekundengenau.
- Bei Ablauf bzw. Phasenwechsel: Mitteilung und Ton, beides in den Einstellungen abschaltbar,
  Ton wählbar. Die Erlaubnis für Mitteilungen wird beim ersten Timer erfragt.
- Timer werden nicht über ein Beenden der App hinaus gespeichert.

## Projektstruktur

```
Zettel/
  App/          Einstiegspunkt (AppDelegate), Einstellungen (UserDefaults), UI-Texte
  HotKey/       Tastenkombination (KeyCombo) und globaler Hotkey (Carbon)
  Panel/        Notizfenster (NSPanel), Steuerung, Logik für Kürzel und Position
  Notes/        Notiz-Datensatz, SQLite-Speicher (GRDB), Stapel & Plätze, Keywords, Suche, Ablauf, Backups – ohne UI
  Search/       Such-Ansicht im Notizfenster (SwiftUI)
  Lists/        Listenzeilen, Markdown ↔ Anzeige, Listen- und Format-Operationen, Syntaxfarben, Links – ohne UI
  Math/         Tokenizer, Parser, Auswertung, Einheiten, Währungskurse, math-/sum-/avg-/count-Notizen – ohne UI
  Timer/        Timer-Befehle, Timer-Zustand, TimerCenter (UI-frei), Mitteilungen/Ton
  Editor/       Texteditor (NSTextView, TextKit 1), Listen-Darstellung, Undo pro Notiz, Wischen
  Support/      Kleine Helfer (Debouncer, Touch-ID-Abfrage)
  Settings/     Einstellungsfenster (Symbolleisten-Tabs, SwiftUI), Hotkey-Aufnahme
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
- **App Sandbox aktiv.** Entitlements: ausgehendes Netzwerk (seit Phase 8, nur für das Opt-in)
  und vom Nutzer gewählte Dateien (seit Phase 9, für den Export). macOS vergibt beides nicht bedingt. Genutzt wird es ausschließlich für das optionale Kurs-Update;
  ohne Opt-in öffnet Zettel keine einzige Verbindung (geprüft mit `lsof -i`).
- **Kein Polling.** Zustände (z. B. Login-Objekt) werden nur aktualisiert, wenn das
  Menü bzw. das Einstellungsfenster geöffnet wird.
- Das Einstellungsfenster wird erst bei Bedarf erzeugt und beim Schließen wieder freigegeben.
  Das Notizfenster wird beim ersten Einblenden erzeugt und danach nur versteckt, damit es sofort da ist.
- Autosave nutzt einen einmaligen Task, der nur nach einer Eingabe existiert – kein Dauer-Timer.
- Optischer Check des Editors: `TEST_RUNNER_ZETTEL_SNAPSHOT=1 xcodebuild … test` schreibt
  `editor-lists.png`, `editor-math.png`, `editor-sum.png`, `editor-count.png`, `editor-units.png`, `editor-format.png`, `editor-code.png`, `search.png` und `settings-*.png` in das temporäre Verzeichnis des Sandbox-Containers (Pfad steht im Log).
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
| Phase 6 (2026-11-23) | Release, universal | 0,0 % | 14 MB | 0 | 3 |
| Phase 7 (2026-11-23) | Release, universal | 0,0 % | 15 MB | 0 | 3 |
| Phase 8 (2026-11-23) | Release, universal | 0,0 % | 15 MB | 0 | 3 |
| Phase 9 (2026-11-23) | Release, universal | 0,0 % | 15 MB | 0 | 3 |
| Phase 9, `paste` aktiv | Debug (unoptimiert) | 0,0 % | 15 MB | 0 | 4 |
| Phase 6, Timer läuft | Debug (unoptimiert) | 0,0 % (0,6 % beim Minutenwechsel) | 16 MB | 0 | 4 |

Messumgebung: Apple M4, macOS 27.2. Ziel laut Anforderungen: ~0 % CPU, < 60 MB RAM.

Mit aktivem `paste`-Modus gemessen über `--args -ZettelMeasurePaste` (nur Debug-Build).
Mit laufendem Timer gemessen über `--args -ZettelMeasureTimer` (nur Debug-Build, startet einen
10-Minuten-Timer beim Start). Der Sekundentakt läuft nur, solange ein Timer aktiv ist; App Nap
ist dann ausgeschaltet, damit Ablauf und Ton pünktlich sind. Die Menüleiste zeigt bewusst nur
Minuten: Ein sekündliches Neuzeichnen kostete dort gemessen ca. 2,3 % CPU.

Hinweis: `ps` zeigt einen RSS von ~70 MB, weil darin gemeinsam genutzte
System-Frameworks (AppKit usw.) mitgezählt werden. Relevant ist der Footprint.

## Beim Login starten

Umgesetzt mit `SMAppService.mainApp`. macOS verlangt beim ersten Aktivieren ggf. eine
Bestätigung unter *Systemeinstellungen › Allgemein › Anmeldeobjekte*. In diesem Fall
zeigt das Menü einen Strich statt Häkchen, und ein Klick öffnet die Systemeinstellungen.
Für einen zuverlässigen Autostart sollte die App in `/Programme` liegen.

## Lizenz

Copyright (C) 2026 187Anton (https://github.com/187Anton)

Zettel ist freie Software: Du kannst sie unter den Bedingungen der
[GNU General Public License, Version 3](LICENSE) weitergeben und/oder verändern.
Zettel wird ohne jede Gewährleistung bereitgestellt; Details stehen in der Lizenz.

Verwendete Bibliothek: [GRDB.swift](https://github.com/groue/GRDB.swift) (MIT-Lizenz).
