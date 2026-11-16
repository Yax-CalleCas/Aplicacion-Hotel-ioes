import Foundation
import LocalAuthentication

/// Autenticación biométrica con **Face ID / Touch ID**.
///
/// Herramienta nativa #2 de la rúbrica (`LocalAuthentication.framework`).
/// Se usa para:
///  - Reabrir la app con una sesión guardada.
///  - Confirmar un pago antes de declararlo.
///
/// Nunca sustituye la contraseña en el servidor: es una barrera local que
/// protege el token guardado en el Keychain.
enum BiometriaService {

    enum Resultado {
        case exito
        case cancelado
        case noDisponible(String)
        case fallo(String)
    }

    /// Indica si el dispositivo tiene biometría configurada.
    static var disponible: Bool {
        let contexto = LAContext()
        var error: NSError?
        return contexto.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                          error: &error)
    }

    static var biometriaDescripcion: String {
        let contexto = LAContext()
        var error: NSError?
        _ = contexto.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)

        switch contexto.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "biometría"
        }
    }

    /// Pide autenticación. En el simulador, `EvaluatePolicy` no está disponible:
    /// se permite continuar para no bloquear el desarrollo.
    static func autenticar(motivo: String) async -> Resultado {
        let contexto = LAContext()
        contexto.localizedCancelTitle = "Cancelar"
        contexto.localizedFallbackTitle = "Usar contraseña"

        var error: NSError?
        guard contexto.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return .noDisponible(error?.localizedDescription
                ?? "La biometría no está configurada en este dispositivo.")
        }

        do {
            let exito = try await contexto.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: motivo)
            return exito ? .exito : .fallo("No se pudo verificar tu identidad.")
        } catch let laError as LAError {
            switch laError.code {
            case .userCancel, .systemCancel, .appCancel:
                return .cancelado
            case .biometryNotAvailable, .biometryNotEnrolled:
                return .noDisponible("Configura Face ID en Ajustes para usar esta función.")
            case .biometryLockout:
                return .fallo("Face ID está bloqueado. Usa tu contraseña del dispositivo.")
            default:
                return .fallo(laError.localizedDescription)
            }
        } catch {
            return .fallo(error.localizedDescription)
        }
    }
}
