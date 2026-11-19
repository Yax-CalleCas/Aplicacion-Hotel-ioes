import Foundation
import Observation

/// Sede activa compartida por toda la app (panel, habitaciones, estructura).
///
/// Antes cada pantalla guardaba su propia sede: cambiabas a Piura en el panel
/// y Habitaciones seguía mostrando Lima. Con un único origen de verdad, el
/// cambio se propaga a todas las pestañas.
///
/// No se persiste en disco: al cerrar sesión se limpia (`limpiar()`), para que
/// el siguiente usuario no herede la sede de otra persona.
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
