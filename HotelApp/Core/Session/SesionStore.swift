import Foundation
import Observation

/// Estado de sesión del hotel.
///
/// Maneja login con bloqueo progresivo, restauración del token desde el
/// Keychain y cierre de sesión.
@MainActor
@Observable
final class SesionStore {

    enum Estado: Equatable {
        case desconocido
        case sinSesion
        case autenticado(Usuario)
    }

    private(set) var estado: Estado = .desconocido
    private(set) var cargando = false

    private let api = HotelAPI.shared
    private let tokenStore = TokenStore.shared

    var usuario: Usuario? {
        if case .autenticado(let u) = estado { return u }
        return nil
    }

    var autenticado: Bool { usuario != nil }
    var esAdmin: Bool { usuario?.esAdmin ?? false }
    var esGerente: Bool { usuario?.esGerente ?? false }
    var esRecepcionista: Bool { usuario?.esRecepcionista ?? false }
    var esHousekeeping: Bool { usuario?.esHousekeeping ?? false }
    var esCliente: Bool { usuario?.esCliente ?? false }
    var puedeOperar: Bool { usuario?.puedeOperar ?? false }
    var sedePrincipal: Sede? { usuario?.sedePrincipal }

    // MARK: - Arranque

    func restaurarSesion() async {
        guard await tokenStore.token() != nil else {
            estado = .sinSesion
            return
        }

        do {
            let usuario = try await api.perfil()
            estado = .autenticado(usuario)
        } catch let error as APIError where error.esSesionExpirada {
            // Token revocado o expirado: se purga también el cache de Core Data
            // para que el siguiente usuario no vea reservas ajenas.
            await cerrarSesionLocal()
        } catch {
            // Fallo de red al arrancar: no se destruye una sesión válida por
            // un corte momentáneo (eso obligaba a teclear la contraseña en
            // cada arranque sin cobertura). El token se conserva y el login
            // puede reintentar la restauración.
            estado = .sinSesion
        }
    }

    // MARK: - Login

    func iniciarSesion(email: String, password: String) async -> ResultadoLogin {
        cargando = true
        defer { cargando = false }

        do {
            let respuesta = try await api.login(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                password: password)

            await tokenStore.guardar(respuesta.accessToken)
            estado = .autenticado(respuesta.usuario)
            return .exito
        } catch let error as APIError {
            if error.esBloqueo {
                return .bloqueado(segundos: error.reintentarEnSegundos ?? 60,
                                  mensaje: error.mensajeUsuario)
            }
            return .fallo(mensaje: error.mensajeUsuario,
                          intentosRestantes: error.intentosRestantes,
                          motivo: error.motivo)
        } catch {
            return .fallo(mensaje: "No se pudo iniciar sesión.",
                          intentosRestantes: nil, motivo: nil)
        }
    }

    // MARK: - Login social

    /// Login con proveedor social (mock). Devuelve 409 si requiere vinculación.
    func iniciarSesionSocial(proveedor: String, cuenta: CuentaSocial) async -> ResultadoLogin {
        cargando = true
        defer { cargando = false }

        do {
            let respuesta = try await api.loginSocial(SocialLoginRequest(
                proveedor: proveedor,
                token: "mock-\(proveedor.lowercased())-\(cuenta.email)",
                email: cuenta.email,
                nombre: cuenta.nombre,
                apellido: cuenta.apellido,
                emailVerificado: true))

            await tokenStore.guardar(respuesta.accessToken)
            estado = .autenticado(respuesta.usuario)
            return .exito
        } catch let error as APIError {
            return .fallo(mensaje: error.mensajeUsuario,
                          intentosRestantes: nil,
                          motivo: error.motivo)
        } catch {
            return .fallo(mensaje: "No se pudo iniciar sesión con \(proveedor).",
                          intentosRestantes: nil, motivo: nil)
        }
    }

    /// Login real con Facebook: el ID Token de Firebase viaja al backend.
    func iniciarSesionFacebookReal() async -> ResultadoLogin {
        cargando = true
        defer { cargando = false }

        do {
            let credencial = try await SocialAuthManager.entrarConFacebook()

            let respuesta = try await api.loginSocial(SocialLoginRequest(
                proveedor: "FACEBOOK",
                token: credencial.idToken,
                email: credencial.email ?? "",
                nombre: credencial.nombre,
                apellido: nil,
                emailVerificado: true))

            await tokenStore.guardar(respuesta.accessToken)
            estado = .autenticado(respuesta.usuario)
            return .exito
        } catch let error as SocialAuthManager.ErrorSocial {
            return .fallo(mensaje: error.errorDescription ?? "Error de Facebook.",
                          intentosRestantes: nil, motivo: "SOCIAL_CANCELADO")
        } catch let error as APIError {
            return .fallo(mensaje: error.mensajeUsuario,
                          intentosRestantes: nil,
                          motivo: error.motivo)
        } catch {
            return .fallo(mensaje: "No se pudo iniciar sesión con Facebook.",
                          intentosRestantes: nil, motivo: nil)
        }
    }

    // MARK: - Registro

    func registrar(nombre: String, email: String, password: String,
                   telefono: String?) async -> ResultadoLogin {
        cargando = true
        defer { cargando = false }

        do {
            let respuesta = try await api.registrar(RegisterRequest(
                nombre: nombre.trimmingCharacters(in: .whitespaces),
                email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                password: password,
                telefono: telefono?.isEmpty == true ? nil : telefono))

            await tokenStore.guardar(respuesta.accessToken)
            estado = .autenticado(respuesta.usuario)
            return .exito
        } catch let error as APIError {
            return .fallo(mensaje: error.mensajeUsuario,
                          intentosRestantes: nil, motivo: error.motivo)
        } catch {
            return .fallo(mensaje: "No se pudo crear la cuenta.",
                          intentosRestantes: nil, motivo: nil)
        }
    }

    // MARK: - Logout

    /// Cierra sesión: revoca el token en el servidor (sube la versión de
    /// credenciales), lo borra del Keychain y limpia el cache de Core Data.
    /// El estado local se limpia aunque el servidor falle, para que el usuario
    /// nunca quede atrapado.
    func cerrarSesion() async {
        try? await api.logout()
        await cerrarSesionLocal()
    }

    /// Cierre de sesión **sin** llamar al servidor.
    ///
    /// Se usa cuando el backend ya rechazó el token (`401 NO_AUTENTICADO`:
    /// expiró, se revocó o `credencialesVersion` cambió tras cambiar la
    /// contraseña). Llamar a `auth/cerrar-sesiones` en ese estado solo
    /// produciría otro 401.
    func cerrarSesionLocal() async {
        await tokenStore.eliminar()
        PersistenciaController.shared.limpiarTodo()
        NotificacionService.cancelarAvisos()
        estado = .sinSesion
    }

    // MARK: - Reautenticación biométrica

    /// Indica si hay un token guardado (para ofrecer Face ID al arrancar).
    func tieneTokenGuardado() async -> Bool {
        await tokenStore.token() != nil
    }

    /// Pide Face ID / Touch ID antes de mostrar datos sensibles.
    /// Devuelve `true` si se puede continuar (también cuando no hay biometría).
    func verificarIdentidad(motivo: String = "Confirma tu identidad para continuar") async -> Bool {
        let resultado = await BiometriaService.autenticar(motivo: motivo)
        switch resultado {
        case .exito, .noDisponible:
            return true
        case .cancelado, .fallo:
            return false
        }
    }
}

enum ResultadoLogin {
    case exito
    case fallo(mensaje: String, intentosRestantes: Int?, motivo: String?)
    case bloqueado(segundos: Int, mensaje: String)
}

// MARK: - Sede activa compartida

/// Sede activa compartida por toda la app (panel, habitaciones, reportes).
///
/// Antes cada pantalla guardaba su propia sede: cambiabas a Piura en el panel
/// y Habitaciones seguía mostrando Lima. Con un único origen de verdad, el
/// cambio se propaga a todas las pestañas.
///
/// Vive en este archivo —y no en uno propio— porque el `.xcodeproj` está en
/// `.gitignore`: al clonar, cualquier archivo nuevo queda fuera del proyecto
/// hasta que alguien añada la referencia a mano. `SesionStore.swift` ya existe
/// en todos los clones, así que aquí el tipo está siempre disponible.
@MainActor
@Observable
final class SedeActivaStore {

    /// Sede elegida. `nil` significa "la sede principal del usuario".
    private(set) var sedeId: Int?

    /// Devuelve la sede efectiva para un usuario, aplicando el valor por
    /// defecto cuando aún no hay elección o la elegida ya no existe.
    func efectiva(para usuario: Usuario) -> Sede? {
        guard let sedeId else { return usuario.sedePrincipal }
        return usuario.sedes.first { $0.id == sedeId } ?? usuario.sedePrincipal
    }

    /// Id efectivo, útil para las llamadas a la API.
    func idEfectivo(para usuario: Usuario) -> Int? {
        efectiva(para: usuario)?.id
    }

    /// Cambia la sede. Ignora el toque si ya está activa, para no recargar.
    /// Devuelve `true` si hubo cambio real.
    @discardableResult
    func seleccionar(_ id: Int, para usuario: Usuario) -> Bool {
        guard id != idEfectivo(para: usuario) else { return false }
        guard usuario.sedes.contains(where: { $0.id == id }) else { return false }
        sedeId = id
        return true
    }

    /// Al cerrar sesión: la sede de una cuenta no debe arrastrarse a otra.
    func limpiar() {
        sedeId = nil
    }
}
