import Foundation

/// Configuración de la aplicación.
///
/// La URL base se lee de Info.plist para no recompilar al cambiar entre
/// simulador (localhost) y iPhone físico (IP del Mac).
enum AppConfig {

    /// Raíz de la API, por ejemplo `http://localhost:8082/api`.
    static let baseURL: URL = {
        guard
            let raw = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
            let url = URL(string: raw)
        else {
            fatalError("API_BASE_URL ausente o inválida en Info.plist")
        }
        return url
    }()

    /// Raíz de los recursos estáticos (fotos del catálogo).
    ///
    /// El backend guarda rutas relativas tipo `/img/habitaciones/suite.jpg`
    /// que sirve el frontend web, no la API. Se configura aparte para poder
    /// apuntar al servidor de imágenes en producción.
    static let webURL: URL = {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "WEB_BASE_URL") as? String,
           let url = URL(string: raw) {
            return url
        }
        // Respaldo: mismo host que la API, sin el sufijo /api.
        var componentes = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        componentes?.path = ""
        return componentes?.url ?? baseURL
    }()

    static let appName = "Hotel PMS"
    static let moneda = "PEN"

    /// Refresco automático del panel de operación.
    static let refrescoDashboardSegundos: UInt64 = 30

    /// Minutos antes de la expiración en que se avisa al cliente.
    static let avisoExpiracionMinutos = 5

    /// Resuelve una ruta de imagen del backend a una URL absoluta.
    ///
    /// Acepta tanto rutas relativas (`/img/...`) como URLs completas, de modo
    /// que si mañana el backend devuelve un CDN la app sigue funcionando.
    static func imagenURL(_ ruta: String?) -> URL? {
        guard let ruta, !ruta.isEmpty else { return nil }

        if ruta.hasPrefix("http://") || ruta.hasPrefix("https://") {
            return URL(string: ruta)
        }

        // Las fotos subidas se sirven desde el API (/api/imagenes/N), no desde
        // el sitio web. Usar webURL daria 404 porque el frontend es estatico.
        if ruta.hasPrefix("/api/") {
            let limpia = String(ruta.dropFirst())
            // baseURL ya termina en /api
            let sinApi = limpia.hasPrefix("api/") ? String(limpia.dropFirst(4)) : limpia
            return baseURL.appendingPathComponent(sinApi)
        }

        let limpia = ruta.hasPrefix("/") ? String(ruta.dropFirst()) : ruta
        return webURL.appendingPathComponent(limpia)
    }
}
