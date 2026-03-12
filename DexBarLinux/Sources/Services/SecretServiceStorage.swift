#if canImport(CLibSecret)
import CLibSecret
import DexBarLinuxBridge
import Foundation

/// Stores and retrieves Dexcom credentials using the Secret Service D-Bus API
/// (KDE Wallet, GNOME Keyring, or any compatible Secret Service provider).
struct SecretServiceStorage {
    private static let schema = "com.dexbar.app"

    static func save(key: String, value: String) -> Bool {
        dexbar_secret_store(schema, key, value) != 0
    }

    static func load(key: String) -> String? {
        guard let ptr = dexbar_secret_load(schema, key) else { return nil }
        let value = String(cString: ptr)
        secret_password_free(ptr)
        return value
    }

    static func delete(key: String) {
        dexbar_secret_delete(schema, key)
    }
}
#endif
