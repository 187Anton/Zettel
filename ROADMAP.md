# Roadmap

Details zu jeder Phase stehen in [CLAUDE.md](CLAUDE.md). Es wird immer nur eine Phase
umgesetzt; danach folgt manueller Test und Freigabe.

| Phase | Inhalt | Status |
|---|---|---|
| 0 | Grundgerüst: Agent-App, Menüleisten-Icon, Menü, Beim Login starten, Ressourcenmessung | ✅ freigegeben |
| 1 | Fenster & Hotkey (`⌥A`, `⌘P`, `Esc`, Größe/Position merken) | ✅ freigegeben |
| 2 | Notizen (Stapel, Autosave mit GRDB, Navigation, Papierkorb, Undo pro Notiz) | ✅ freigegeben (`⌘⇧1` nicht testbar, s. u.) |
| 3 | Checklisten in normalen Notizen | ✅ freigegeben |
| 4 | Keyword-System & Rechnen (`list`, `math`) | ✅ freigegeben |
| 5 | `sum`, `avg`, `count` | ✅ freigegeben |
| 6 | Timer | ✅ freigegeben |
| 7 | Notizverwaltung & Suche, Backups | ✅ freigegeben |
| 8 | Einheiten & Währungen | ✅ freigegeben |
| 9 | Komfort (Formatierung, Code, Paste-Modus, Export, Sperren, Themes) | ✅ freigegeben |

## Phase 9 – Notizen

- `InlineMarkup` / `InlineFormatting`: Markdown im Text, Formatierung als ein Undo-Schritt;
  `⌘/` mit Listenzeichen davor und Sprach-Kommentar in Code.
- `SyntaxHighlighter`: eigener kleiner Lexer (Schlüsselwörter, Strings, Zahlen, Zeilen- und
  Blockkommentare) ohne Fremdabhängigkeit; `code`-Notizen werden roh gespeichert und gezeigt.
- `PasteCollector`: Zwischenablage über `changeCount`, 1-Sekunden-Takt nur im aktiven Modus
  (ohne App-Nap-Sperre), ignoriert Passwort-Manager und eigene Kopien.
  Fund in den Tests: Endlosrekursion beim Starten des Modus (Benachrichtigung → Neuberechnung) – behoben.
- Lange Links über Glyph-Eigenschaften (`.null` + Platzhalter) gekürzt, Text unverändert.
- `NoteExporter`: Markdown/Text/PDF (Druckauftrag → echte Seitenumbrüche), ZIP über
  `NSFileCoordinator(.forUploading)` ohne Zip-Bibliothek; Entitlement „vom Nutzer gewählte Dateien“.
- Migration `v3_lockAndReadOnly`; Sperre per `LocalAuthentication` (Sichtschutz, keine Verschlüsselung).
- Einstellungen: neuer Tab „Darstellung“, Hotkey-Aufnahme unter „Allgemein“ (wird sofort neu registriert).
- 401 Tests. Leerlauf 0,0 %, 15 MB; mit aktivem `paste` ebenfalls 0,0 %.

### Nachträge nach dem Test

- `/paste` funktionierte nicht, wenn das Keyword ausgetippt wurde: Die Auswahl schloss sich
  beim ersten Buchstaben. Jetzt filtert Weitertippen die Auswahl, Return wählt
  (Ursache war auch die missverständliche Anleitung „Notiz mit `/paste` starten“).
  Geprüft: Zwischenablage-Erlaubnis („Immer erlauben“) und Takt im Hintergrund (< 1 s) waren in Ordnung.
- Neue Einstellung: Formatierungszeichen ausblenden (Standard an), sichtbar nur in der Cursor-Zeile.
- 410 Tests, darunter `/paste` + Return und der ganze Paste-Ablauf mit echter Zwischenablage.

## Offene Punkte nach Phase 9

- Timer werden beim Beenden der App nicht gespeichert.
- Wörter *mitten* in Rechnungen (`Miete 800 + Strom 60 =`) werden nicht ignoriert.
- Gesperrte Notizen sind nicht verschlüsselt (nur Sichtschutz); echte Verschlüsselung
  (Schlüssel in der Keychain) wäre ein eigenes Vorhaben.
- Eigenes App-Icon fehlt noch (Menüleiste nutzt ein SF Symbol).
- Die Punkte unter „Bewusst vorerst nicht geplant“ in CLAUDE.md (iCloud, Erweiterungen, …).

## Phase 8 – Notizen

- `Units.swift`: Einheitenkatalog (Länge, Fläche, Volumen, Masse, Temperatur mit Offset,
  Währungen), `UnitExpression` erkennt `<Ausdruck> <Einheit> to|in|→|als|nach <Einheit>` und
  `<Ausdruck> <Einheit>`; an Zahlen geklebte Einheiten (`10cm`, `20°C`, `€10`) werden getrennt.
- `MathEngine.evaluateLine`: erst Umrechnung, dann normale Rechnung, zuletzt „Wert mit Einheit“ –
  Variablen mit Einheitennamen (`m`, `t`, `l`) funktionieren weiter.
- Variablen dürfen Einheiten haben (`strecke : 420 km`); in `sum`/`avg` werden umgerechnete
  `=`-Zeilen mitgezählt.
- Währungen: eigene Kurse (Vorrang) + optional EZB-Referenzkurse, täglich höchstens einmal,
  beim Start bzw. Öffnen des Fensters geprüft; Einstellungs-Tab „Währungen“.
- Netzwerk-Entitlement hinzugefügt; ohne Opt-in keine offene Verbindung (lsof).
- 363 Tests (EZB-XML als eingebettete Probe, kein Netz in Tests).

## Phase 7 – Notizen

- Migration `v2_slotsAndArchive` (Spalten `slot`, `archivedAt`); mit einer echten v1-Datenbank
  getestet und auf der Nutzer-Datenbank erfolgreich gelaufen.
- `NoteStackModel`: Modus Stapel/Platz, `⌘T`, Plätze 1–9 (leere Plätze hinterlassen nichts),
  Archiv, Öffnen aus der Suche, Wiederherstellen aus Papierkorb/Archiv, Neu laden nach Restore.
- `NoteSearch`: Groß-/Kleinschreibung und Akzente egal, alle Wörter müssen vorkommen,
  Filter Alle/Stapel/Plätze/Archiv/Papierkorb, Titel und Textausschnitt.
- Such-Ansicht als Overlay im Notizfenster (SwiftUI), damit das Panel den Fokus behält.
  Esc schließt erst die Suche, dann das Fenster.
- `⌘⇧F`: Standard-Suchleiste mit Ersetzen (`NSTextFinder`); Esc darin lässt das Fenster offen.
- `NoteRetention`: Ablauf unveränderter Stapel-Notizen und Leeren des Papierkorbs.
- `BackupManager`: SQLite-Online-Backup, Intervall, 10 behalten, Wiederherstellen mit
  vorheriger Sicherung; Einstellungen jetzt in Tabs, mit Backup-Liste.
- 342 Tests, darunter echte Tastatur-Events für Suche und Suchleiste. Leerlauf 0,0 %, 15 MB.
- Nachtrag: Einstellungsfenster überlappte die Titelleiste (SwiftUI-`TabView`). Jetzt
  Standard-Einstellungsfenster mit Symbolleisten-Tabs (`NSTabViewController`, `.toolbar`),
  Höhe passt sich dem Tab an.

## Phase 6 – Notizen

- `TimerCommand`: Parser für alle Timer-Zeilen der Spezifikation; `HH:MM` mit zweistelliger
  Stunde ≤ 23 = Uhrzeit, sonst `M:SS` = Dauer; Name nach `:` (nicht zwischen Ziffern).
- `RunningTimer`: rein rechnerischer Zustand aus absoluten Zeiten (robust gegen Ruhezustand),
  Pause, Neustart, Intervall-Phasen; jeder Phasenwechsel wird genau einmal gemeldet.
- `TimerCenter`: alle Timer app-weit (überleben das Schließen des Fensters), Sekundentakt
  nur solange ein Timer läuft, App Nap währenddessen aus.
- Editor: `Return` am Ende einer Timer-Zeile startet; Steuerbefehle wirken auf den nächsten
  Timer darüber und werden aus der Notiz entfernt; Anzeige rechts in der Zeile, Aktualisierung
  nur bei sichtbarem Fenster.
- Menüleiste: Restzeit in Minuten (letzte Minute in Sekunden), Timer im Statusmenü mit
  Pausieren/Neu starten/Stoppen. Mitteilung und Ton einstellbar.
- Messung: Sekundengenaue Menüleiste kostete ~2,3 % CPU (Neuzeichnen der Menüleiste) →
  minutengenau, danach 0,0 %.
- 301 Tests.

### Bewusst offen

- Laufende Timer werden beim Beenden der App nicht gespeichert.

## Phase 5 – Notizen

- Keywords `sum`, `avg`, `count` (Auswahl über `/` mit Ziffern 3–5).
- `NumberExtraction`: erkennt Zahlen in Freitext mit denselben Regeln wie der Rechner
  (gemeinsames `scanNumber`), Minus nur als Vorzeichen am Wortanfang, keine Zahlen hinter Buchstaben.
- `AggregateSheet`: Ergebnis rechts in der Kopfzeile; `sum` addiert pro Zeile alle Zahlen,
  `avg` mittelt alle Einzelzahlen, `=`-Zeilen zählen mit ihrem Ergebnis (und zeigen es),
  `count` zählt Einträge, Zeilen, Wörter, Zeichen.
- `//`-Zeilen werden überall ignoriert und grau dargestellt.
- Beschriftung vor Rechnungen (`Käse 3 * 1,99 =`) wird ignoriert – in `sum`, `avg` und `math`.
  Nur reiner Text ohne Operatoren, damit Tippfehler in Variablen weiterhin gemeldet werden.
- 260 Tests. Leerlauf unverändert (0,0 % CPU, 14 MB).

### Nachträge nach dem Test

- Kommentare in Listen: `//` hinter einem Listenzeichen (das nach Return automatisch kommt)
  entfernt das Zeichen. Kommentare am Zeilenende (` // …`) werden ebenfalls ignoriert.
- Beschriftung vor Variablen (`Kosten preis * 3 =`): Beschriftungswörter dürfen keine
  bekannten Variablen sein; gemeldet wird der aussagekräftigste Fehler.
- Variablen mit mehreren Wörtern (`Preis pro Stück : 2,50`), längster Name gewinnt.
- 277 Tests, darunter Kommentar in Liste mit ⇧7 als echtem Tastendruck.

## Phase 4 – Notizen

- Rechen-Engine (`Math/MathEngine.swift`): eigener Tokenizer, Recursive-Descent-Parser,
  Auswerter mit typisierten Fehlern statt Abstürzen; Zufallseingaben-Test.
  Operatoren `+ - * / ^`, Klammern, Vorzeichen, Prozent (`200 + 10%`), Funktionen, `pi`.
- `MathSheet`: zeilenweise Auswertung mit Variablen (`name : wert`), `ans`, `total`
  (ohne frühere Totals), Kommentare `//`. Ergebnisse rechtsbündig gezeichnet; Platz dafür
  über `tailIndent` reserviert. Neuberechnung bei jeder Änderung und bei Einstellungsänderung.
- Keywords in der ersten Zeile (`KeywordHeader`), Kopfzeile hervorgehoben.
  Keyword-Auswahl nach `/` am Zeilenanfang als Overlay im Editor (kein eigenes Fenster).
- `list`-Modus: Return und Tippen in leere Zeilen erzeugen Checkboxen, `/x` hakt ab,
  eingefügte Zeilen werden Checkboxen.
- Einstellungen „Rechnen“: Dezimalstellen (automatisch bis 4 oder 0–6, kaufmännisch gerundet),
  Dezimalzeichen, Tausendertrennzeichen, mit Vorschau.
- Zusätzlich: `⌥⌘↑` holt die Notiz nach vorn (Alternative zu `⌘⇧1`).
- 233 Tests, davon echte Tastatur-Events für Auswahl und Rechnen. Leerlauf unverändert.

### Bewusst offen

- Wörter *mitten* in Rechenzeilen (`Miete 800 + Strom 60 =`) werden als unbekannte Variable
  gemeldet. Eine Beschriftung *vor* der Rechnung funktioniert seit Phase 5.
- Funktionen mit mehreren Argumenten (z. B. `round(x, 2)`) gibt es nicht, weil `,` auch
  Dezimalzeichen ist.

## Phase 3 – Notizen

- Notiz bleibt Markdown; der Editor zeigt ☐ / ☑ / • (`NoteFormat`, `ListLine`).
- Listen-Operationen als reine, getestete Funktionen (`ListEditing`, `LineDocument`):
  Kurzformen, Return, Backspace, Tab/⇧Tab, ⌘⇧K, ⌘⇧M, ⌥↑/⌥↓, Klick auf Checkbox.
  Jede Operation ist genau eine Textänderung = ein Undo-Schritt.
- Nummerierung wird bei Listen-Operationen angepasst; jede Folge zählt ab ihrer kleinsten Zahl.
- Checkboxen werden als SF Symbols gezeichnet (Platz über `NSLayoutManagerDelegate`
  reserviert), da ☐/☑ in der Systemschrift fehlen.
- Abgehakte Einträge: hängender Einzug, durchgestrichen; Einstellung stehen lassen /
  nach unten / löschen.
- Kopieren als Markdown, Einfügen von Markdown als Liste.
- 171 Tests. Leerlauf unverändert (0,0 % CPU, 14 MB).

### Nachtrag

- `⌘⇧1` (nach vorn holen) kollidiert beim Nutzer mit einem globalen Screenshot-Kürzel.
  Zusätzlich belegt: `⌥⌘↑` (passend zu `⌥⌘←` / `⌥⌘→`).
- Fix: `⌘Z` direkt nach einer Listen-Umwandlung nahm auch den getippten Text weg.

## Phase 2 – Notizen

- GRDB 7 als SPM-Abhängigkeit, Tabelle `note` (id, text, createdAt, updatedAt, touchedAt,
  trashedAt) mit Migration `v1_createNote`.
- `NoteStackModel`: Stapel nach `touchedAt`, Navigation, Neu, Nach-vorn, Papierkorb;
  leere Notizen werden verworfen statt gespeichert. Reihenfolge wird beim Einblenden
  und mit `⌘1` aktualisiert.
- `updatedAt` = letzte Inhaltsänderung (für den Auto-Ablauf in Phase 7),
  `touchedAt` = Position im Stapel (Bearbeiten oder `⌘⇧1`).
- Editor: `NSTextView` mit TextKit 1, reiner Text, ohne Auto-Ersetzungen; Autosave 500 ms;
  eigener `UndoManager` und Cursorposition pro Notiz.
- Kürzel `⌘N`, `⌘[`/`⌘]` (+ `⌘⌥5`/`⌘⌥6` für deutsche Tastatur, `⌥⌘←`/`⌥⌘→`), `⌘1`, `⌘⇧1`,
  `⌘D`; Zwei-Finger-Wischen; Positionsanzeige `2/5` in der Titelleiste.
- Hauptmenü (unsichtbar, solange die App nicht aktiv ist) liefert `⌘Z`, `⌘C`, `⌘V` usw.
- Einstellung „Mit neuer Notiz öffnen nach …“ (Nie / 1–60 Minuten).
- Menüleisten-Eintrag „Neue Notiz“ ist jetzt aktiv.
- Leerlauf: 0,0 % CPU, 14 MB Footprint, 0 Idle-Wakeups. 113 Tests.
- Bundle-ID bleibt `dev.zettel.Zettel` (bestimmt den Speicherort der Datenbank).

## Phase 1 – Notizen

- Globaler Hotkey `⌥A` über Carbon `RegisterEventHotKey` (`GlobalHotKey`), Kombination
  als `KeyCombo` in den Einstellungen gespeichert. Oberfläche zum Ändern folgt.
- Notizfenster als nicht-aktivierendes, schwebendes `NSPanel` (`.canJoinAllSpaces`,
  `.fullScreenAuxiliary`). Inhalt vorerst ein Platzhalter, der Editor kommt in Phase 2.
- `⌘P` / Pin-Symbol fixiert, `Esc` / `⌘W` / Schließen-Knopf blenden aus.
- Ohne Fixierung Ausblenden bei Fokusverlust.
- Fixier-Zustand, Größe und Position werden gespeichert und beim Einblenden geprüft
  (Bildschirm entfernt → Standardposition; zu groß/teilweise außerhalb → eingepasst).
- Menü: neuer Eintrag „Notizfenster öffnen ⌥A“.
- Leerlauf unverändert: 0,0 % CPU, 13 MB Footprint, 0 Idle-Wakeups.
- 59 Tests (Logik für Kürzel, Sichtbarkeit, Fensterposition, Einstellungen, Hotkey-Registrierung, Panel).

## Phase 0 – Notizen

- Xcode-Projekt mit App-Target `Zettel` und Test-Target `ZettelTests` (Swift Testing).
- Menü: Neue Notiz (deaktiviert bis Phase 2), Einstellungen …, Beim Login starten, Zettel beenden.
- Einstellungsfenster (SwiftUI) mit der Option „Beim Login starten“.
- App Sandbox aktiv, keine Netzwerk-Entitlements.
- Leerlauf gemessen: 0,0 % CPU, 13 MB Footprint, 0 Idle-Wakeups (siehe README).
- Bundle-ID `dev.zettel.Zettel` – vor Phase 2 festlegen, da der Datenspeicherort
  (Sandbox-Container) davon abhängt.
- Noch offen: eigenes App-Icon (Menüleiste nutzt vorerst das SF-Symbol `note.text`).
