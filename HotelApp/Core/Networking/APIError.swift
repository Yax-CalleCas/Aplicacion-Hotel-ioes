import Foundation

/// Error de red o de negocio devuelto por la API.
///
/// Refleja exactamente `ErrorResponse` del backend:
/// `{ timestamp, status, error, message, path, correlationId, motivo,
///    intentosRestantes, reintentarEnSegundos, bloqueadoHasta, nivel,
///    fieldErrors }`
///
/// Todos los campos salvo `status` y `message` son opcionales para tolerar
/// respuestas parciales o errores de proxy.
struct APIError: Error, Decodable, LocalizedError, Sendable {

    let status: Int
    let error: String?
    let message: String
    let path: String?
    let correlationId: String?
    let motivo: String?
    let fieldErrors: [String: String]?
    let intentosRestantes: Int?
    let reintentarEnSegundos: Int?
    let bloqueadoHasta: String?
    let nivel: Int?

    var errorDescription: String? { message }

    // MARK: - Clasificación

    /// Bloqueo temporal de cuenta (HTTP 429).
    var esBloqueo: Bool { status == 429 }

    /// Credenciales inválidas (HTTP 401) con intentos restantes.
    var esCredencialesInvalidas: Bool { status == 401 }

    /// Conflicto de negocio (409): sobreventa, saldo pendiente, etc.
    var esConflicto: Bool { status == 409 }

    /// Sin conexión o servidor inalcanzable.
    var esTransporte: Bool { status == 0 }

    /// Sesión expirada (401 sin `motivo` de credenciales).
    var esSesionExpirada: Bool { status == 401 && motivo == "NO_AUTENTICADO" }

    /// Mensaje listo para mostrar al usuario, priorizando la validación por campo.
    var mensajeUsuario: String {
        if let fieldErrors, let primero = fieldErrors.values.first {
            return primero
        }
        return message
    }

    // MARK: - Constructores

    static func transporte(_ mensaje: String) -> APIError {
        APIError(status: 0, error: "SIN_CONEXION", message: mensaje,
                 path: nil, correlationId: nil, motivo: nil, fieldErrors: nil,
                 intentosRestantes: nil, reintentarEnSegundos: nil,
                 bloqueadoHasta: nil, nivel: nil)
    }

    static func decodificacion(_ mensaje: String) -> APIError {
        APIError(status: -1, error: "RESPUESTA_INVALIDA", message: mensaje,
                 path: nil, correlationId: nil, motivo: nil, fieldErrors: nil,
                 intentosRestantes: nil, reintentarEnSegundos: nil,
                 bloqueadoHasta: nil, nivel: nil)
    }
}
