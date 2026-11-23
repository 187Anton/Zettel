# Roadmap

Details zu jeder Phase stehen in [CLAUDE.md](CLAUDE.md). Es wird immer nur eine Phase
umgesetzt; danach folgt manueller Test und Freigabe.

| Phase | Inhalt | Status |
|---|---|---|
| 0 | Grundgerüst: Agent-App, Menüleisten-Icon, Menü, Beim Login starten, Ressourcenmessung | ✅ freigegeben |
| 1 | Fenster & Hotkey (`⌥A`, `⌘P`, `Esc`, Größe/Position merken) | ✅ umgesetzt – wartet auf Freigabe |
| 2 | Notizen (Stapel, Autosave mit GRDB, Navigation, Papierkorb, Undo pro Notiz) | ⏳ offen |
| 3 | Checklisten in normalen Notizen | ⏳ offen |
| 4 | Keyword-System & Rechnen (`list`, `math`) | ⏳ offen |
| 5 | `sum`, `avg`, `count` | ⏳ offen |
| 6 | Timer | ⏳ offen |
| 7 | Notizverwaltung & Suche, Backups | ⏳ offen |
| 8 | Einheiten & Währungen | ⏳ offen |
| 9 | Komfort (Formatierung, Code, Paste-Modus, Export, Sperren, Themes) | ⏳ offen |

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
