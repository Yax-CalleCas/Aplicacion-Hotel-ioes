import Foundation
import Observation

/// Estado del panel de operación (recepción, gerencia, admin, housekeeping).
///
/// Centraliza:
///  - Dashboard y KPIs.
///  - Llegadas/salidas del día.
///  - Habitaciones por estado.
///  - Pagos pendientes de verificación.
///  - Tareas de housekeeping (para el home reducido de limpieza).
///
/// Las vistas solo leen de aquí: así una acción (aprobar un pago) refresca
/// todas las pantallas a la vez sin duplicar peticiones.
@MainActor
@Observable
final class OperacionStore {

    private(set) var dashboard: Dashboard?
    private(set) var llegadas: [ReservaResumen] = []
    private(set) var salidas: [ReservaResumen] = []
    private(set) var habitaciones: ListaHabitaciones?
    private(set) var pagosPendientes: [Pago] = []
    /// Tareas pendientes del usuario. Solo lo usa el home de housekeeping,
    /// que no tiene permiso para el dashboard.
    private(set) var tareasPendientes: [TareaLimpieza] = []

    private(set) var cargando = false
    private(set) var error: String?
    /// Error propio de la lista de pagos: no debe mezclarse con el del
    /// dashboard, porque uno puede cargar y el otro fallar (por ejemplo, un
    /// gerente ve el panel pero el backend le niega la cola de verificación).
    private(set) var errorPagos: String?

    private let api = HotelAPI.shared

    // MARK: - Dashboard

    /// Carga KPIs, llegadas y salidas del día de la sede.
    ///
    /// Requiere rol ADMIN, GERENTE o RECEPCIONISTA (`/reportes/dashboard`).
    /// Housekeeping **no** llama aquí: usar `cargarTareasPendientes()`.
    func cargarDashboard(sedeId: Int?) async {
        cargando = true
        error = nil
        defer { cargando = false }

        do {
            dashboard = try await api.dashboard(sedeId: sedeId)
        } catch let apiError as APIError {
            error = apiError.mensajeUsuario
        } catch {
            self.error = "No se pudo cargar el panel."
        }

        await cargarLlegadasYSalidas(sedeId: sedeId)
    }

    /// Llegadas y salidas **de hoy**.
    ///
    /// Antes se pedía `/reservas?sedeId=` sin fechas: el backend aplica
    /// `desde = hoy − 1 mes` y `hasta = hoy + 6 meses`, así que la lista
    /// mostraba llegadas de siete meses y no las de hoy.
    func cargarLlegadasYSalidas(sedeId: Int?) async {
        guard let sedeId else {
            llegadas = []
            salidas = []
            return
        }

        let hoy = FechaAPI.soloFecha(Date())
        // El backend filtra `desde`/`hasta` por fecha de ENTRADA, así que para
        // las salidas se usa el parámetro `checkOut` (fecha exacta). Si el
        // backend desplegado aún no lo soporta, se cae a la ventana amplia y
        // se recorta en cliente.
        let inicioAncho = FechaAPI.soloFecha(
            Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date())

        do {
            // Secuencial a propósito: `async let` sobre una instancia no
            // `Sendable` es error en Swift 6.
            llegadas = try await api.reservas(sedeId: sedeId,
                                              estado: "CONFIRMADA",
                                              desde: hoy,
                                              hasta: hoy)

            let enCurso = try await api.reservas(sedeId: sedeId,
                                                 estado: "EN_CURSO",
                                                 desde: inicioAncho,
                                                 hasta: hoy,
                                                 checkOut: hoy)
            salidas = enCurso.filter { $0.checkOut == hoy }
        } catch let apiError as APIError {
            llegadas = []
            salidas = []
            // Si el dashboard ya cargó, el error de las listas no debe tapar
            // las cifras: se informa pero se conserva lo que hay.
            self.error = self.error ?? apiError.mensajeUsuario
        } catch {
            llegadas = []
            salidas = []
            self.error = self.error ?? "No se pudieron cargar llegadas y salidas."
        }
    }

    // MARK: - Habitaciones

    /// Tablero de habitaciones, opcionalmente filtrado por estado.
    func cargarHabitaciones(sedeId: Int, estado: String?) async {
        cargando = true
        error = nil
        defer { cargando = false }

        do {
            habitaciones = try await api.habitaciones(sedeId: sedeId, estado: estado)
        } catch let apiError as APIError {
            error = apiError.mensajeUsuario
        } catch {
            self.error = "No se pudieron cargar las habitaciones."
        }
    }

    /// Cambia el estado de una habitación y recarga el tablero.
    func cambiarEstado(habitacionId: Int, estado: String, motivo: String?,
                       sedeId: Int) async throws {
        _ = try await api.cambiarEstadoHabitacion(id: habitacionId,
                                                  estado: estado,
                                                  motivo: motivo)
        await cargarHabitaciones(sedeId: sedeId, estado: nil)
    }

    // MARK: - Tareas (housekeeping)

    /// Tareas pendientes del usuario autenticado.
    ///
    /// Es el único dato que necesita el home de housekeeping: ese rol no tiene
    /// permiso sobre `/reportes/dashboard` ni `/reservas`.
    func cargarTareasPendientes() async {
        cargando = true
        error = nil
        defer { cargando = false }

        do {
            tareasPendientes = try await api.tareas(estado: "PENDIENTE")
        } catch let apiError as APIError {
            tareasPendientes = []
            error = apiError.mensajeUsuario
        } catch {
            tareasPendientes = []
            self.error = "No se pudieron cargar tus tareas."
        }
    }

    /// Tareas pendientes para el bloque "Limpieza pendiente" del panel
    /// operativo (admin/gerente/recepción).
    ///
    /// No toca `error` ni `cargando`: el panel ya está mostrando el dashboard y
    /// un fallo aquí no debe tapar las cifras ni hacer parpadear la pantalla.
    func cargarTareasPendientesOperacion() async {
        tareasPendientes = (try? await api.tareas(estado: "PENDIENTE")) ?? []
    }

    // MARK: - Pagos

    /// Pagos pendientes de verificación en recepción.
    ///
    /// El error **se propaga** (`errorPagos`) en lugar de dejar la lista vacía
    /// en silencio: un 401/403 mostraba "0 pagos" y recepción creía que no
    /// había nada por cobrar.
    func cargarPagosPendientes() async {
        errorPagos = nil

        do {
            pagosPendientes = try await api.pagosPendientes()
        } catch let apiError as APIError {
            pagosPendientes = []
            errorPagos = apiError.mensajeUsuario
        } catch {
            pagosPendientes = []
            errorPagos = "No se pudieron cargar los pagos pendientes."
        }
    }

    func aprobarPago(id: Int, codigoOperacion: String?) async throws {
        _ = try await api.aprobarPago(id: id, codigoOperacion: codigoOperacion)
        await cargarPagosPendientes()
    }

    func rechazarPago(id: Int, motivo: String) async throws {
        _ = try await api.rechazarPago(id: id, motivo: motivo)
        await cargarPagosPendientes()
    }

    // MARK: - Limpieza

    /// Vacía todo el estado compartido. Se llama al cerrar sesión.
    func limpiar() {
        dashboard = nil
        llegadas = []
        salidas = []
        habitaciones = nil
        pagosPendientes = []
        tareasPendientes = []
        error = nil
        errorPagos = nil
        cargando = false
    }
}
