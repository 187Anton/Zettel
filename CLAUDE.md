# CLAUDE.md – Zettel (Arbeitstitel)

Native macOS-Scratchpad-App für schnelle Notizen, Listen, Rechnungen und Timer.
Inspiriert von **Antinote** (antinote.io), dessen schlankes Bedienkonzept uns als Vorbild dient.
Zettel ist eine eigenständige Umsetzung mit eigenem Namen, Icon, Design und Code.
Keine Assets, Texte oder Code von Antinote oder anderen Apps übernehmen.

## Oberste Anforderungen (gelten für jede Phase)

1. **Läuft dauerhaft im Hintergrund**, startet beim Login, ist per Hotkey sofort da.
2. **Minimaler Ressourcenverbrauch:**
   - Leerlauf: ~0 % CPU, Ziel < 60 MB RAM.
   - Kein Polling, keine Endlos-Timer, keine Animationen im Hintergrund.
   - Sekundentakt-Updates nur, solange ein Timer aktiv ist.
   - Standardmäßig **kein Netzwerkzugriff** (Ausnahme: optionale Währungskurse, Phase 8, nur per Opt-in).
3. **Daten bleiben lokal.** Kein Konto, keine Telemetrie.
4. **Robust:** Keine Notiz darf verloren gehen (Autosave, Backups, Papierkorb statt Löschen).

## Technik

- **Swift + AppKit als Basis, SwiftUI für Einstellungen.** Xcode-Projekt, kein Electron, kein Web-View.
- **Deployment Target: macOS 14 (Sonoma)**, Apple Silicon und Intel.
- **Agent-App:** `LSUIElement = YES` (kein Dock-Icon), `NSStatusItem` in der Menüleiste.
- **Fenster:** `NSPanel`, schwebend, kann Key-Window werden.
  - `collectionBehavior`: `.canJoinAllSpaces`, `.fullScreenAuxiliary`, damit es auch über Vollbild-Apps erscheint.
- **Globaler Hotkey:** über Carbon `RegisterEventHotKey`. Benötigt keine Bedienungshilfen-Berechtigung. In eigener Klasse kapseln.
- **Editor:** `NSTextView` (nicht SwiftUI `TextEditor`). Wird gebraucht für Inline-Ergebnisse, Checkboxen und Formatierung.
- **Speicherung:** SQLite über **GRDB.swift** (einzige erlaubte Fremdabhängigkeit ohne Rückfrage).
  - Notizinhalt als Klartext mit leichten Markdown-Markierungen.
  - Autosave mit Debounce (~500 ms nach letzter Eingabe).
- **Autostart:** `SMAppService.mainApp`.
- **Benachrichtigungen:** `UserNotifications`.
- **Rechen-Engine:** eigener Tokenizer + Recursive-Descent-Parser.
  - **Kein** `NSExpression` (crasht bei ungültiger Eingabe).
  - Reine Swift-Logik ohne UI-Abhängigkeit, vollständig unit-getestet.

## Konventionen

- Code, Bezeichner, Funktionsnamen und Commit-Messages auf **Englisch**. Diese Datei und die UI-Texte dürfen deutsch sein.
- Logik (Parser, Keyword-Erkennung, Timer-Syntax, Notizverwaltung) strikt von UI trennen und **testgetrieben** entwickeln (Swift Testing oder XCTest).
- Nach jeder Änderung: bauen mit `xcodebuild`, Tests laufen lassen, Fehler selbst beheben, bis alles grün ist.
- **Immer nur eine Phase umsetzen.** Danach kurz zusammenfassen, was zum manuellen Testen ansteht, und auf Freigabe warten.
- `README.md` und `ROADMAP.md` (Phasen mit Status) bei jeder Phase mitpflegen.
- Neue Fremdabhängigkeiten nur nach Rückfrage.

## Phasen

### Phase 0 – Grundgerüst
- Xcode-Projekt als Agent-App mit Menüleisten-Icon.
- Menü: Neue Notiz, Einstellungen, Beim Login starten (an/aus), Beenden.
- Ressourcenverbrauch im Leerlauf mit Aktivitätsanzeige prüfen und dokumentieren.

### Phase 1 – Fenster & Hotkey
- `⌥A` blendet das Fenster über der aktiven App ein/aus (Hotkey später in Einstellungen änderbar).
- `⌘P` fixiert das Fenster im Vordergrund. Ohne Fixierung blendet es sich bei Fokusverlust aus.
- Fixier-Zustand, Fenstergröße und Fensterposition merken.
- `Esc` schließt das Fenster.

### Phase 2 – Notizen
- Fenster öffnet mit Textfeld, sofort tippbereit, Autosave.
- Notizstapel, sortiert nach letzter Änderung:
  - `⌘N` neue Notiz
  - `⌘[` / `⌘]` vor/zurück, alternativ Zwei-Finger-Wischen
  - `⌘1` neueste Notiz
  - `⌘⇧1` aktuelle Notiz nach vorn holen
  - `⌘D` in den Papierkorb
- Option: nach X Minuten ohne Fokus mit neuer leerer Notiz öffnen.
- Undo/Redo getrennt pro Notiz.

### Phase 3 – Checklisten in normalen Notizen
- Markdown-Kurzformen beim Tippen umwandeln:
  - `[] ` / `- [ ] ` → leere Checkbox
  - `[x] ` / `- [x] ` → abgehakt
  - `- ` → Aufzählungspunkt
  - `1. ` → nummerierte Liste
- `Tab` / `⇧Tab` ändert die Einrückung, `⌘⇧K` hakt ab, `⌘⇧M` wechselt den Listentyp.
- Einstellung für abgehakte Einträge: stehen lassen / nach unten verschieben / löschen.
- `⌥↑` / `⌥↓` verschiebt Zeilen.

### Phase 4 – Keyword-System & Rechnen
- Keywords stehen in der ersten Zeile, optional mit Titel (`math: Budget`).
- `/` am Zeilenanfang öffnet eine Keyword-Auswahl (Zahlentaste wählt).
- `list`: alle folgenden Zeilen werden automatisch Checkboxen, `/x` am Zeilenende hakt ab.
- `math`:
  - Zeilen, die mit `=` enden, zeigen ihr Ergebnis rechtsbündig.
  - Variablen: `preis : 25`, danach `preis * 3 =` ergibt `75`.
  - `ans` bezieht sich auf das nächste Ergebnis darüber.
  - `total =` summiert die Ergebnisse darüber, frühere Zwischensummen ausgenommen.
  - Live-Neuberechnung bei jeder Änderung (reaktiv).
  - Einstellungen: Dezimalstellen, Tausendertrennzeichen.
- Parser zuerst als getestete Bibliothek bauen: Operatoren, Klammern, Prozent, Fehlerfälle.

### Phase 5 – sum, avg, count
- `sum`: summiert erkannte Zahlen pro Zeile. Bei Zeilen mit `=` zählt deren Ergebnis.
- `avg`: Durchschnitt der erkannten Zahlen.
- `count`: zählt Einträge, Zeilen, Wörter und Zeichen.
- Zeilen mit `//` am Anfang werden bei allen Auswertungen ignoriert.

### Phase 6 – Timer
- Timer-Befehle stehen am Anfang einer beliebigen Zeile:
  - `timer` → Stoppuhr
  - `timer 10` → 10 Minuten
  - `timer 3.5` / `timer 3:30` → 3:30 Minuten
  - `timer 21:15` → Countdown bis zu dieser Uhrzeit
  - `timer 5: Wäsche` → benannter Countdown
  - `timer pomo` → 25 Minuten Arbeit / 5 Minuten Pause
  - `timer 5 1` → eigene Intervalle
- Steuerung: `timer p` pausiert/setzt fort, `timer r` startet neu, `timer s` / `timer 0` stoppt.
- Restzeit optional in der Menüleiste.
- Bei Ablauf: Benachrichtigung und Ton, beides einstellbar.
- Laufende Timer überleben das Schließen des Fensters.

### Phase 7 – Notizverwaltung & Suche
- 9 feste Notizplätze, die nie ablaufen:
  - `⌘T` wechselt zwischen Stapel und Plätzen.
  - `⌘1`–`⌘9` springt direkt zu einem Platz (optional).
- `⌘⇧A` archiviert eine Notiz.
- Papierkorb („Void“), wiederherstellbar.
- Auto-Ablauf unveränderter Notizen in den Papierkorb, Frist einstellbar: heute / Woche / Monat / Jahr / nie.
- Papierkorb leert sich nach 7 / 30 / 90 Tagen / nie.
- `⌘F` Suche über alle Notizen mit Listenansicht und Filter.
- `⌘⇧F` Suchen & Ersetzen in der aktuellen Notiz.
- Automatische Datenbank-Backups (Intervall einstellbar) mit Wiederherstellen-Funktion.

### Phase 8 – Einheiten & Währungen
- In `math`: `10 cm to inch =`, Länge, Fläche, Volumen, Masse, Temperatur (lokale Tabellen).
- Währungen mit eigenen Kursen.
- Tägliches Kurs-Update nur per Opt-in (einziger Netzwerkzugriff der App).

### Phase 9 – Komfort
- Markdown-Formatierung: Überschriften, `⌘B`, `⌘I`, `⌘U`, `⌘⇧X` durchstreichen, `⌘/` Kommentar.
- `code` / `code: py`: Syntaxhervorhebung (schlank, ohne schwere Abhängigkeit).
- `paste`: übernimmt neu kopierten Text automatisch aus der Zwischenablage.
  - Nur während aktiv. Zwischenablage nur über `changeCount` prüfen, sparsam getaktet.
  - `Esc` beendet den Modus.
- `⌘C` ohne Auswahl kopiert die ganze Notiz.
- Lange URLs optisch kürzen, `⌘↩` öffnet den Link.
- Export einzelner Notizen als `.txt`, `.md` oder PDF, Export aller Notizen als ZIP.
- `⌘⇧L` sperrt eine Notiz per Touch ID, `⌘⇧R` macht sie schreibgeschützt.
- Helles/dunkles Theme, Textgröße `⌘+` / `⌘−`, optional transparentes Fenster.
- Einstellungsfenster mit allen Optionen der vorigen Phasen.

## Bewusst vorerst nicht geplant
- iCloud-Sync
- JavaScript-Erweiterungen
- Raycast/Alfred-Integration und URL-Scheme
- Vim-Modus
- Texterkennung aus Bildern
- iOS-App

Diese Punkte erst nach Phase 9 und nur nach Absprache angehen.
