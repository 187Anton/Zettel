import LocalAuthentication

/// Touch ID, or the account password if Touch ID is not available.
enum Authentication {
    static func deviceOwner(reason: String) async -> Bool {
        let context = LAContext()
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}
