/// User-facing texts (German). Collected in one place so they can later be
/// moved to a String Catalog without touching the UI code.
enum Strings {
    static let appName = "Zettel"

    enum Menu {
        static let showWindow = "Notizfenster öffnen"
        static let newNote = "Neue Notiz"
        static let settings = "Einstellungen …"
        static let launchAtLogin = "Beim Login starten"
        static let launchAtLoginNeedsApproval = "Muss in den Systemeinstellungen unter „Anmeldeobjekte“ erlaubt werden."
        static let quit = "Zettel beenden"
    }

    enum Panel {
        static let positionHelp = "Position im Notizstapel. ⌘[ / ⌘] oder Wischen mit zwei Fingern blättert."
        static let pin = "Im Vordergrund fixieren"
        static let unpin = "Fixierung lösen"
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
        static let databaseErrorTitle = "Notizen können nicht gespeichert werden"
        static let databaseErrorMessage = "Die Notizdatenbank konnte nicht geöffnet werden. Zettel läuft vorübergehend ohne Speichern – bitte kopiere wichtige Inhalte heraus.\n\nFehler: "
    }
}
