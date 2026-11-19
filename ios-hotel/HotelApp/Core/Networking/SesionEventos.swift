import Foundation

/// Eventos de sesión que cruzan de la capa de red a la de UI.
///
/// `APIClient` es un `actor` y no puede tocar `SesionStore` (que es
/// `@MainActor`), así que publica aquí y la raíz de SwiftUI escucha.
///
/// Se dispara **solo** cuando el backend responde `401` con
/// `motivo == "NO_AUTENTICADO"`: ese es el caso de "el token ya no vale"
/// (expirado, revocado o versión de credenciales obsoleta tras cambiar la
/// contraseña). Un `401 CREDENCIALES_INVALIDAS` del login **no** dispara el
/// evento: ahí el usuario todavía no tiene sesión.
enum SesionEventos {

    /// El servidor rechazó el token: hay que borrarlo y volver al login.
    static let sesionExpirada = Notification.Name("pe.agrocorp.hotel.sesionExpirada")
}
