import Foundation
import Observation

/// Reservas del usuario.
///
/// Guarda las reservas en Core Data para que el cliente las consulte sin red.
/// La fuente de verdad siempre es el backend: el cache es solo de lectura.
@MainActor
@Observable
final class ReservaStore {

    private(set) var reservas: [ReservaResumen] = []
    private(set) var cargando = false
    /// `true` cuando la lista mostrada viene del cache por falta de red.
    private(set) var desdeCache = false
    private(set) var error: String?

    private let api: HotelAPI
    private let persistencia: PersistenciaController

    /// `persistencia` es inyectable para previews y tests
    /// (`PersistenciaController.enMemoria()`), sin tocar la tienda real.
    init(api: HotelAPI = .shared,
         persistencia: PersistenciaController = .shared) {
        self.api = api
        self.persistencia = persistencia
        self.reservas = persistencia.reservasGuardadas()
    }

    // MARK: - Listado

    /// Descarga las reservas del cliente. Si falla, cae al cache local.
    func cargar() async {
        cargando = true
        defer { cargando = false }
        error = nil

        do {
            let remotas = try await api.misReservas()
            reservas = remotas
            desdeCache = false
            try? persistencia.guardarReservas(remotas)
        } catch let apiError as APIError {
            reservas = persistencia.reservasGuardadas()
            desdeCache = !reservas.isEmpty
            error = apiError.esTransporte
                ? "Sin conexión. Mostrando reservas guardadas."
                : apiError.mensajeUsuario
        } catch {
            reservas = persistencia.reservasGuardadas()
            desdeCache = !reservas.isEmpty
            self.error = "No se pudieron cargar las reservas."
        }
    }

    // MARK: - Detalle

    /// Obtiene el detalle. Si no hay red devuelve la copia local.
    func obtener(id: Int) async -> Reserva? {
        if let remota = try? await api.reserva(id: id) {
            try? persistencia.guardarReservaDetalle(remota)
            return remota
        }
        return persistencia.reservaGuardada(id: id)
    }

    /// Detalle por código de reserva (pantalla "buscar por código").
    func obtener(codigo: String) async throws -> Reserva {
        let reserva = try await api.reserva(codigo: codigo)
        try? persistencia.guardarReservaDetalle(reserva)
        return reserva
    }

    // MARK: - Crear

    /// Crea la reserva. El backend calcula precios y depósito: no se envían.
    func crear(sedeId: Int, categoriaId: Int, checkIn: String, checkOut: String,
               adultos: Int, ninos: Int,
               observaciones: String? = nil) async throws -> Reserva {
        let request = CrearReservaRequest(
            sedeId: sedeId,
            huespedId: nil,
            huespedNuevo: nil,
            lineas: [LineaReservaRequest(
                categoriaId: categoriaId,
                habitacionId: nil,
                checkIn: checkIn,
                checkOut: checkOut,
                adultos: adultos,
                ninos: ninos)],
            observaciones: observaciones,
            canal: "APP")

        let reserva = try await api.crearReserva(request)
        try? persistencia.guardarReservaDetalle(reserva)

        // Aviso local si el depósito no se paga a tiempo.
        if let expira = FechaAPI.parsear(reserva.expiraEn) {
            await NotificacionService.programarAvisoExpiracion(
                codigo: reserva.codigo, expiraEn: expira)
        }

        await cargar()
        return reserva
    }

    // MARK: - Cancelar

    func cancelar(id: Int, motivo: String?) async throws -> Reserva {
        let reserva = try await api.cancelarReserva(id: id, motivo: motivo)
        try? persistencia.guardarReservaDetalle(reserva)
        NotificacionService.cancelarAvisoExpiracion()
        await NotificacionService.notificarEstado(reservaId: reserva.id,
                                                  estado: reserva.estado)
        await cargar()
        return reserva
    }

    // MARK: - Pagar

    /// Registra el depósito (50 %).
    ///
    /// La `idempotencyKey` incluye el número de intento, calculado a partir de
    /// los pagos ya registrados en el servidor: un doble toque no crea dos
    /// cobros, pero tras un rechazo (o al reabrir la app) el cliente sí puede
    /// reintentar. Con una clave fija el backend devolvía el pago RECHAZADO
    /// anterior y la app mostraba "registrado" sin que ocurriera nada.
    /// El pago queda en `PENDIENTE` hasta que recepción lo apruebe.
    func pagarDeposito(reserva: Reserva, metodo: String) async throws -> Pago {
        let intento = await intentoDePago(reservaId: reserva.id, tipo: "DEPOSITO")

        let pago = try await api.registrarPago(
            reservaId: reserva.id,
            request: CrearPagoRequest(
                tipo: "DEPOSITO",
                metodo: metodo,
                monto: reserva.depositoRequerido,
                idempotencyKey: "ios-dep-\(reserva.id)-\(intento)",
                codigoOperacion: nil))

        await cargar()
        return pago
    }

    /// Paga el saldo restante (recepción, en efectivo/tarjeta).
    ///
    /// El monto es el saldo pendiente exacto que calcula el backend; si hay
    /// pagos en revisión se descuentan para no cobrar dos veces.
    func pagarSaldo(reserva: Reserva, folio: Folio, metodo: String = "EFECTIVO") async throws -> Pago {
        let intento = await intentoDePago(reservaId: reserva.id, tipo: "SALDO")

        let pago = try await api.registrarPago(
            reservaId: reserva.id,
            request: CrearPagoRequest(
                tipo: "SALDO",
                metodo: metodo,
                monto: folio.saldo,
                idempotencyKey: "ios-saldo-\(reserva.id)-\(intento)",
                codigoOperacion: nil))

        await cargar()
        return pago
    }

    /// Siguiente número de intento para un tipo de pago, leído del servidor.
    private func intentoDePago(reservaId: Int, tipo: String) async -> Int {
        let existentes = (try? await api.folio(reservaId: reservaId))?
            .pagos
            .filter { $0.tipo == tipo }
            .count ?? 0
        return existentes + 1
    }

    // MARK: - Limpieza local

    /// Vacía el listado en memoria.
    ///
    /// **No** borra Core Data: el cache offline se conserva mientras la sesión
    /// siga siendo del mismo usuario. La purga real la hace
    /// `SesionStore.cerrarSesionLocal()`.
    func limpiar() {
        reservas = []
        desdeCache = false
        error = nil
        cargando = false
    }
}
