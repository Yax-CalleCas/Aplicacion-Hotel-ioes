import Foundation
import Observation

/// Catálogo de sedes, categorías y disponibilidad.
///
/// Estrategia: la búsqueda es online; las reservas del cliente se cachean en
/// Core Data para consulta offline.
///
/// La sede seleccionada se conserva en el store (no en la vista) para que
/// todas las pantallas respeten la misma elección.
@MainActor
@Observable
final class CatalogoStore {

    private(set) var sedes: [Sede] = []
    /// Catálogo completo de la sede seleccionada (para mostrar sin buscar fechas).
    private(set) var categorias: [CategoriaHabitacion] = []
    /// Resultado de la última búsqueda por fechas.
    private(set) var resultados: [Disponibilidad] = []
    private(set) var cargando = false
    private(set) var buscando = false
    private(set) var error: String?

    /// Sede activa. Si es nil se usa la primera disponible.
    private(set) var sedeId: Int?

    private let api = HotelAPI.shared

    var sedeSeleccionada: Sede? {
        guard let sedeId else { return sedes.first }
        return sedes.first { $0.id == sedeId } ?? sedes.first
    }

    // MARK: - Carga inicial

    /// Carga las sedes y deja seleccionada la primera (o la que ya estaba).
    func cargarSedes() async {
        cargando = true
        defer { cargando = false }

        do {
            sedes = try await api.sedes()
            error = nil

            if sedeId == nil || !sedes.contains(where: { $0.id == sedeId }) {
                sedeId = sedes.first?.id
            }

            if let sedeId {
                await cargarCategorias(sedeId: sedeId)
            }
        } catch let error as APIError {
            self.error = error.mensajeUsuario
        } catch {
            self.error = "No se pudieron cargar las sedes."
        }
    }

    // MARK: - Selección de sede

    /// Cambia la sede activa y refresca el catálogo visible.
    func seleccionar(sedeId nuevoId: Int) async {
        guard nuevoId != sedeId else { return }
        sedeId = nuevoId
        resultados = []
        error = nil
        await cargarCategorias(sedeId: nuevoId)
    }

    // MARK: - Catálogo

    func cargarCategorias(sedeId: Int) async {
        do {
            categorias = try await api.categorias(sedeId: sedeId)
        } catch {
            // No se pisa el error de búsqueda: el catálogo es informativo.
            categorias = []
        }
    }

    // MARK: - Búsqueda

    /// Consulta disponibilidad real por fechas.
    func buscar(sedeId: Int, checkIn: String, checkOut: String) async {
        buscando = true
        error = nil
        defer { buscando = false }

        do {
            resultados = try await api.disponibilidad(
                sedeId: sedeId, checkIn: checkIn, checkOut: checkOut)
        } catch let apiError as APIError {
            error = apiError.mensajeUsuario
            resultados = []
        } catch {
            self.error = "No se pudo consultar la disponibilidad."
            resultados = []
        }
    }

    /// Limpia el resultado para volver a ver el catálogo completo.
    func limpiarBusqueda() {
        resultados = []
        error = nil
    }

    /// Vacía el catálogo cacheado y la sede elegida.
    /// Se llama al cerrar sesión: la sede de una cuenta no debe arrastrarse
    /// a otra (un recepcionista de Piura no debe abrir en Lima).
    func limpiar() {
        sedes = []
        categorias = []
        resultados = []
        sedeId = nil
        cargando = false
        buscando = false
        error = nil
    }

    // MARK: - Utilidades de presentación

    /// Foto de la sede con respaldo local por ciudad (igual que la web).
    func fotoSede(_ sede: Sede) -> String? {
        if let url = sede.imagenUrl, !url.isEmpty { return url }

        let ciudad = (sede.ciudad ?? sede.nombre).lowercased()
        if ciudad.contains("piura") { return "/img/sedes/piura.jpg" }
        if ciudad.contains("trujillo") { return "/img/sedes/trujillo.jpg" }
        if ciudad.contains("lima") { return "/img/sedes/lima.jpg" }
        return nil
    }

    /// Foto de la categoría con respaldo local por nombre.
    func fotoCategoria(_ nombre: String, url: String?) -> String? {
        if let url, !url.isEmpty { return url }

        let n = nombre.lowercased()
        if n.contains("suite") || n.contains("presidencial") {
            return "/img/habitaciones/suite.jpg"
        }
        if n.contains("matrimonial") { return "/img/habitaciones/matrimonial.jpg" }
        if n.contains("doble") { return "/img/habitaciones/doble.jpg" }
        if n.contains("simple") || n.contains("individual") || n.contains("estandar") {
            return "/img/habitaciones/simple.jpg"
        }
        return nil
    }
}
