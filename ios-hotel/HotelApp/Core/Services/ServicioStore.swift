import Foundation
import Observation

/// Grupo de productos de una categoría del catálogo.
struct GrupoCatalogo: Identifiable {
    let categoria: String
    let productos: [Producto]

    var id: String { categoria }
}

/// Estancia del cliente en curso (check-in hecho).
///
/// Se resuelve con `/reservas/mias` (`estado == EN_CURSO`) y no con
/// `/estadias/activas`, porque ese endpoint exige rol operativo y un cliente
/// recibiría 403.
struct EstadiaCliente: Equatable, Sendable {
    let reservaId: Int
    let reservaCodigo: String
    let habitacionId: Int?
    let habitacionNumero: String?
}

/// Estado del servicio a la habitación.
///
/// Compartido entre la vista del cliente (pedir) y la de recepción (gestionar).
@MainActor
@Observable
final class ServicioStore {

    // Catalogo
    private(set) var productos: [Producto] = []
    private(set) var cargandoCatalogo = false

    // Cliente
    private(set) var misSolicitudes: [SolicitudConsumo] = []

    // Recepcion
    private(set) var pendientes: [SolicitudConsumo] = []

    private(set) var procesando = false
    private(set) var error: String?

    /// El cliente no tiene reserva en curso (sin check-in): el servicio a la
    /// habitación no aplica. Se muestra como aviso informativo, no como error.
    private(set) var sinEstadiaActiva = false

    /// Consultando si hay check-in. Evita mostrar el catálogo antes de saber
    /// si el cliente está alojado.
    private(set) var comprobandoEstadia = true

    /// Reserva en curso del cliente. `nil` mientras no se ha consultado o si
    /// no hay check-in hecho.
    private(set) var estadia: EstadiaCliente?

    private let api = HotelAPI.shared

    /// Hay check-in activo: se puede pedir servicio a la habitación.
    var puedePedir: Bool { estadia != nil }

    // MARK: - Catalogo

    func cargarCatalogo(forzar: Bool = false) async {
        if !forzar && !productos.isEmpty { return }

        cargandoCatalogo = true
        defer { cargandoCatalogo = false }

        do {
            productos = try await api.productos()
            self.error = nil
        } catch let apiError as APIError {
            self.error = apiError.mensajeUsuario
        } catch {
            self.error = "No se pudo cargar el catalogo."
        }
    }

    /// Productos agrupados por categoría, en el orden de presentación.
    var catalogoPorCategoria: [GrupoCatalogo] {
        let orden = ["BEBIDA", "COMIDA", "SNACK", "HIGIENE", "OTRO"]
        return orden.compactMap { categoria in
            let items = productos.filter { $0.categoria == categoria }
            return items.isEmpty ? nil : GrupoCatalogo(categoria: categoria, productos: items)
        }
    }

    // MARK: - Cliente

    /// Detecta si el cliente está hospedado (reserva EN_CURSO = check-in hecho).
    ///
    /// Si hay reserva en curso se carga su detalle para conocer la habitación
    /// asignada; el pedido no necesita enviarla, el backend la deduce del JWT.
    func cargarEstadiaActiva() async {
        comprobandoEstadia = true
        defer { comprobandoEstadia = false }

        do {
            let reservasCliente = try await api.misReservas()

            guard let activa = reservasCliente.first(where: { $0.estado == "EN_CURSO" })
            else {
                estadia = nil
                sinEstadiaActiva = true
                return
            }

            var habitacionId: Int?
            var habitacionNumero: String?

            if let detalle = try? await api.reserva(id: activa.id),
               let linea = detalle.lineas.first(where: { $0.habitacionNumero != nil })
                ?? detalle.lineas.first {
                habitacionId = linea.habitacionId
                habitacionNumero = linea.habitacionNumero
            }

            estadia = EstadiaCliente(reservaId: activa.id,
                                     reservaCodigo: activa.codigo,
                                     habitacionId: habitacionId,
                                     habitacionNumero: habitacionNumero)
            sinEstadiaActiva = false
        } catch let apiError as APIError {
            // Sin red no se inventa una estancia: se muestra el aviso.
            estadia = nil
            sinEstadiaActiva = true
            // Un fallo de transporte no debe tapar el catálogo con un error rojo.
            if !apiError.esTransporte {
                error = apiError.mensajeUsuario
            }
        } catch {
            estadia = nil
            sinEstadiaActiva = true
        }
    }

    func cargarMisSolicitudes() async {
        do {
            misSolicitudes = try await api.misSolicitudes()
            self.error = nil
        } catch let apiError as APIError {
            self.error = apiError.mensajeUsuario
        } catch {
            self.error = "No se pudieron cargar tus solicitudes."
        }
    }

    /// Devuelve la solicitud creada, o nil si falló (el error queda en `error`).
    ///
    /// No se cobra aquí: el backend crea la solicitud y, cuando recepción la
    /// aprueba, genera un cargo CONSUMO en el folio que se paga en el check-out.
    func crearSolicitud(items: [ItemSolicitudRequest],
                        observaciones: String?) async -> SolicitudConsumo? {
        guard !items.isEmpty else {
            self.error = "Elige al menos un producto."
            return nil
        }

        procesando = true
        defer { procesando = false }

        do {
            let creada = try await api.crearSolicitud(items: items,
                                                      observaciones: observaciones)
            self.error = nil
            sinEstadiaActiva = false
            await cargarMisSolicitudes()
            return creada
        } catch let apiError as APIError {
            // 409 SIN_ESTADIA_ACTIVA: no es un fallo, es que no hay estancia.
            if apiError.motivo == "SIN_ESTADIA_ACTIVA" {
                sinEstadiaActiva = true
                estadia = nil
                self.error = nil
            } else {
                self.error = apiError.mensajeUsuario
            }
            return nil
        } catch {
            self.error = "No se pudo enviar la solicitud."
            return nil
        }
    }

    func cancelarSolicitud(id: Int) async -> Bool {
        procesando = true
        defer { procesando = false }

        do {
            _ = try await api.cancelarSolicitud(id: id)
            self.error = nil
            await cargarMisSolicitudes()
            return true
        } catch let apiError as APIError {
            self.error = apiError.mensajeUsuario
            return false
        } catch {
            self.error = "No se pudo anular la solicitud."
            return false
        }
    }

    // MARK: - Recepcion

    func cargarPendientes() async {
        do {
            pendientes = try await api.solicitudesPendientes()
            self.error = nil
        } catch let apiError as APIError {
            self.error = apiError.mensajeUsuario
        } catch {
            self.error = "No se pudieron cargar las solicitudes."
        }
    }

    func aprobar(id: Int, observacion: String? = nil) async -> Bool {
        procesando = true
        defer { procesando = false }

        do {
            _ = try await api.aprobarSolicitud(id: id, observacion: observacion)
            self.error = nil
            await cargarPendientes()
            return true
        } catch let apiError as APIError {
            self.error = apiError.mensajeUsuario
            return false
        } catch {
            self.error = "No se pudo aprobar la solicitud."
            return false
        }
    }

    func rechazar(id: Int, motivo: String) async -> Bool {
        procesando = true
        defer { procesando = false }

        do {
            _ = try await api.rechazarSolicitud(id: id, motivo: motivo)
            self.error = nil
            await cargarPendientes()
            return true
        } catch let apiError as APIError {
            self.error = apiError.mensajeUsuario
            return false
        } catch {
            self.error = "No se pudo rechazar la solicitud."
            return false
        }
    }

    func entregar(id: Int) async -> Bool {
        procesando = true
        defer { procesando = false }

        do {
            _ = try await api.entregarSolicitud(id: id)
            self.error = nil
            return true
        } catch let apiError as APIError {
            self.error = apiError.mensajeUsuario
            return false
        } catch {
            self.error = "No se pudo marcar la entrega."
            return false
        }
    }

    func limpiarError() {
        self.error = nil
    }

    /// Vacía el estado compartido entre cliente y recepción.
    /// Se llama al cerrar sesión para no filtrar pedidos entre cuentas.
    func limpiar() {
        productos = []
        misSolicitudes = []
        pendientes = []
        procesando = false
        cargandoCatalogo = false
        sinEstadiaActiva = false
        comprobandoEstadia = true
        estadia = nil
        error = nil
    }
}
