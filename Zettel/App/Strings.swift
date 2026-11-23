/// User-facing texts (German). Collected in one place so they can later be
/// moved to a String Catalog without touching the UI code.
enum Strings {
    static let appName = "Zettel"

    enum Menu {
        static let showWindow = "Notizfenster öffnen"
        static let exportAll = "Alle Notizen exportieren …"
        static let newNote = "Neue Notiz"
        static let settings = "Einstellungen …"
        static let launchAtLogin = "Beim Login starten"
        static let launchAtLoginNeedsApproval = "Muss in den Systemeinstellungen unter „Anmeldeobjekte“ erlaubt werden."
        static let quit = "Zettel beenden"
    }

    enum Panel {
        static let readOnly = "nur lesen"
        static let positionHelp = "Position im Notizstapel. ⌘[ / ⌘] oder Wischen mit zwei Fingern blättert."
        static let pin = "Im Vordergrund fixieren"
        static let unpin = "Fixierung lösen"
    }

    enum Lock {
        static let title = "Gesperrte Notiz"
        static let unlock = "Entsperren"
        static let reason = "die Notiz anzuzeigen"
    }

    enum Export {
        static let format = "Format:"
        static let allTitle = "Alle Notizen exportieren"
        static let lockedNote = "Gesperrte Notizen werden erst nach dem Entsperren exportiert."
        static func done(_ count: Int) -> String { "\(count) Notizen exportiert." }
        static let failed = "Export fehlgeschlagen"
    }

    enum Paste {
        static let active = "● sammelt – Esc beendet"
        static let inactive = "aus – / und „paste“ wählen startet neu"
    }

    enum Search {
        static let placeholder = "Alle Notizen durchsuchen"
        static let filter = "Filter"
        static let empty = "Keine Notizen"
        static let noResults = "Keine Treffer"
        static let untitled = "Ohne Titel"
        static let restore = "Wiederherstellen"
        static let unarchive = "Zurückholen"
    }

    enum Timer {
        static let finished = "Timer abgelaufen"
        static let workPhase = "Weiterarbeiten"
        static let breakPhase = "Pause"
        static let pause = "Pausieren"
        static let resume = "Fortsetzen"
        static let restart = "Neu starten"
        static let stop = "Stoppen"
    }

    enum MainMenu {
        static let about = "Über Zettel"
        static let edit = "Bearbeiten"
        static let undo = "Widerrufen"
        static let redo = "Wiederholen"
        static let cut = "Ausschneiden"
        static let copy = "Kopieren"
        static let paste = "Einsetzen"
        static let selectAll = "Alles auswählen"
        static let findNext = "Weitersuchen"
        static let findPrevious = "Rückwärts suchen"
        static let useSelectionForFind = "Auswahl suchen"
    }

    enum Settings {
        static let windowTitle = "Zettel – Einstellungen"
        static let general = "Allgemein"
        static let launchAtLogin = "Beim Login starten"
        static let needsApproval = "Zettel muss noch in den Systemeinstellungen erlaubt werden."
        static let openSystemSettings = "Systemeinstellungen öffnen …"
        static let notFound = "Das Anmeldeobjekt wurde nicht gefunden. Liegt Zettel im Programme-Ordner?"
        static let notes = "Notizen"
        static let newNoteAfterIdle = "Mit neuer Notiz öffnen nach"
        static let newNoteAfterIdleHelp = "Wenn das Fenster so lange nicht im Fokus war, beginnt es mit einer leeren Notiz."
        static let never = "Nie"
        static func minutes(_ value: Int) -> String { value == 1 ? "1 Minute" : "\(value) Minuten" }
        static let lists = "Listen"
        static let listsAndMath = "Listen & Rechnen"
        static let appearance = "Darstellung"
        static let theme = "Erscheinungsbild"
        static let fontSize = "Textgröße"
        static let transparentWindow = "Transparentes Notizfenster"
        static let hideMarkdownMarkers = "Formatierungszeichen ausblenden (außer in der Zeile mit dem Cursor)"
        static let appearanceHelp = "Textgröße auch mit ⌘+ / ⌘− / ⌘0 im Notizfenster."
        static let hotKey = "Notizfenster ein-/ausblenden"
        static let pressShortcut = "Tasten drücken …"
        static let reset = "Zurücksetzen"
        static let expiry = "Unveränderte Notizen in den Papierkorb nach"
        static let trashPeriod = "Papierkorb leeren"
        static let retentionHelp = "Gilt nur für den Stapel. Plätze und Archiv laufen nie ab. Geprüft wird beim Start und beim Öffnen des Fensters."
        static let slotShortcuts = "⌘1–⌘9 springen immer zu den Plätzen"
        static let slotShortcutsHelp = "Aus: ⌘1 zeigt im Stapel die neueste Notiz, in den Plätzen (⌘T) wählen ⌘1–⌘9 den Platz."
        static let backups = "Backups"
        static let currencies = "Währungen"
        static let currencyAutoUpdate = "Kurse täglich von der Europäischen Zentralbank laden"
        static let currencyPrivacy = "Einziger Netzwerkzugriff von Zettel: lädt einmal am Tag die öffentlichen Referenzkurse (ecb.europa.eu). Es werden keine Daten gesendet."
        static func ratesFrom(_ date: String) -> String { "Kurse vom \(date)" }
        static let ratesNotLoaded = "Noch keine Kurse geladen"
        static let updateNow = "Jetzt aktualisieren"
        static let ratesHeader = "Kurse (1 EUR = …)"
        static let currencyCode = "Code"
        static let rate = "Kurs"
        static let add = "Hinzufügen"
        static let resetRate = "Eigenen Kurs entfernen (EZB-Kurs verwenden)"
        static let removeRate = "Währung entfernen"
        static let ratesHelp = "Eigene Kurse haben Vorrang vor den geladenen. Grau: Kurs der EZB. Verwendung in math: 100\u{00A0}€\u{00A0}in\u{00A0}USD\u{00A0}="
        static let backupInterval = "Automatisches Backup"
        static let backupHelp = "Die letzten 10 Backups werden aufbewahrt. Vor jeder Wiederherstellung wird zusätzlich der aktuelle Stand gesichert."
        static let noBackups = "Noch keine Backups."
        static let restoreBackup = "Wiederherstellen"
        static let backupNow = "Jetzt sichern"
        static let showInFinder = "Im Finder zeigen"
        static let restoreQuestion = "Backup wiederherstellen?"
        static let restoreExplanation = "Alle Notizen werden durch den Stand des Backups ersetzt. Der aktuelle Stand wird vorher als eigenes Backup gesichert."
        static let restored = "Backup wiederhergestellt."
        static let cancel = "Abbrechen"
        static let checkedItems = "Abgehakte Einträge"
        static let checkedKeep = "Stehen lassen"
        static let checkedMoveToBottom = "Nach unten verschieben"
        static let checkedDelete = "Löschen"
        static let math = "Rechnen"
        static let decimals = "Dezimalstellen"
        static let decimalsAutomatic = "Automatisch (bis 4)"
        static let decimalSeparator = "Dezimalzeichen"
        static let groupingSeparator = "Tausendertrennzeichen"
        static let comma = "Komma"
        static let period = "Punkt"
        static let space = "Leerzeichen"
        static let apostrophe = "Apostroph"
        static let none = "Keines"
        static let example = "Beispiel"
        static let timer = "Timer"
        static let timerNotifications = "Benachrichtigung bei Ablauf"
        static let timerSound = "Ton bei Ablauf"
        static let timerSoundName = "Ton"
        static let timerInMenuBar = "Restzeit in der Menüleiste anzeigen"
        static let databaseErrorTitle = "Notizen können nicht gespeichert werden"
        static let databaseErrorMessage = "Die Notizdatenbank konnte nicht geöffnet werden. Zettel läuft vorübergehend ohne Speichern – bitte kopiere wichtige Inhalte heraus.\n\nFehler: "
    }
}
