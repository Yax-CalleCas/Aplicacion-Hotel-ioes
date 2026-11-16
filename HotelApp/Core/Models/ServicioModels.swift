import Foundation

// ============================================================================
// Contratos del servicio a la habitacion y del registro walk-in.
//
// Replican 1:1 los DTOs de Spring Boot
// (ServicioHabitacionDtos y WalkInDtos).
// ============================================================================

// MARK: - Catalogo de productos

struct Producto: Decodable, Identifiable, Equatable, Sendable {
    let id: Int
    let nombre: String
    let descripcion: String?
    let categoria: String
    let precio: Decimal
    let imagenUrl: String?
    let activo: Bool

    var icono: String {
        switch categoria {
        case "BEBIDA": return "cup.and.saucer.fill"
        case "SNACK": return "takeoutbag.and.cup.and.straw.fill"
        case "HIGIENE": return "drop.fill"
        case "COMIDA": return "fork.knife"
        default: return "shippingbox.fill"
        }
    }

    var etiquetaCategoria: String {
        switch categoria {
        case "BEBIDA": return "Bebida"
        case "SNACK": return "Snack"
        case "HIGIENE": return "Higiene"
        case "COMIDA": return "Comida"
        default: return "Otro"
        }
    }
}

struct CrearProductoRequest: Encodable, Sendable {
    let nombre: String
    let descripcion: String?
    let categoria: String
    let precio: Decimal
    let imagenUrl: String?
}

struct ActualizarProductoRequest: Encodable, Sendable {
    let nombre: String
    let descripcion: String?
    let categoria: String
    let precio: Decimal
    let imagenUrl: String?
    let activo: Bool
}

// MARK: - Solicitudes

struct ItemSolicitudRequest: Encodable, Sendable {
    let productoId: Int
    let cantidad: Int
}

struct CrearSolicitudRequest: Encodable, Sendable {
    let items: [ItemSolicitudRequest]
    let observaciones: String?
}

struct ItemSolicitud: Decodable, Identifiable, Sendable {
    let id: Int
    let productoId: Int
    let productoNombre: String
    let cantidad: Int
    let precioUnitario: Decimal
    let subtotal: Decimal
}

struct SolicitudConsumo: Decodable, Identifiable, Sendable {
    let id: Int
    let codigo: String
    let estado: String
    let estadiaId: Int?
    let habitacionId: Int?
    let habitacionNumero: String?
    let huespedId: Int?
    let huespedNombre: String?
    let total: Decimal
    let totalUnidades: Int
    let observaciones: String?
    let motivoRechazo: String?
    let cargoId: Int?
    let creadoEn: String?
    let gestionadoEn: String?
    let items: [ItemSolicitud]

    var estaPendiente: Bool { estado == "PENDIENTE" }
    var estaAprobada: Bool { estado == "APROBADA" }
    var estaEntregada: Bool { estado == "ENTREGADA" }
    var estaRechazada: Bool { estado == "RECHAZADA" }
    var estaCancelada: Bool { estado == "CANCELADA" }

    /// El cliente solo puede anular mientras recepcion no la haya tocado.
    var sePuedeCancelar: Bool { estaPendiente }

    var resumenItems: String {
        items.map { "\($0.cantidad)× \($0.productoNombre)" }
            .joined(separator: ", ")
    }
}

struct AprobarSolicitudRequest: Encodable, Sendable {
    let observacion: String?
}

struct RechazarSolicitudRequest: Encodable, Sendable {
    let motivo: String
}

// MARK: - Registro walk-in (recepcion)

/// Alta de cliente en mostrador: reserva + credenciales si es nuevo.
struct WalkInRequest: Encodable, Sendable {
    let tipoDocumento: String
    let numeroDocumento: String
    let nombres: String
    let apellidos: String
    let email: String?
    let telefono: String?
    let sedeId: Int
    let categoriaId: Int
    let habitacionId: Int?
    let checkIn: String
    let checkOut: String
    let adultos: Int
    let ninos: Int?
    let observaciones: String?
}

struct WalkInResponse: Decodable, Sendable {
    let reservaId: Int
    let reservaCodigo: String
    let estadoReserva: String
    let canal: String
    let huespedId: Int
    let huespedNombre: String
    let usuarioId: Int?
    let email: String?
    let passwordTemporal: String?
    let cuentaCreada: Bool
    let sedeId: Int
    let sedeNombre: String
    let categoriaNombre: String?
    let habitacionNumero: String?
    let checkIn: String
    let checkOut: String
    let noches: Int
    let montoTotal: Decimal
    let depositoRequerido: Decimal
}

/// Respuesta de la comprobacion previa por documento.
struct BusquedaHuespedResponse: Decodable, Sendable {
    let existe: Bool
    let huesped: Huesped?
}
