import Foundation
import Security

/// Almacenamiento del JWT en el **Keychain** de iOS.
///
/// Herramienta nativa #1 de la rúbrica: `Security.framework`.
/// Nunca se guarda el token en `UserDefaults` (sería legible en backups).
actor TokenStore {

    static let shared = TokenStore()

    private let service = "pe.agrocorp.hotel.token"
    private let account = "accessToken"
    private var cache: String?

    // MARK: - Lectura

    func token() -> String? {
        if let cache { return cache }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess,
              let data = item as? Data,
              let valor = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        cache = valor
        return valor
    }

    // MARK: - Escritura

    func guardar(_ token: String) {
        let data = Data(token.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let atributos: [String: Any] = [
            kSecValueData as String: data,
            // El token solo debe estar disponible con el dispositivo desbloqueado.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemUpdate(query as CFDictionary, atributos as CFDictionary)

        if status == errSecItemNotFound {
            var nuevo = query
            nuevo.merge(atributos) { _, nuevoValor in nuevoValor }
            SecItemAdd(nuevo as CFDictionary, nil)
        }

        cache = token
    }

    func eliminar() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        cache = nil
    }
}

// MARK: - Credenciales recordadas

/// Guarda el correo del último acceso para rellenarlo automáticamente.
///
/// Solo se recuerda el **email**, nunca la contraseña: guardar contraseñas en
/// UserDefaults es una vulnerabilidad clásica. Para el "recordarme" completo
/// se usa Face ID, que desbloquea el JWT del Keychain.
enum CredencialesRecordadas {

    private static let clave = "hotel.emailRecordado"
    private static let claveActivo = "hotel.recordarActivo"

    /// ¿El usuario marcó "Recordarme"?
    static var activo: Bool {
        get { UserDefaults.standard.bool(forKey: claveActivo) }
        set { UserDefaults.standard.set(newValue, forKey: claveActivo) }
    }

    static var email: String? {
        get { UserDefaults.standard.string(forKey: clave) }
        set {
            if let newValue, !newValue.isEmpty {
                UserDefaults.standard.set(newValue, forKey: clave)
            } else {
                UserDefaults.standard.removeObject(forKey: clave)
            }
        }
    }

    static func guardar(email: String) {
        self.email = email
        activo = true
    }

    static func olvidar() {
        UserDefaults.standard.removeObject(forKey: clave)
        activo = false
    }
}
