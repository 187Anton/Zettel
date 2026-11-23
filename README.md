# Zettel

Schlanke, native Scratchpad-App für macOS (Arbeitstitel). Läuft unauffällig in der
Menüleiste, ist per Hotkey sofort da und speichert alles lokal.

> Status: **Phase 0 – Grundgerüst.** Siehe [ROADMAP.md](ROADMAP.md).

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

## Projektstruktur

```
Zettel/
  App/          Einstiegspunkt (AppDelegate), UI-Texte
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

## Ressourcenverbrauch (Leerlauf)

Gemessen mit `top -pid <PID> -stats cpu,mem,idlew,threads,power` über 60 s und
`footprint <PID>`; „Speicher“ in der Aktivitätsanzeige entspricht dem Footprint.

| Stand | Build | CPU | Speicher (Footprint) | Idle-Wakeups | Threads |
|---|---|---|---|---|---|
| Phase 0 (2026-11-23) | Release, universal | 0,0 % | 13 MB | 0 | 3 |

Messumgebung: Apple M4, macOS 27.2. Ziel laut Anforderungen: ~0 % CPU, < 60 MB RAM.

Hinweis: `ps` zeigt einen RSS von ~70 MB, weil darin gemeinsam genutzte
System-Frameworks (AppKit usw.) mitgezählt werden. Relevant ist der Footprint.

## Beim Login starten

Umgesetzt mit `SMAppService.mainApp`. macOS verlangt beim ersten Aktivieren ggf. eine
Bestätigung unter *Systemeinstellungen › Allgemein › Anmeldeobjekte*. In diesem Fall
zeigt das Menü einen Strich statt Häkchen, und ein Klick öffnet die Systemeinstellungen.
Für einen zuverlässigen Autostart sollte die App in `/Programme` liegen.
