import CoreData
import Foundation

// ============================================================================
// Entidades Core Data para el hotel.
//
// Se modelan en código (no .xcdatamodeld) para que el proyecto compile sin
// el editor visual de Xcode.
// ============================================================================

@objc(ReservaEntity)
public final class ReservaEntity: NSManagedObject {
    @NSManaged public var id: Int64
    @NSManaged public var codigo: String
    @NSManaged public var estado: String
    @NSManaged public var huespedNombre: String
    @NSManaged public var huespedTelefono: String?
    @NSManaged public var checkIn: Date?
    @NSManaged public var checkOut: Date?
    @NSManaged public var montoTotal: NSDecimalNumber
    @NSManaged public var deposito: NSDecimalNumber?
    // NSNumber? y no Bool: al ser atributos nuevos pueden venir a nil en las
    // filas antiguas, y leer un Bool no opcional desde Core Data con nil
    // puede provocar un crash.
    @NSManaged public var depositoPagado: NSNumber?
    @NSManaged public var pagoEnRevision: NSNumber?
    @NSManaged public var detalleJson: Data?
    @NSManaged public var actualizadoEn: Date?

    /// `true` solo si el backend confirmo el deposito.
    var tieneDepositoPagado: Bool { depositoPagado?.boolValue ?? false }
    /// `true` si hay un pago esperando validacion.
    var tienePagoEnRevision: Bool { pagoEnRevision?.boolValue ?? false }

    static func upsert(id: Int, en contexto: NSManagedObjectContext) -> ReservaEntity {
        let solicitud = ReservaEntity.fetchRequest()
        solicitud.predicate = NSPredicate(format: "id == %lld", Int64(id))
        solicitud.fetchLimit = 1

        if let existente = (try? contexto.fetch(solicitud))?.first {
            return existente
        }
        let nueva = ReservaEntity(context: contexto)
        nueva.id = Int64(id)
        return nueva
    }

    func aResumen() -> ReservaResumen? {
        // Una fila sin fechas o sin importe no es un resumen válido: antes se
        // rellenaba con `Date()` y el cliente veía "hoy" como fecha de
        // entrada. Se descarta y el listado cae al backend.
        guard let entrada = checkIn, let salida = checkOut else { return nil }

        return ReservaResumen(
            id: Int(id),
            codigo: codigo,
            estado: estado,
            huespedNombre: huespedNombre,
            checkIn: FechaAPI.soloFecha(entrada),
            checkOut: FechaAPI.soloFecha(salida),
            montoTotal: montoTotal.decimalValue,
            huespedTelefono: huespedTelefono,
            depositoPagado: tieneDepositoPagado,
            pagoEnRevision: tienePagoEnRevision)
    }
}

@objc(OperacionPendienteEntity)
public final class OperacionPendienteEntity: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var tipo: String?
    @NSManaged public var payload: Data?
    @NSManaged public var creadoEn: Date?
}

// MARK: - Fetch requests

extension ReservaEntity {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<ReservaEntity> {
        NSFetchRequest<ReservaEntity>(entityName: "ReservaEntity")
    }
}

extension OperacionPendienteEntity {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<OperacionPendienteEntity> {
        NSFetchRequest<OperacionPendienteEntity>(entityName: "OperacionPendienteEntity")
    }
}

// MARK: - Modelo programático

enum ModeloProgramatico {

    static func construir() -> NSManagedObjectModel {
        let modelo = NSManagedObjectModel()

        let reserva = entidad(nombre: "ReservaEntity",
                              clase: ReservaEntity.self,
                              atributos: [
                                ("id", .integer64AttributeType, false),
                                ("codigo", .stringAttributeType, false),
                                ("estado", .stringAttributeType, false),
                                ("huespedNombre", .stringAttributeType, false),
                                ("huespedTelefono", .stringAttributeType, true),
                                ("checkIn", .dateAttributeType, true),
                                ("checkOut", .dateAttributeType, true),
                                ("montoTotal", .decimalAttributeType, false),
                                ("deposito", .decimalAttributeType, true),
                                // Opcionales a proposito: al ser atributos
                                // nuevos, la migracion ligera los infiere y
                                // las filas antiguas quedan en nil (= false
                                // al leerlos como Bool).
                                ("depositoPagado", .booleanAttributeType, true),
                                ("pagoEnRevision", .booleanAttributeType, true),
                                ("detalleJson", .binaryDataAttributeType, true),
                                ("actualizadoEn", .dateAttributeType, true)
                              ])

        let operacion = entidad(nombre: "OperacionPendienteEntity",
                                clase: OperacionPendienteEntity.self,
                                atributos: [
                                    ("id", .UUIDAttributeType, true),
                                    ("tipo", .stringAttributeType, true),
                                    ("payload", .binaryDataAttributeType, true),
                                    ("creadoEn", .dateAttributeType, true)
                                ])

        modelo.entities = [reserva, operacion]
        return modelo
    }

    private static func entidad(
        nombre: String,
        clase: AnyClass,
        atributos: [(String, NSAttributeType, Bool)]
    ) -> NSEntityDescription {
        let entidad = NSEntityDescription()
        entidad.name = nombre
        entidad.managedObjectClassName = NSStringFromClass(clase)

        entidad.properties = atributos.map { definicion in
            let atributo = NSAttributeDescription()
            atributo.name = definicion.0
            atributo.attributeType = definicion.1
            atributo.isOptional = definicion.2
            return atributo
        }
        return entidad
    }
}
