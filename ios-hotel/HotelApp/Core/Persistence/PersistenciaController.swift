import CoreData
import Foundation

/// Persistencia local con Core Data.
///
/// Se cachean las reservas del cliente para consulta offline. El detalle
/// completo se guarda como JSON en un atributo binario para no necesitar
/// 20 entidades distintas: el backend ya validó el contenido.
final class PersistenciaController {

    static let shared = PersistenciaController()

    /// Instancia en memoria para **previews y tests**.
    ///
    /// Con el `init` privado no había forma de crear un contenedor aislado:
    /// los previews escribían en la tienda real del simulador y los tests
    /// compartían estado. `NSInMemoryStoreType` no toca el disco.
    static func enMemoria() -> PersistenciaController {
        PersistenciaController(inMemory: true)
    }

    let container: NSPersistentContainer

    private init(inMemory: Bool = false) {
        container = NSPersistentContainer(
            name: "HotelModel",
            managedObjectModel: ModeloProgramatico.construir())

        if inMemory {
            let descripcion = NSPersistentStoreDescription()
            descripcion.type = NSInMemoryStoreType
            container.persistentStoreDescriptions = [descripcion]
        }

        // El modelo se define en codigo: al anadir atributos (por ejemplo
        // depositoPagado / pagoEnRevision) la tienda existente del usuario
        // debe migrar sola. Sin esto, loadPersistentStores falla y la app
        // muere en el arranque para quien ya la tenia instalada.
        for descripcion in container.persistentStoreDescriptions {
            descripcion.shouldMigrateStoreAutomatically = true
            descripcion.shouldInferMappingModelAutomatically = true
        }

        container.loadPersistentStores { [coordinador = container.persistentStoreCoordinator] _, error in
            if let error = error as NSError? {
                NSLog("Core Data no cargo (%@). Se recrea la cache local.", error)
                // En memoria (previews/tests) no hay archivo que recrear: si
                // falla, añadir un store SQLite rompería el aislamiento.
                if !inMemory {
                    try? PersistenciaController.recrearTienda(coordinador)
                }
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    func nuevoContexto() -> NSManagedObjectContext {
        let contexto = container.newBackgroundContext()
        contexto.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return contexto
    }

    /// Recrea la tienda local cuando el modelo no puede migrar.
    /// Solo se pierde la cache de reservas: el backend es la fuente de verdad.
    private static func recrearTienda(_ coordinador: NSPersistentStoreCoordinator) throws {
        for tienda in coordinador.persistentStores {
            if let url = tienda.url {
                try? FileManager.default.removeItem(at: url)
            }
            try coordinador.remove(tienda)
        }

        // SQLite exige una URL concreta: `nil` solo es valido en memoria.
        let url = NSPersistentContainer.defaultDirectoryURL()
            .appendingPathComponent("HotelModel.sqlite")

        try coordinador.addPersistentStore(
            ofType: NSSQLiteStoreType, configurationName: nil, at: url)
    }

    func guardarContexto(_ contexto: NSManagedObjectContext) throws {
        guard contexto.hasChanges else { return }
        try contexto.save()
    }

    // MARK: - Reservas

    /// Guarda (upsert) los resúmenes y **elimina las filas huérfanas**.
    ///
    /// Sin el borrado, una reserva cancelada y luego eliminada del listado del
    /// backend seguía apareciendo en el cache offline para siempre. El cache
    /// debe reflejar exactamente lo que devolvió `GET /reservas/mias`.
    func guardarReservas(_ resumenes: [ReservaResumen]) throws {
        let contexto = container.viewContext
        let idsVigentes = Set(resumenes.map { Int64($0.id) })

        for r in resumenes {
            let entidad = ReservaEntity.upsert(id: r.id, en: contexto)
            entidad.codigo = r.codigo
            entidad.estado = r.estado
            entidad.huespedNombre = r.huespedNombre
            entidad.huespedTelefono = r.huespedTelefono
            entidad.checkIn = FechaAPI.parsear(r.checkIn)
            entidad.checkOut = FechaAPI.parsear(r.checkOut)
            entidad.montoTotal = NSDecimalNumber(decimal: r.montoTotal)
            entidad.depositoPagado = NSNumber(value: r.depositoPagado)
            entidad.pagoEnRevision = NSNumber(value: r.pagoEnRevision)
            entidad.actualizadoEn = Date()
        }

        // Huérfanas: filas cacheadas cuyo id ya no está en la respuesta.
        let solicitud = ReservaEntity.fetchRequest()
        if let todas = try? contexto.fetch(solicitud) {
            for entidad in todas where !idsVigentes.contains(entidad.id) {
                contexto.delete(entidad)
            }
        }

        try guardarContexto(contexto)
    }

    /// Guarda el detalle serializado como JSON.
    func guardarReservaDetalle(_ reserva: Reserva) throws {
        let contexto = container.viewContext
        let entidad = ReservaEntity.upsert(id: reserva.id, en: contexto)

        entidad.codigo = reserva.codigo
        entidad.estado = reserva.estado
        entidad.huespedNombre = reserva.huespedTitular.nombreCompleto
        entidad.huespedTelefono = reserva.huespedTitular.telefono
        entidad.checkIn = FechaAPI.parsear(reserva.checkIn)
        entidad.checkOut = FechaAPI.parsear(reserva.checkOut)
        entidad.montoTotal = NSDecimalNumber(decimal: reserva.montoTotal)
        entidad.deposito = NSDecimalNumber(decimal: reserva.depositoRequerido)
        entidad.actualizadoEn = Date()

        if let data = try? JSONEncoder().encode(reserva) {
            entidad.detalleJson = data
        }

        try guardarContexto(contexto)
    }

    func reservasGuardadas() -> [ReservaResumen] {
        let contexto = container.viewContext
        let solicitud = ReservaEntity.fetchRequest()
        solicitud.sortDescriptors = [NSSortDescriptor(key: "id", ascending: false)]

        do {
            return try contexto.fetch(solicitud).compactMap { $0.aResumen() }
        } catch {
            return []
        }
    }

    func reservaGuardada(id: Int) -> Reserva? {
        let contexto = container.viewContext
        let solicitud = ReservaEntity.fetchRequest()
        solicitud.predicate = NSPredicate(format: "id == %lld", Int64(id))
        solicitud.fetchLimit = 1

        guard let entidad = (try? contexto.fetch(solicitud))?.first,
              let data = entidad.detalleJson else { return nil }

        return try? JSONDecoder().decode(Reserva.self, from: data)
    }

    // MARK: - Limpieza

    func limpiarTodo() {
        let contexto = container.viewContext
        for nombre in ["ReservaEntity", "OperacionPendienteEntity"] {
            let solicitud = NSFetchRequest<NSFetchRequestResult>(entityName: nombre)
            let borrar = NSBatchDeleteRequest(fetchRequest: solicitud)
            _ = try? contexto.execute(borrar)
        }
        contexto.reset()
    }
}

// MARK: - Fechas

/// Conversión y formato de fechas de la API.
///
/// El backend envía `LocalDate` como `"2027-06-10"` (sin hora ni zona) y
/// `OffsetDateTime` como ISO con offset. Una fecha sin hora **no** debe
/// interpretarse en UTC: eso la mostraría un día antes en Perú (UTC-5).
enum FechaAPI {

    /// Zona del hotel. Todas las fechas de negocio son locales a esta zona.
    private static let zonaHotel = TimeZone(identifier: "America/Lima") ?? .current

    /// Parser de fecha sin hora (`yyyy-MM-dd`), anclado a la zona del hotel.
    private static let parserSoloFecha: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = zonaHotel
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Parser ISO8601 con y sin fracciones de segundo.
    private static let parserISO: ISO8601DateFormatter = {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso
    }()

    private static let parserISOsinFracciones: ISO8601DateFormatter = {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        return iso
    }()

    static func parsear(_ valor: String?) -> Date? {
        guard let valor, !valor.isEmpty else { return nil }

        // 1) Texto con hora y offset (creadoEn, expiraEn, checkInReal...).
        if valor.contains("T") {
            if let fecha = parserISO.date(from: valor) { return fecha }
            if let fecha = parserISOsinFracciones.date(from: valor) { return fecha }
        }

        // 2) LocalDate puro: se ancla a la zona del hotel, no a UTC.
        if let fecha = parserSoloFecha.date(from: valor) { return fecha }

        // 3) Último intento tolerante (por si llega otro formato).
        return parserISOsinFracciones.date(from: valor)
    }

    static func formatear(_ fecha: Date?) -> String {
        guard let fecha else { return "—" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_PE")
        f.timeZone = zonaHotel
        f.dateFormat = "dd MMM yyyy"
        return f.string(from: fecha)
    }

    static func formatearConHora(_ fecha: Date?) -> String {
        guard let fecha else { return "—" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_PE")
        f.timeZone = zonaHotel
        f.dateFormat = "dd MMM yyyy, HH:mm"
        return f.string(from: fecha)
    }

    /// Texto `yyyy-MM-dd` para enviar al backend (siempre en zona del hotel).
    static func soloFecha(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = zonaHotel
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// Fecha de hoy a medianoche local (para comparar sin horas).
    static func hoy() -> Date {
        Calendar.current.startOfDay(for: Date())
    }

    /// Noches entre dos fechas (mínimo 1).
    static func noches(desde: Date, hasta: Date) -> Int {
        max(1, Calendar.current.dateComponents([.day], from: desde, to: hasta).day ?? 1)
    }
}

