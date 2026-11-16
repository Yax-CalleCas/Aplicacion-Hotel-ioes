import Foundation

/// Cliente HTTP de la API.
///
/// Responsabilidades:
///  - Adjuntar el JWT en cada petición autenticada.
///  - Propagar `X-Correlation-Id` para trazabilidad con el backend.
///  - Traducir cualquier respuesta no-2xx a `APIError` tipado.
///
/// Es un `actor` para que el acceso al token y a la sesión sea seguro desde
/// tareas concurrentes (polling de pago + navegación del usuario).
actor APIClient {

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let tokenStore: TokenStore

    init(tokenStore: TokenStore = .shared) {
        let configuracion = URLSessionConfiguration.default
        configuracion.timeoutIntervalForRequest = 20
        configuracion.timeoutIntervalForResource = 40
        configuracion.waitsForConnectivity = false
        configuracion.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuracion)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
        self.encoder = encoder

        self.tokenStore = tokenStore
    }

    // MARK: - API pública

    func get<T: Decodable & Sendable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        let request = try await construirRequest(method: "GET", path: path, query: query)
        return try await ejecutar(request)
    }

    /// GET cuyo cuerpo se ignora (204 No Content o respuesta que no interesa).
    func getVoid(_ path: String, query: [String: String] = [:]) async throws {
        let request = try await construirRequest(method: "GET", path: path, query: query)
        try await ejecutarSinCuerpo(request)
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B) async throws -> T {
        var request = try await construirRequest(method: "POST", path: path)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        return try await ejecutar(request)
    }

    /// POST sin cuerpo (algunos endpoints del backend no lo requieren).
    func post<T: Decodable & Sendable>(_ path: String) async throws -> T {
        let request = try await construirRequest(method: "POST", path: path)
        return try await ejecutar(request)
    }

    /// POST sin cuerpo cuyo resultado se ignora (204).
    func postVoid(_ path: String) async throws {
        let request = try await construirRequest(method: "POST", path: path)
        try await ejecutarSinCuerpo(request)
    }

    /// POST con cuerpo cuyo resultado se ignora (204).
    ///
    /// Necesario para `auth/cambiar-password`: el backend valida el body pero
    /// responde `204 No Content`. Pedir un tipo ahí rompía la decodificación
    /// (`RESPUESTA_INVALIDA`) justo después de que el servidor ya había
    /// cambiado la contraseña e invalidado el token.
    func postVoid<B: Encodable & Sendable>(_ path: String, body: B) async throws {
        var request = try await construirRequest(method: "POST", path: path)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        try await ejecutarSinCuerpo(request)
    }

    /// PUT con cuerpo (actualizar usuario, categoría, habitación, tarifa...).
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B) async throws -> T {
        var request = try await construirRequest(method: "PUT", path: path)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        return try await ejecutar(request)
    }

    /// PUT sin cuerpo (por si el endpoint lo admite).
    func put<T: Decodable & Sendable>(_ path: String) async throws -> T {
        let request = try await construirRequest(method: "PUT", path: path)
        return try await ejecutar(request)
    }

    /// PATCH con cuerpo. El backend usa PATCH para cambios de estado.
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B) async throws -> T {
        var request = try await construirRequest(method: "PATCH", path: path)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        return try await ejecutar(request)
    }

    /// PATCH sin cuerpo (compatibilidad con llamadas antiguas).
    func patch<T: Decodable & Sendable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        let request = try await construirRequest(method: "PATCH", path: path, query: query)
        return try await ejecutar(request)
    }

    /// DELETE cuyo cuerpo se ignora (el backend responde 204).
    func delete(_ path: String) async throws {
        let request = try await construirRequest(method: "DELETE", path: path)
        try await ejecutarSinCuerpo(request)
    }

    /// Descarga binaria (por ejemplo el PNG de un QR).
    func descargar(_ path: String) async throws -> Data {
        let request = try await construirRequest(method: "GET", path: path)
        let (datos, respuesta) = try await URLSession.shared.data(for: request)

        guard let http = respuesta as? HTTPURLResponse else {
            throw APIError.transporte("Respuesta inválida del servidor")
        }

        if http.statusCode >= 400 {
            // El backend responde JSON tambien en los errores: se decodifica
            // para mostrar el mensaje real en lugar de un código suelto.
            if let error = try? decoder.decode(APIError.self, from: datos) {
                avisarSiLaSesionMurio(error)
                throw error
            }
            throw APIError.transporte("Error \(http.statusCode) al descargar la imagen")
        }

        return datos
    }

    /// Sube un archivo como `multipart/form-data`.
    func subirArchivo<T: Decodable & Sendable>(_ path: String,
                                               datos: Data,
                                               nombre: String,
                                               campo: String = "archivo",
                                               tipoMime: String = "image/jpeg") async throws -> T {
        var request = try await construirRequest(method: "POST", path: path)

        let limite = "----HotelPMS\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(limite)",
                         forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        var cuerpo = Data()
        cuerpo.append("--\(limite)\r\n".data(using: .utf8)!)
        cuerpo.append("Content-Disposition: form-data; name=\"\(campo)\"; filename=\"\(nombre)\"\r\n".data(using: .utf8)!)
        cuerpo.append("Content-Type: \(tipoMime)\r\n\r\n".data(using: .utf8)!)
        cuerpo.append(datos)
        cuerpo.append("\r\n--\(limite)--\r\n".data(using: .utf8)!)

        request.httpBody = cuerpo

        return try await ejecutar(request)
    }

    // MARK: - Construcción y ejecución

    private func construirRequest(
        method: String,
        path: String,
        query: [String: String] = [:]
    ) async throws -> URLRequest {

        // Se limpia la barra inicial para que appendingPathComponent no duplique.
        let ruta = path.hasPrefix("/") ? String(path.dropFirst()) : path

        guard var components = URLComponents(
            url: AppConfig.baseURL.appendingPathComponent(ruta),
            resolvingAgainstBaseURL: false
        ) else {
            throw APIError.transporte("URL inválida: \(path)")
        }

        if !query.isEmpty {
            components.queryItems = query
                .map { URLQueryItem(name: $0.key, value: $0.value) }
                // Orden estable: facilita el cache y la depuración.
                .sorted { $0.name < $1.name }
        }

        guard let url = components.url else {
            throw APIError.transporte("URL inválida: \(path)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Correlation-Id")

        if let token = await tokenStore.token() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    private func ejecutar<T: Decodable & Sendable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await enviar(request)
        try validar(response: response, data: data)

        // 204 No Content: el llamador pidió un tipo, pero no hay cuerpo.
        if data.isEmpty {
            throw APIError.decodificacion("El servidor no devolvió datos.")
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodificacion(
                "La respuesta del servidor no tiene el formato esperado.")
        }
    }

    private func ejecutarSinCuerpo(_ request: URLRequest) async throws {
        let (data, response) = try await enviar(request)
        try validar(response: response, data: data)
    }

    private func enviar(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            throw APIError.transporte(mensajeTransporte(error))
        } catch {
            throw APIError.transporte("No se pudo conectar con el servidor.")
        }
    }

    private func validar(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.transporte("Respuesta no HTTP.")
        }

        guard (200..<300).contains(http.statusCode) else {
            // El backend devuelve siempre el mismo contrato de error.
            if let apiError = try? decoder.decode(APIError.self, from: data) {
                avisarSiLaSesionMurio(apiError)
                throw apiError
            }
            throw APIError(
                status: http.statusCode,
                error: "ERROR",
                message: mensajeGenerico(http.statusCode),
                path: nil, correlationId: nil, motivo: nil,
                fieldErrors: nil, intentosRestantes: nil,
                reintentarEnSegundos: nil, bloqueadoHasta: nil, nivel: nil)
        }
    }

    /// Un `401 NO_AUTENTICADO` significa que el token guardado ya no sirve
    /// (expiró, se revocó o cambió `credencialesVersion`). Se avisa a la UI
    /// para que borre el Keychain y vuelva al login: sin esto la app se queda
    /// "autenticada" en memoria mostrando errores en cada pantalla.
    private func avisarSiLaSesionMurio(_ error: APIError) {
        guard error.esSesionExpirada else { return }
        // Se publica en el hilo principal: SwiftUI (`onReceive`) debe recibir
        // el evento donde vive el estado de la vista.
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: SesionEventos.sesionExpirada,
                                            object: nil)
        }
    }

    private func mensajeGenerico(_ status: Int) -> String {
        switch status {
        case 400: return "La petición contiene datos inválidos."
        case 401: return "Tu sesión expiró. Inicia sesión nuevamente."
        case 403: return "No tienes permisos para esta acción."
        case 404: return "El recurso no existe."
        case 409: return "La operación entra en conflicto con el estado actual."
        case 429: return "Demasiados intentos. Espera un momento."
        case 500...599: return "Error interno del servidor."
        default: return "Ocurrió un error inesperado."
        }
    }

    private func mensajeTransporte(_ error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet:
            return "Sin conexión a internet."
        case .cannotConnectToHost, .cannotFindHost:
            return "No se pudo conectar con el servidor. Verifica que el backend esté activo."
        case .timedOut:
            return "El servidor tardó demasiado en responder."
        default:
            return "Error de red: \(error.localizedDescription)"
        }
    }
}
