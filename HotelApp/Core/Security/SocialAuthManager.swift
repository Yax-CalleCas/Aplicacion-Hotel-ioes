import Foundation
import UIKit
import FirebaseAuth
import FirebaseCore
import FacebookLogin
import FacebookCore

/// Autenticación social real con Firebase.
///
/// Flujo:
///  1. El SDK de Facebook obtiene un token de acceso.
///  2. Se canjea por una credencial de Firebase.
///  3. Firebase devuelve un **ID Token** (JWT firmado por Google).
///  4. Ese ID Token es lo que viaja al backend Spring Boot.
///
/// El token de Facebook nunca sale del teléfono.
///
/// Nota de API: desde facebook-ios-sdk 16 se usa `AuthenticationToken`
/// (no `AccessToken`) y `loginBehavior` ya no existe en `LoginManager`.
enum SocialAuthManager {

    enum ErrorSocial: LocalizedError {
        case noConfigurado
        case cancelado
        case sinToken
        case fallo(String)

        var errorDescription: String? {
            switch self {
            case .noConfigurado:
                return "El inicio de sesión con Facebook no está configurado."
            case .cancelado:
                return "Cancelaste el inicio de sesión."
            case .sinToken:
                return "Facebook no devolvió un token válido."
            case .fallo(let mensaje):
                return mensaje
            }
        }
    }

    /// Credencial lista para enviar al backend.
    struct Credencial {
        let proveedor: String
        let idToken: String
        let email: String?
        let nombre: String?
    }

    /// ¿Está Firebase listo? Sirve para decidir si mostrar el flujo real.
    static var configurado: Bool {
        FirebaseApp.app() != nil
    }

    /// ¿Hay un App ID real de Facebook en el Info.plist?
    ///
    /// Sin esto, `LoginManager.logIn` lanza una excepción de Objective-C
    /// (`App ID not found`) que **termina la app**: Swift no la puede capturar
    /// con `try/catch`. Se comprueba antes de tocar el SDK.
    static var facebookConfigurado: Bool {
        guard let appID = Bundle.main.object(
            forInfoDictionaryKey: "FacebookAppID") as? String else {
            return false
        }

        let limpio = appID.trimmingCharacters(in: .whitespaces)
        return !limpio.isEmpty && !limpio.hasPrefix("PON_AQUI")
    }

    // MARK: - Facebook

    /// Abre la pantalla real de Facebook y devuelve la credencial de Firebase.
    static func entrarConFacebook() async throws -> Credencial {
        guard FirebaseApp.app() != nil else { throw ErrorSocial.noConfigurado }

        // Sin App ID el SDK aborta el proceso: se corta antes.
        guard facebookConfigurado else { throw ErrorSocial.noConfigurado }

        let tokenFacebook = try await pedirTokenFacebook()

        let credencialFacebook = FacebookAuthProvider.credential(
            withAccessToken: tokenFacebook)

        do {
            let authResult = try await Auth.auth().signIn(with: credencialFacebook)
            let usuario = authResult.user
            let idToken = try await usuario.getIDToken()

            return Credencial(proveedor: "FACEBOOK",
                              idToken: idToken,
                              email: usuario.email,
                              nombre: usuario.displayName)
        } catch {
            throw ErrorSocial.fallo(error.localizedDescription)
        }
    }

    /// Wrapper async del callback del SDK de Facebook.
    private static func pedirTokenFacebook() async throws -> String {
        try await withCheckedThrowingContinuation { continuacion in
            let manager = LoginManager()

            manager.logIn(permissions: ["public_profile", "email"],
                          from: nil) { resultado, error in

                if let error {
                    continuacion.resume(throwing: ErrorSocial.fallo(
                        error.localizedDescription))
                    return
                }

                guard let resultado else {
                    continuacion.resume(throwing: ErrorSocial.cancelado)
                    return
                }

                if resultado.isCancelled {
                    continuacion.resume(throwing: ErrorSocial.cancelado)
                    return
                }

                // SDK 16+: authenticationToken (AuthenticationToken).
                guard let authenticationToken = resultado.authenticationToken else {
                    continuacion.resume(throwing: ErrorSocial.sinToken)
                    return
                }

                continuacion.resume(returning: authenticationToken.tokenString)
            }
        }
    }

    // MARK: - Retorno por URL scheme

    /// Debe llamarse desde AppDelegate cuando vuelve de Facebook.
    @discardableResult
    static func manejarURL(_ url: URL) -> Bool {
        ApplicationDelegate.shared.application(
            UIApplication.shared,
            open: url,
            sourceApplication: nil,
            annotation: nil)
    }
}
