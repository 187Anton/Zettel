# Roadmap

Details zu jeder Phase stehen in [CLAUDE.md](CLAUDE.md). Es wird immer nur eine Phase
umgesetzt; danach folgt manueller Test und Freigabe.

| Phase | Inhalt | Status |
|---|---|---|
| 0 | Grundgerüst: Agent-App, Menüleisten-Icon, Menü, Beim Login starten, Ressourcenmessung | ✅ freigegeben |
| 1 | Fenster & Hotkey (`⌥A`, `⌘P`, `Esc`, Größe/Position merken) | ✅ freigegeben |
| 2 | Notizen (Stapel, Autosave mit GRDB, Navigation, Papierkorb, Undo pro Notiz) | ✅ freigegeben (`⌘⇧1` nicht testbar, s. u.) |
| 3 | Checklisten in normalen Notizen | ✅ umgesetzt – wartet auf Freigabe |
| 4 | Keyword-System & Rechnen (`list`, `math`) | ⏳ offen |
| 5 | `sum`, `avg`, `count` | ⏳ offen |
| 6 | Timer | ⏳ offen |
| 7 | Notizverwaltung & Suche, Backups | ⏳ offen |
| 8 | Einheiten & Währungen | ⏳ offen |
| 9 | Komfort (Formatierung, Code, Paste-Modus, Export, Sperren, Themes) | ⏳ offen |

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

### Offen aus Phase 2

- `⌘⇧1` (nach vorn holen) kollidiert beim Nutzer mit einem globalen Screenshot-Kürzel und
  kommt daher nicht in Zettel an. Alternative Belegung oder frei wählbare Kürzel klären.

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
