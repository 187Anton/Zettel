# Zettel

Schlanke, native Scratchpad-App für macOS (Arbeitstitel). Läuft unauffällig in der
Menüleiste, ist per Hotkey sofort da und speichert alles lokal.

> Status: **Phase 1 – Fenster & Hotkey.** Siehe [ROADMAP.md](ROADMAP.md).

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

- Ohne Fixierung blendet sich das Fenster aus, sobald es den Fokus verliert.
- Fixier-Zustand, Größe und Position werden gespeichert. Liegt die gespeicherte Position
  auf einem nicht mehr angeschlossenen Bildschirm, erscheint das Fenster zentriert auf
  dem Bildschirm mit dem Mauszeiger.
- Das Fenster ist ein nicht-aktivierendes Panel: Die App, in der du gerade arbeitest,
  bleibt aktiv. Es erscheint auf allen Spaces und auch über Vollbild-Apps.
- Der Hotkey wird über Carbon `RegisterEventHotKey` registriert und braucht keine
  Bedienungshilfen-Berechtigung. Er ist in den Einstellungen gespeichert
  (`hotKey.toggleWindow`); eine Oberfläche zum Ändern folgt mit dem Einstellungsfenster.

## Projektstruktur

```
Zettel/
  App/          Einstiegspunkt (AppDelegate), Einstellungen (UserDefaults), UI-Texte
  HotKey/       Tastenkombination (KeyCombo) und globaler Hotkey (Carbon)
  Panel/        Notizfenster (NSPanel), Steuerung, Logik für Kürzel und Position
  StatusBar/    Menüleisten-Icon und Menü
  LoginItem/    „Beim Login starten“ (SMAppService) – Logik getrennt von der UI
  Settings/     Einstellungsfenster (SwiftUI)
ZettelTests/    Unit-Tests (Swift Testing), laufen im App-Host
```

Neue Dateien in `Zettel/` bzw. `ZettelTests/` werden von Xcode automatisch
übernommen – die Projektdatei muss dafür nicht angepasst werden.

## Grundsätze

- **Agent-App** (`LSUIElement = YES`): kein Dock-Icon, nur Menüleiste.
- **App Sandbox aktiv, kein Netzwerk-Entitlement.** Die App kann technisch keine
  Verbindungen aufbauen. (Ausnahme später: optionale Währungskurse, Phase 8, nur per Opt-in.)
- **Kein Polling.** Zustände (z. B. Login-Objekt) werden nur aktualisiert, wenn das
  Menü bzw. das Einstellungsfenster geöffnet wird.
- Das Einstellungsfenster wird erst bei Bedarf erzeugt und beim Schließen wieder freigegeben.
  Das Notizfenster wird beim ersten Einblenden erzeugt und danach nur versteckt, damit es sofort da ist.
- Unit-Tests laufen im App-Host. Dort werden Menüleisten-Icon und Hotkey nicht eingerichtet,
  damit die Tests keinem laufenden Zettel `⌥A` wegnehmen.

## Ressourcenverbrauch (Leerlauf)

Gemessen mit `top -pid <PID> -stats cpu,mem,idlew,threads,power` über 60 s und
`footprint <PID>`; „Speicher“ in der Aktivitätsanzeige entspricht dem Footprint.

| Stand | Build | CPU | Speicher (Footprint) | Idle-Wakeups | Threads |
|---|---|---|---|---|---|
| Phase 0 (2026-11-23) | Release, universal | 0,0 % | 13 MB | 0 | 3 |
| Phase 1 (2026-11-23) | Release, universal | 0,0 % | 13 MB | 0 | 3 |

Messumgebung: Apple M4, macOS 27.2. Ziel laut Anforderungen: ~0 % CPU, < 60 MB RAM.

Hinweis: `ps` zeigt einen RSS von ~70 MB, weil darin gemeinsam genutzte
System-Frameworks (AppKit usw.) mitgezählt werden. Relevant ist der Footprint.

## Beim Login starten

Umgesetzt mit `SMAppService.mainApp`. macOS verlangt beim ersten Aktivieren ggf. eine
Bestätigung unter *Systemeinstellungen › Allgemein › Anmeldeobjekte*. In diesem Fall
zeigt das Menü einen Strich statt Häkchen, und ein Klick öffnet die Systemeinstellungen.
Für einen zuverlässigen Autostart sollte die App in `/Programme` liegen.
