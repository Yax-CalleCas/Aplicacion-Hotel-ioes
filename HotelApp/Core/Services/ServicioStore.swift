import Foundation
import Observation

/// Grupo de productos de una categoría del catálogo.
struct GrupoCatalogo: Identifiable {
    let categoria: String
    let productos: [Producto]

    var id: String { categoria }
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

    /// El cliente no tiene check-in activo: el servicio a la habitación no
    /// aplica. Se muestra como aviso informativo, no como error.
    private(set) var sinEstadiaActiva = false

    private let api = HotelAPI.shared

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

    /// Devuelve la solicitud creada, o nil si falló (el error queda en `error`.
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
        error = nil
    }
}
