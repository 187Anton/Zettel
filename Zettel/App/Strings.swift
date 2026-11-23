/// User-facing texts (German). Collected in one place so they can later be
/// moved to a String Catalog without touching the UI code.
enum Strings {
    static let appName = "Zettel"

    enum Menu {
        static let newNote = "Neue Notiz"
        static let settings = "Einstellungen …"
        static let launchAtLogin = "Beim Login starten"
        static let launchAtLoginNeedsApproval = "Muss in den Systemeinstellungen unter „Anmeldeobjekte“ erlaubt werden."
        static let quit = "Zettel beenden"
    }

    enum Settings {
        static let windowTitle = "Zettel – Einstellungen"
        static let general = "Allgemein"
        static let launchAtLogin = "Beim Login starten"
        static let needsApproval = "Zettel muss noch in den Systemeinstellungen erlaubt werden."
        static let openSystemSettings = "Systemeinstellungen öffnen …"
        static let notFound = "Das Anmeldeobjekt wurde nicht gefunden. Liegt Zettel im Programme-Ordner?"
    }
}
