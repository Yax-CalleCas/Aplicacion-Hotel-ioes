import Foundation

/// Servicio de API del hotel.
///
/// Reutiliza el `APIClient` (actor con JWT + correlationId) y expone **cada**
/// endpoint del backend agrupado por dominio. Todos los métodos son `async`
/// y lanzan `APIError` ya tipado.
///
/// Mapa de controladores del backend:
///  - AuthController         → /auth
///  - InventarioController   → /sedes, /categorias, /disponibilidad, /pisos,
///                             /habitaciones, /temporadas, /tarifas
///  - ReservaController      → /reservas, /estadias, /cargos, /pagos
///  - OperacionesController  → /housekeeping, /notificaciones
///  - ReporteController      → /reportes
///  - AdminController        → /admin (usuarios, roles, sedes)
final class HotelAPI {

    static let shared = HotelAPI()

    private let client: APIClient

    init(client: APIClient = APIClient()) {
        self.client = client
    }

    // ==================================================================
    // MARK: - Autenticación
    // ==================================================================

    /// Login con bloqueo progresivo. Lanza `APIError` 401 o 429.
    func login(email: String, password: String) async throws -> AuthResponse {
        try await client.post("auth/login", body: LoginRequest(email: email, password: password))
    }

    /// Registro de cliente. Devuelve la sesión ya iniciada.
    func registrar(_ request: RegisterRequest) async throws -> AuthResponse {
        try await client.post("auth/register", body: request)
    }

    /// Perfil del usuario autenticado (se usa al restaurar la sesión).
    func perfil() async throws -> Usuario {
        try await client.get("auth/me")
    }

    /// Login social (mock OAuth). Lanza 409 si requiere vinculación manual.
    func loginSocial(_ request: SocialLoginRequest) async throws -> AuthResponse {
        try await client.post("auth/social", body: request)
    }

    /// Cambio de contraseña del propio usuario.
    ///
    /// El backend responde `204 No Content` y **sube `credencialesVersion`**,
    /// así que el token en uso queda muerto al instante. La UI debe cerrar
    /// sesión justo después de un éxito (por eso devuelve `Void`).
    func cambiarPassword(actual: String, nueva: String) async throws {
        try await client.postVoid("auth/cambiar-password",
                                  body: CambiarPasswordRequest(passwordActual: actual,
                                                               passwordNueva: nueva))
    }

    /// Cierre de sesión real: sube la versión de credenciales en el servidor,
    /// con lo que el token deja de valer aunque alguien lo haya copiado.
    func logout() async throws {
        try await client.postVoid("auth/cerrar-sesiones")
    }

    // ==================================================================
    // MARK: - Catálogo público
    // ==================================================================

    func sedes() async throws -> [Sede] {
        try await client.get("sedes")
    }

    func categorias(sedeId: Int) async throws -> [CategoriaHabitacion] {
        try await client.get("categorias", query: ["sedeId": String(sedeId)])
    }

    /// Disponibilidad real por fechas, ya con foto y descripción.
    func disponibilidad(sedeId: Int, checkIn: String, checkOut: String) async throws -> [Disponibilidad] {
        try await client.get("disponibilidad", query: [
            "sedeId": String(sedeId),
            "checkIn": checkIn,
            "checkOut": checkOut,
        ])
    }

    // ==================================================================
    // MARK: - Reservas
    // ==================================================================

    /// Reservas del usuario autenticado (cliente).
    func misReservas() async throws -> [ReservaResumen] {
        try await client.get("reservas/mias")
    }

    /// Listado operativo por sede/estado/rango (recepción, gerencia, admin).
    ///
    /// `checkOut` filtra por fecha de salida exacta y es lo que usa el panel
    /// para "Salidas de hoy": sin él, el rango `desde`/`hasta` aplica sobre
    /// `checkIn` y una estancia que empezó hace una semana nunca aparecía.
    func reservas(sedeId: Int? = nil,
                  estado: String? = nil,
                  desde: String? = nil,
                  hasta: String? = nil,
                  checkOut: String? = nil) async throws -> [ReservaResumen] {
        var query: [String: String] = [:]
        if let sedeId { query["sedeId"] = String(sedeId) }
        if let estado, !estado.isEmpty { query["estado"] = estado }
        if let desde { query["desde"] = desde }
        if let hasta { query["hasta"] = hasta }
        if let checkOut { query["checkOut"] = checkOut }
        return try await client.get("reservas", query: query)
    }

    func reserva(id: Int) async throws -> Reserva {
        try await client.get("reservas/\(id)")
    }

    /// Búsqueda por código de reserva (pantalla "buscar reserva").
    func reserva(codigo: String) async throws -> Reserva {
        try await client.get("reservas/codigo/\(codigo)")
    }

    func crearReserva(_ request: CrearReservaRequest) async throws -> Reserva {
        try await client.post("reservas", body: request)
    }

    func cancelarReserva(id: Int, motivo: String?) async throws -> Reserva {
        try await client.post("reservas/\(id)/cancelar",
                              body: CancelarReservaRequest(motivo: motivo ?? ""))
    }

    // ---- Folio ----

    /// Cuenta de la reserva: cargos, pagos y saldo.
    func folio(reservaId: Int) async throws -> Folio {
        try await client.get("reservas/\(reservaId)/folio")
    }

    /// Cargo extra (minibar, restaurante, lavandería...) al folio.
    func agregarCargo(reservaId: Int,
                      concepto: String,
                      descripcion: String,
                      cantidad: Decimal,
                      precioUnitario: Decimal) async throws -> Cargo {
        let request = CrearCargoRequest(concepto: concepto,
                                        descripcion: descripcion,
                                        cantidad: cantidad,
                                        precioUnitario: precioUnitario)
        return try await client.post("reservas/\(reservaId)/cargos", body: request)
    }

    /// Anula un cargo (nunca se borra: queda en el historial).
    func anularCargo(cargoId: Int, motivo: String) async throws -> Cargo {
        try await client.post("cargos/\(cargoId)/anular",
                              body: AnularCargoRequest(motivo: motivo))
    }

    // ---- Pagos ----

    /// Registra un pago. Es idempotente por `idempotencyKey`.
    func registrarPago(reservaId: Int, request: CrearPagoRequest) async throws -> Pago {
        try await client.post("reservas/\(reservaId)/pagos", body: request)
    }

    /// QR del deposito (pasarela simulada). Idempotente: reutiliza el pago
    /// pendiente si ya existe, no crea un segundo cobro.
    func qrDeposito(reservaId: Int) async throws -> PagoQr {
        try await client.get("reservas/\(reservaId)/pago/qr")
    }

    /// PNG del QR de la reserva, para ensenarlo en recepcion al hacer check-in.
    func qrReserva(reservaId: Int) async throws -> Data {
        try await client.descargar("reservas/\(reservaId)/qr")
    }

    /// Sube una foto del catalogo y devuelve su URL relativa.
    func subirImagen(datos: Data, nombre: String) async throws -> ImagenSubida {
        try await client.subirArchivo("imagenes", datos: datos, nombre: nombre)
    }

    /// Pagos pendientes de verificación (recepción).
    func pagosPendientes() async throws -> [Pago] {
        try await client.get("pagos/pendientes")
    }

    func aprobarPago(id: Int, codigoOperacion: String?,
                     observacion: String? = nil) async throws -> Pago {
        try await client.post("pagos/\(id)/aprobar",
                              body: AprobarPagoRequest(codigoOperacion: codigoOperacion,
                                                       observacion: observacion))
    }

    func rechazarPago(id: Int, motivo: String, observacion: String? = nil) async throws -> Pago {
        try await client.post("pagos/\(id)/rechazar",
                              body: RechazarPagoRequest(motivo: motivo,
                                                        observacion: observacion))
    }

    // ==================================================================
    // MARK: - Estadia (check-in / check-out)
    // ==================================================================

    func checkIn(reservaId: Int, request: CheckInRequest) async throws -> Estadia {
        try await client.post("reservas/\(reservaId)/check-in", body: request)
    }

    func checkOut(estadiaId: Int, observaciones: String? = nil,
                  cerrarFolio: Bool = true) async throws -> Estadia {
        try await client.post("estadias/\(estadiaId)/check-out",
                              body: CheckOutRequest(observaciones: observaciones,
                                                    cerrarFolio: cerrarFolio))
    }

    func estadiasActivas() async throws -> [Estadia] {
        try await client.get("estadias/activas")
    }

    // ==================================================================
    // MARK: - Inventario operativo
    // ==================================================================

    func habitaciones(sedeId: Int, estado: String? = nil) async throws -> ListaHabitaciones {
        var query = ["sedeId": String(sedeId)]
        if let estado, !estado.isEmpty { query["estado"] = estado }
        return try await client.get("habitaciones", query: query)
    }

    func habitacion(id: Int) async throws -> Habitacion {
        try await client.get("habitaciones/\(id)")
    }

    func crearHabitacion(_ request: CrearHabitacionRequest) async throws -> Habitacion {
        try await client.post("habitaciones", body: request)
    }

    func actualizarHabitacion(id: Int, request: ActualizarHabitacionRequest) async throws -> Habitacion {
        try await client.put("habitaciones/\(id)", body: request)
    }

    /// Cambia de estado (mantenimiento, fuera de servicio, disponible...).
    func cambiarEstadoHabitacion(id: Int, estado: String,
                                 motivo: String? = nil) async throws -> Habitacion {
        try await client.patch("habitaciones/\(id)/estado",
                               body: CambiarEstadoHabitacionRequest(estado: estado,
                                                                    motivo: motivo))
    }

    /// Historial de estados de la habitación (auditoría).
    func historialHabitacion(id: Int) async throws -> [HabitacionEstadoLog] {
        try await client.get("habitaciones/\(id)/historial")
    }

    func pisos(sedeId: Int) async throws -> [Piso] {
        try await client.get("pisos", query: ["sedeId": String(sedeId)])
    }

    func crearPiso(_ request: CrearPisoRequest) async throws -> Piso {
        try await client.post("pisos", body: request)
    }

    func actualizarPiso(id: Int, request: CrearPisoRequest) async throws -> Piso {
        try await client.put("pisos/\(id)", body: request)
    }

    func eliminarPiso(id: Int) async throws {
        try await client.delete("pisos/\(id)")
    }

    func crearCategoria(_ request: CrearCategoriaRequest) async throws -> CategoriaHabitacion {
        try await client.post("categorias", body: request)
    }

    func actualizarCategoria(id: Int, request: CrearCategoriaRequest) async throws -> CategoriaHabitacion {
        try await client.put("categorias/\(id)", body: request)
    }

    func eliminarCategoria(id: Int) async throws {
        try await client.delete("categorias/\(id)")
    }

    func temporadas(sedeId: Int) async throws -> [Temporada] {
        try await client.get("temporadas", query: ["sedeId": String(sedeId)])
    }

    func tarifas(categoriaId: Int) async throws -> [Tarifa] {
        try await client.get("tarifas", query: ["categoriaId": String(categoriaId)])
    }

    func crearTarifa(_ request: CrearTarifaRequest) async throws -> Tarifa {
        try await client.post("tarifas", body: request)
    }

    // ==================================================================
    // MARK: - Housekeeping
    // ==================================================================

    /// Tareas del usuario (housekeeping ve las suyas; admin ve todas).
    func tareas(estado: String? = nil) async throws -> [TareaLimpieza] {
        var query: [String: String] = [:]
        if let estado, !estado.isEmpty { query["estado"] = estado }
        return try await client.get("housekeeping/tareas", query: query)
    }

    /// Todas las tareas de la sede (admin y gerente).
    func todasLasTareas() async throws -> [TareaLimpieza] {
        try await client.get("housekeeping/tareas/todas")
    }

    func crearTarea(_ request: CrearTareaRequest) async throws -> TareaLimpieza {
        try await client.post("housekeeping/tareas", body: request)
    }

    /// Avanza el flujo de la tarea. Usa PATCH con body (el backend lo exige).
    func actualizarTarea(id: Int, estado: String,
                         observaciones: String? = nil) async throws -> TareaLimpieza {
        try await client.patch("housekeeping/tareas/\(id)",
                               body: ActualizarTareaRequest(estado: estado,
                                                            observaciones: observaciones))
    }

    /// Reporta una incidencia de mantenimiento desde una habitación.
    func crearIncidencia(habitacionId: Int, descripcion: String,
                         prioridad: String = "NORMAL") async throws -> Void {
        // El backend responde 201 con la incidencia; aquí solo interesa el éxito.
        let _: IncidenciaCreada = try await client.post(
            "housekeeping/incidencias",
            body: CrearIncidenciaRequest(habitacionId: habitacionId,
                                         descripcion: descripcion,
                                         prioridad: prioridad))
    }

    /// Respuesta mínima de la incidencia (el backend devuelve la entidad completa).
    private struct IncidenciaCreada: Decodable, Sendable {
        let id: Int?
    }

    // ==================================================================
    // MARK: - Notificaciones
    // ==================================================================

    func notificaciones() async throws -> [Notificacion] {
        try await client.get("notificaciones")
    }

    func noLeidas() async throws -> Int {
        let respuesta: [String: Int] = try await client.get("notificaciones/no-leidas")
        return respuesta["cantidad"] ?? 0
    }

    func marcarLeida(id: Int) async throws {
        try await client.postVoid("notificaciones/\(id)/leer")
    }

    // ==================================================================
    // MARK: - Reportes
    // ==================================================================

    func dashboard(sedeId: Int? = nil) async throws -> Dashboard {
        var query: [String: String] = [:]
        if let sedeId { query["sedeId"] = String(sedeId) }
        return try await client.get("reportes/dashboard", query: query)
    }

    func kpis(sedeId: Int, desde: String, hasta: String) async throws -> Kpi {
        try await client.get("reportes/kpis", query: [
            "sedeId": String(sedeId), "desde": desde, "hasta": hasta,
        ])
    }

    func ocupacion(sedeId: Int, desde: String, hasta: String) async throws -> ReporteOcupacion {
        try await client.get("reportes/ocupacion", query: [
            "sedeId": String(sedeId), "desde": desde, "hasta": hasta,
        ])
    }

    func ingresosPorCategoria(sedeId: Int, desde: String,
                              hasta: String) async throws -> [IngresoPorCategoria] {
        try await client.get("reportes/ingresos/categoria", query: [
            "sedeId": String(sedeId), "desde": desde, "hasta": hasta,
        ])
    }

    func ingresosPorConcepto(sedeId: Int, desde: String,
                             hasta: String) async throws -> [IngresoPorConcepto] {
        try await client.get("reportes/ingresos/concepto", query: [
            "sedeId": String(sedeId), "desde": desde, "hasta": hasta,
        ])
    }

    // ==================================================================
    // MARK: - Administración (solo ADMIN)
    // ==================================================================

    func usuarios() async throws -> [Usuario] {
        try await client.get("admin/usuarios")
    }

    func usuario(id: Int) async throws -> Usuario {
        try await client.get("admin/usuarios/\(id)")
    }

    func crearUsuario(_ request: CrearUsuarioRequest) async throws -> Usuario {
        try await client.post("admin/usuarios", body: request)
    }

    func actualizarUsuario(id: Int, request: ActualizarUsuarioRequest) async throws -> Usuario {
        try await client.put("admin/usuarios/\(id)", body: request)
    }

    func cambiarEstadoUsuario(id: Int, activo: Bool, motivo: String? = nil) async throws -> Usuario {
        try await client.patch("admin/usuarios/\(id)/estado",
                               body: CambiarEstadoUsuarioRequest(activo: activo, motivo: motivo))
    }

    func resetPassword(id: Int, password: String) async throws -> Usuario {
        let cuerpo: [String: String] = ["password": password]
        return try await client.post("admin/usuarios/\(id)/reset-password", body: cuerpo)
    }

    func estadoBloqueo(usuarioId: Int) async throws -> BloqueoCuenta {
        try await client.get("admin/usuarios/\(usuarioId)/bloqueo")
    }

    func desbloquear(usuarioId: Int) async throws {
        try await client.postVoid("admin/usuarios/\(usuarioId)/desbloquear")
    }

    func roles() async throws -> [Rol] {
        try await client.get("admin/roles")
    }

    func permisos() async throws -> [String] {
        try await client.get("admin/permisos")
    }

    func crearRol(_ request: CrearRolRequest) async throws -> Rol {
        try await client.post("admin/roles", body: request)
    }

    func actualizarRol(id: Int, request: CrearRolRequest) async throws -> Rol {
        try await client.put("admin/roles/\(id)", body: request)
    }

    func eliminarRol(id: Int) async throws {
        try await client.delete("admin/roles/\(id)")
    }

    func sedesAdmin() async throws -> [Sede] {
        try await client.get("admin/sedes")
    }

    func crearSede(_ request: CrearSedeRequest) async throws -> Sede {
        try await client.post("admin/sedes", body: request)
    }

    func actualizarSede(id: Int, request: CrearSedeRequest) async throws -> Sede {
        try await client.put("admin/sedes/\(id)", body: request)
    }

    func desactivarSede(id: Int) async throws {
        try await client.delete("admin/sedes/\(id)")
    }

    // ==================================================================
    // MARK: - Servicio a la habitación
    // ==================================================================

    /// Catálogo de productos activos (cliente y recepción).
    func productos(categoria: String? = nil) async throws -> [Producto] {
        var query: [String: String] = [:]
        if let categoria, !categoria.isEmpty { query["categoria"] = categoria }
        return try await client.get("productos", query: query)
    }

    // ---- Cliente ----

    /// Crea una solicitud. Solo funciona con check-in activo.
    func crearSolicitud(items: [ItemSolicitudRequest],
                        observaciones: String?) async throws -> SolicitudConsumo {
        try await client.post("servicio-habitacion",
                              body: CrearSolicitudRequest(items: items,
                                                          observaciones: observaciones))
    }

    func misSolicitudes() async throws -> [SolicitudConsumo] {
        try await client.get("servicio-habitacion/mias")
    }

    func cancelarSolicitud(id: Int) async throws -> SolicitudConsumo {
        try await client.post("servicio-habitacion/\(id)/cancelar")
    }

    // ---- Recepción ----

    func solicitudesPendientes() async throws -> [SolicitudConsumo] {
        try await client.get("servicio-habitacion/pendientes")
    }

    func solicitudes(estado: String) async throws -> [SolicitudConsumo] {
        try await client.get("servicio-habitacion/estado/\(estado)")
    }

    func solicitud(id: Int) async throws -> SolicitudConsumo {
        try await client.get("servicio-habitacion/\(id)")
    }

    /// Aprueba y carga al folio. Idempotente.
    func aprobarSolicitud(id: Int, observacion: String? = nil) async throws -> SolicitudConsumo {
        try await client.post("servicio-habitacion/\(id)/aprobar",
                              body: AprobarSolicitudRequest(observacion: observacion))
    }

    func rechazarSolicitud(id: Int, motivo: String) async throws -> SolicitudConsumo {
        try await client.post("servicio-habitacion/\(id)/rechazar",
                              body: RechazarSolicitudRequest(motivo: motivo))
    }

    func entregarSolicitud(id: Int) async throws -> SolicitudConsumo {
        try await client.post("servicio-habitacion/\(id)/entregar")
    }

    // ---- Administración del catálogo ----

    func catalogoAdmin() async throws -> [Producto] {
        try await client.get("admin/productos")
    }

    func crearProducto(_ request: CrearProductoRequest) async throws -> Producto {
        try await client.post("admin/productos", body: request)
    }

    func actualizarProducto(id: Int,
                            request: ActualizarProductoRequest) async throws -> Producto {
        try await client.put("admin/productos/\(id)", body: request)
    }

    // ==================================================================
    // MARK: - Registro walk-in (recepción)
    // ==================================================================

    /// Alta en mostrador: crea cliente si no existe y devuelve las credenciales.
    func walkIn(_ request: WalkInRequest) async throws -> WalkInResponse {
        try await client.post("reception/walk-in", body: request)
    }

    /// Comprobación previa: ¿este documento ya tiene ficha?
    func buscarHuesped(tipoDocumento: String,
                       numeroDocumento: String) async throws -> BusquedaHuespedResponse {
        try await client.get("reception/walk-in/buscar", query: [
            "tipoDocumento": tipoDocumento,
            "numeroDocumento": numeroDocumento,
        ])
    }
}
