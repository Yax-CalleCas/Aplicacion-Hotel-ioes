import Foundation

// ============================================================================
// Contratos de la API hotelera. Replican los DTOs de Spring Boot.
//
// Reglas de este archivo:
//  - Los nombres coinciden 1:1 con el backend (no se usa convertFromSnakeCase).
//  - Los campos anulables del backend son `Optional`.
//  - Los importes son `Decimal` para no perder centavos.
//  - Las fechas llegan como texto ISO (`2027-06-10` o con hora); se formatean
//    con `FechaAPI`, nunca con `DateFormatter` suelto.
// ============================================================================

// MARK: - Autenticación

struct LoginRequest: Encodable, Sendable {
    let email: String
    let password: String
}

struct RegisterRequest: Encodable, Sendable {
    let nombre: String
    let email: String
    let password: String
    let telefono: String?
}

struct AuthResponse: Decodable, Sendable {
    let accessToken: String
    let tokenType: String
    let usuario: Usuario
}

struct CambiarPasswordRequest: Encodable, Sendable {
    let passwordActual: String
    let passwordNueva: String
}

/// Login social (mock OAuth). El token simula lo que devuelve el SDK.
struct SocialLoginRequest: Encodable, Sendable {
    let proveedor: String
    let token: String
    let email: String
    let nombre: String?
    let apellido: String?
    let emailVerificado: Bool
}

/// Cuenta ofrecida en el selector del proveedor social (mock).
struct CuentaSocial: Identifiable, Sendable {
    let id = UUID()
    let nombre: String
    let apellido: String
    let email: String
    let iniciales: String
    let avatarColor: (Double, Double, Double)

    static let demo: [CuentaSocial] = [
        CuentaSocial(nombre: "Carlos", apellido: "Mendoza Rios",
                     email: "carlos.mendoza@example.com",
                     iniciales: "CM", avatarColor: (0.11, 0.36, 0.60)),
        CuentaSocial(nombre: "Ana", apellido: "Torres Vega",
                     email: "ana.torres@example.com",
                     iniciales: "AT", avatarColor: (0.02, 0.47, 0.34)),
        CuentaSocial(nombre: "Cliente", apellido: "Demo",
                     email: "cliente@hotel.com",
                     iniciales: "CD", avatarColor: (0.78, 0.45, 0.03)),
    ]
}

struct Usuario: Decodable, Identifiable, Equatable, Sendable {
    let id: Int
    let nombre: String
    let email: String
    let telefono: String?
    let fotoUrl: String?
    let activo: Bool
    let motivoDesactivacion: String?
    /// LOCAL si la cuenta tiene contraseña, FACEBOOK/APPLE si es social.
    let proveedor: String?
    let ultimoLogin: String?
    let roles: [Rol]
    let sedes: [Sede]
    let permisos: [String]

    var nombresRol: [String] { roles.map { $0.nombre.uppercased() } }

    var esAdmin: Bool { nombresRol.contains("ADMIN") }
    var esGerente: Bool { nombresRol.contains("GERENTE") }
    var esRecepcionista: Bool { nombresRol.contains("RECEPCIONISTA") }
    var esHousekeeping: Bool { nombresRol.contains("HOUSEKEEPING") }

    /// Cliente puro: no tiene roles operativos.
    var esCliente: Bool {
        nombresRol.contains("CLIENTE") && !esAdmin && !esRecepcionista && !esGerente
    }

    /// Admin, gerente o recepcionista pueden operar el panel.
    var puedeOperar: Bool { esAdmin || esGerente || esRecepcionista }

    /// Puede ver reportes (admin y gerente).
    var puedeVerReportes: Bool { esAdmin || esGerente }

    var sedePrincipal: Sede? { sedes.first }

    var iniciales: String {
        nombre.split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
            .uppercased()
    }

    func tienePermiso(_ codigo: String) -> Bool { permisos.contains(codigo) }
}

struct Rol: Decodable, Identifiable, Equatable, Sendable {
    let id: Int
    let nombre: String
    let descripcion: String?
    let esSistema: Bool
    let activo: Bool
    let permisos: [String]
}

struct Sede: Decodable, Identifiable, Equatable, Sendable {
    let id: Int
    let nombre: String
    let codigo: String
    let direccion: String?
    let ciudad: String?
    let pais: String
    let telefono: String?
    let email: String?
    let zonaHoraria: String
    let horaCheckIn: String
    let horaCheckOut: String
    let activo: Bool
    let imagenUrl: String?

    /// Hora "15:00:00" → "15:00".
    var checkInCorto: String { String(horaCheckIn.prefix(5)) }
    var checkOutCorto: String { String(horaCheckOut.prefix(5)) }
}

struct CrearSedeRequest: Encodable, Sendable {
    let nombre: String
    let codigo: String
    let direccion: String?
    let ciudad: String?
    let telefono: String?
    let email: String?
    let horaCheckIn: String?
    let horaCheckOut: String?
    let imagenUrl: String?
}

// MARK: - Inventario

struct CategoriaHabitacion: Decodable, Identifiable, Equatable, Sendable {
    let id: Int
    let sedeId: Int
    let nombre: String
    let descripcion: String?
    let capacidadAdultos: Int
    let capacidadNinos: Int
    let camas: Int
    let metrosCuadrados: Double?
    let activo: Bool
    let precioBase: Decimal?
    let imagenUrl: String?

    var icono: String {
        let n = nombre.lowercased()
        if n.contains("suite") { return "crown.fill" }
        if n.contains("matrimonial") || n.contains("doble") { return "bed.double.fill" }
        return "bed.double"
    }
}

struct CrearCategoriaRequest: Encodable, Sendable {
    let sedeId: Int
    let nombre: String
    let descripcion: String?
    let capacidadAdultos: Int
    let capacidadNinos: Int
    let camas: Int
    let metrosCuadrados: Double?
    let imagenUrl: String?
}

struct Habitacion: Decodable, Identifiable, Equatable, Sendable {
    let id: Int
    let sedeId: Int
    let sedeNombre: String
    let pisoId: Int
    let pisoNumero: Int
    let categoriaId: Int
    let categoriaNombre: String
    let numero: String
    let estado: String
    let motivoBloqueo: String?
    let activo: Bool
    let capacidadAdultos: Int
    let capacidadNinos: Int

    var estaDisponible: Bool { estado == "DISPONIBLE" }
    var estaOcupada: Bool { estado == "OCUPADA" }
    var enLimpieza: Bool { estado == "LIMPIEZA" }
    var tieneBloqueo: Bool { estado == "MANTENIMIENTO" || estado == "FUERA_SERVICIO" }
}

struct CrearHabitacionRequest: Encodable, Sendable {
    let sedeId: Int
    let pisoId: Int
    let categoriaId: Int
    let numero: String
}

struct ActualizarHabitacionRequest: Encodable, Sendable {
    let pisoId: Int
    let categoriaId: Int
    let numero: String
    let activo: Bool
}

struct CambiarEstadoHabitacionRequest: Encodable, Sendable {
    let estado: String
    let motivo: String?
}

struct HabitacionEstadoLog: Decodable, Identifiable, Sendable {
    let id: Int
    let estadoAnterior: String?
    let estadoNuevo: String
    let motivo: String?
    let actorId: Int?
    let actorRol: String?
    let creadoEn: String
}

struct ResumenEstados: Decodable, Sendable {
    let total: Int
    let disponibles: Int
    let ocupadas: Int
    let limpieza: Int
    let mantenimiento: Int
    let fueraServicio: Int
}

struct ListaHabitaciones: Decodable, Sendable {
    let habitaciones: [Habitacion]
    let resumen: ResumenEstados
}

struct Disponibilidad: Decodable, Identifiable, Sendable {
    let categoriaId: Int
    let categoriaNombre: String
    let descripcion: String?
    let imagenUrl: String?
    let precioDesde: Decimal
    let habitacionesDisponibles: Int
    let capacidadAdultos: Int
    let capacidadNinos: Int
    let camas: Int
    let metrosCuadrados: Double?

    var id: Int { categoriaId }
}

struct Piso: Decodable, Identifiable, Sendable {
    let id: Int
    let sedeId: Int
    let numero: Int
    let nombre: String?
    let activo: Bool
}

struct CrearPisoRequest: Encodable, Sendable {
    let sedeId: Int
    let numero: Int
    let nombre: String?
}

struct Temporada: Decodable, Identifiable, Sendable {
    let id: Int
    let sedeId: Int
    let nombre: String
    let fechaInicio: String
    let fechaFin: String
    let prioridad: Int
    let activo: Bool
}

struct Tarifa: Decodable, Identifiable, Sendable {
    let id: Int
    let categoriaId: Int
    let categoriaNombre: String
    let temporadaId: Int
    let temporadaNombre: String
    let precioNoche: Decimal
    let moneda: String
    let minimoNoches: Int
    let activo: Bool
}

struct CrearTarifaRequest: Encodable, Sendable {
    let categoriaId: Int
    let temporadaId: Int
    let precioNoche: Decimal
    let minimoNoches: Int?
}

// MARK: - Reservas

struct Huesped: Codable, Identifiable, Equatable, Sendable {
    let id: Int
    let usuarioId: Int?
    let tipoDocumento: String
    let numeroDocumento: String
    let nombres: String
    let apellidos: String
    let email: String?
    let telefono: String?
    let nacionalidad: String?
    let notas: String?

    var nombreCompleto: String { "\(nombres) \(apellidos)".trimmingCharacters(in: .whitespaces) }
}

struct CrearHuespedRequest: Encodable, Sendable {
    let tipoDocumento: String
    let numeroDocumento: String
    let nombres: String
    let apellidos: String
    let email: String?
    let telefono: String?
    let nacionalidad: String?
    let notas: String?
}

struct ReservaHabitacion: Codable, Identifiable, Equatable, Sendable {
    let id: Int
    let categoriaId: Int
    let categoriaNombre: String
    let habitacionId: Int?
    let habitacionNumero: String?
    let checkIn: String
    let checkOut: String
    let precioNoche: Decimal
    let adultos: Int
    let ninos: Int
    let subtotal: Decimal
    let noches: Int
    let estado: String
}

struct Reserva: Decodable, Encodable, Identifiable, Equatable, Sendable {
    let id: Int
    let codigo: String
    let sedeId: Int
    let sedeNombre: String
    let estado: String
    let canal: String
    let checkIn: String
    let checkOut: String
    let noches: Int
    let adultos: Int
    let ninos: Int
    let montoTotal: Decimal
    let depositoRequerido: Decimal
    let expiraEn: String?
    let huespedTitular: Huesped
    let lineas: [ReservaHabitacion]
    let observaciones: String?
    let folio: Folio?
    let creadoEn: String?

    var estaPendiente: Bool { estado == "PENDIENTE" }
    var estaConfirmada: Bool { estado == "CONFIRMADA" }
    var enCurso: Bool { estado == "EN_CURSO" }
    var completada: Bool { estado == "COMPLETADA" }
    var cancelada: Bool { estado == "CANCELADA" }

    /// Se puede cancelar mientras no haya empezado ni terminado.
    var sePuedeCancelar: Bool { estaPendiente || estaConfirmada }
}

struct ReservaResumen: Decodable, Identifiable, Equatable, Sendable {
    let id: Int
    let codigo: String
    let estado: String
    let huespedNombre: String
    let checkIn: String
    let checkOut: String
    let montoTotal: Decimal
    let huespedTelefono: String?
    /// El deposito del 50 % ya fue aprobado por recepcion.
    let depositoPagado: Bool
    /// Hay un pago registrado esperando validacion.
    let pagoEnRevision: Bool

    /// Se declara a mano: al implementar `init(from:)` el compilador no
    /// sintetiza este enum y el codigo no compilaria.
    private enum CodingKeys: String, CodingKey {
        case id, codigo, estado, huespedNombre, checkIn, checkOut
        case montoTotal, huespedTelefono, depositoPagado, pagoEnRevision
    }

    /// Decodificacion tolerante: si la app apunta a un backend anterior que
    /// aun no envia estos campos, se asume "sin deposito" en lugar de fallar
    /// toda la lista de reservas.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        codigo = try c.decode(String.self, forKey: .codigo)
        estado = try c.decode(String.self, forKey: .estado)
        huespedNombre = try c.decode(String.self, forKey: .huespedNombre)
        checkIn = try c.decode(String.self, forKey: .checkIn)
        checkOut = try c.decode(String.self, forKey: .checkOut)
        montoTotal = try c.decode(Decimal.self, forKey: .montoTotal)
        huespedTelefono = try c.decodeIfPresent(String.self, forKey: .huespedTelefono)
        depositoPagado = try c.decodeIfPresent(Bool.self, forKey: .depositoPagado) ?? false
        pagoEnRevision = try c.decodeIfPresent(Bool.self, forKey: .pagoEnRevision) ?? false
    }

    init(id: Int, codigo: String, estado: String, huespedNombre: String,
         checkIn: String, checkOut: String, montoTotal: Decimal,
         huespedTelefono: String?, depositoPagado: Bool, pagoEnRevision: Bool) {
        self.id = id
        self.codigo = codigo
        self.estado = estado
        self.huespedNombre = huespedNombre
        self.checkIn = checkIn
        self.checkOut = checkOut
        self.montoTotal = montoTotal
        self.huespedTelefono = huespedTelefono
        self.depositoPagado = depositoPagado
        self.pagoEnRevision = pagoEnRevision
    }
}

struct LineaReservaRequest: Encodable, Sendable {
    let categoriaId: Int
    let habitacionId: Int?
    let checkIn: String
    let checkOut: String
    let adultos: Int
    let ninos: Int?
}

struct CrearReservaRequest: Encodable, Sendable {
    let sedeId: Int
    let huespedId: Int?
    let huespedNuevo: CrearHuespedRequest?
    let lineas: [LineaReservaRequest]
    let observaciones: String?
    let canal: String?
}

struct CancelarReservaRequest: Encodable, Sendable {
    let motivo: String
}

// MARK: - Estadia

struct Estadia: Decodable, Identifiable, Sendable {
    let id: Int
    let reservaId: Int
    let reservaCodigo: String
    let habitacionId: Int
    let habitacionNumero: String
    let checkInReal: String
    let checkOutReal: String?
    let estado: String
    let huespedes: [Huesped]

    var activa: Bool { estado == "ACTIVA" }
}

struct CheckInRequest: Encodable, Sendable {
    let lineaId: Int
    let habitacionId: Int?
    let observaciones: String?
    let acompanantes: [AcompananteRequest]?
}

struct AcompananteRequest: Encodable, Sendable {
    let huespedId: Int
    let esTitular: Bool?
}

struct CheckOutRequest: Encodable, Sendable {
    let observaciones: String?
    let cerrarFolio: Bool
}

// MARK: - Folio y pagos

struct Cargo: Codable, Identifiable, Equatable, Sendable {
    let id: Int
    let concepto: String
    let descripcion: String
    let cantidad: Decimal
    let precioUnitario: Decimal
    let monto: Decimal
    let fechaCargo: String
    let anulado: Bool
    let motivoAnulacion: String?
}

struct Pago: Codable, Identifiable, Equatable, Sendable {
    let id: Int
    let tipo: String
    let metodo: String
    let monto: Decimal
    let moneda: String
    let estado: String
    let codigoOperacion: String?
    let motivoRechazo: String?
    let creadoEn: String?
    let verificadoEn: String?

    var completo: Bool { estado == "COMPLETADO" }
    var pendiente: Bool { estado == "PENDIENTE" || estado == "EN_VERIFICACION" }
    var rechazado: Bool { estado == "RECHAZADO" }
    var reembolsado: Bool { estado == "REEMBOLSADO" }
}

struct Folio: Codable, Identifiable, Equatable, Sendable {
    let id: Int
    let reservaId: Int
    let estado: String
    let totalCargos: Decimal
    let totalPagado: Decimal
    let saldo: Decimal
    let cargos: [Cargo]
    let pagos: [Pago]

    /// Cargos exigibles (no anulados).
    var cargosActivos: [Cargo] { cargos.filter { !$0.anulado } }

    /// Pagos pendientes de verificación por recepción.
    var pagosEnVerificacion: [Pago] { pagos.filter { $0.pendiente } }

    // --- Desglose para el check-out -------------------------------------
    //
    // El backend crea un cargo ALOJAMIENTO por la estadía y un cargo CONSUMO
    // por cada pedido de servicio a la habitación aprobado. El check-out se
    // liquida con el total de ambos, así que la UI los muestra separados.

    /// Cargos de hospedaje (noches).
    var cargosHospedaje: [Cargo] {
        cargosActivos.filter { $0.concepto.uppercased() == "ALOJAMIENTO" }
    }

    /// Cargos de servicio a la habitación (pedidos aprobados).
    var cargosConsumo: [Cargo] {
        cargosActivos.filter { $0.concepto.uppercased() == "CONSUMO" }
    }

    var totalHospedaje: Decimal {
        cargosHospedaje.reduce(Decimal.zero) { $0 + $1.monto }
    }

    var totalConsumos: Decimal {
        cargosConsumo.reduce(Decimal.zero) { $0 + $1.monto }
    }

    /// Costo de hospedaje + todos los pedidos acumulados.
    var totalEstadia: Decimal { totalHospedaje + totalConsumos }
}

/// Imagen subida al backend.
struct ImagenSubida: Decodable, Sendable {
    let id: Int
    /// Guardar en `imagenUrl`. Ej: /api/imagenes/42
    let url: String
    let ancho: Int
    let alto: Int
    let tamano: Int
    let contentType: String
    let nombre: String?
    let yaExistia: Bool
}

/// QR del deposito generado por el backend (pasarela simulada).
struct PagoQr: Decodable, Sendable {
    let pagoId: Int
    let monto: Decimal
    let estado: String
    /// Enlace que contiene el QR; se puede abrir en Safari.
    let url: String
    /// PNG ya renderizado por el backend: la app no genera el QR.
    let imagenBase64: String
    let expiraEn: String?
}

struct CrearPagoRequest: Encodable, Sendable {
    let tipo: String
    let metodo: String
    let monto: Decimal
    let idempotencyKey: String
    let codigoOperacion: String?
}

struct CrearCargoRequest: Encodable, Sendable {
    let concepto: String
    let descripcion: String
    let cantidad: Decimal
    let precioUnitario: Decimal
}

struct AnularCargoRequest: Encodable, Sendable {
    let motivo: String
}

struct AprobarPagoRequest: Encodable, Sendable {
    let codigoOperacion: String?
    let observacion: String?
}

struct RechazarPagoRequest: Encodable, Sendable {
    let motivo: String
    let observacion: String?
}

// MARK: - Housekeeping

struct TareaLimpieza: Decodable, Identifiable, Equatable, Sendable {
    let id: Int
    let habitacionId: Int
    let habitacionNumero: String
    let tipo: String
    let estado: String
    let prioridad: String
    let asignadaA: Int?
    let inicioEn: String?
    let finEn: String?

    var urgente: Bool { prioridad == "URGENTE" || prioridad == "CRITICA" }

    /// Siguiente paso del flujo: PENDIENTE → EN_PROCESO → COMPLETADA → VERIFICADA.
    var siguienteEstado: String? {
        switch estado {
        case "PENDIENTE": return "EN_PROCESO"
        case "EN_PROCESO": return "COMPLETADA"
        case "COMPLETADA": return "VERIFICADA"
        default: return nil
        }
    }
}

struct ActualizarTareaRequest: Encodable, Sendable {
    let estado: String
    let observaciones: String?
}

struct CrearTareaRequest: Encodable, Sendable {
    let habitacionId: Int
    let tipo: String
    let prioridad: String?
    let asignadaA: Int?
    let observaciones: String?
}

struct CrearIncidenciaRequest: Encodable, Sendable {
    let habitacionId: Int
    let descripcion: String
    let prioridad: String
}

// MARK: - Notificaciones

struct Notificacion: Decodable, Identifiable, Sendable {
    let id: Int
    let tipo: String
    let titulo: String
    let mensaje: String
    let referenciaId: Int?
    let referenciaTipo: String?
    let leida: Bool
    let creadoEn: String
}

// MARK: - Reportes

struct OcupacionPorSede: Decodable, Sendable {
    let sedeId: Int
    let sedeNombre: String
    let habitaciones: Int
    let ocupadas: Int
    let porcentaje: Double
}

struct Dashboard: Decodable, Sendable {
    let totalHabitaciones: Int
    let habitacionesOcupadas: Int
    let porcentajeOcupacion: Double
    let llegadasHoy: Int
    let salidasHoy: Int
    let reservasPendientes: Int
    let tareasPendientes: Int
    let ingresosMes: Decimal
    let cuentasPorCobrar: Decimal
    let porSede: [OcupacionPorSede]
}

struct Kpi: Decodable, Sendable {
    let desde: String
    let hasta: String
    let habitacionesDisponibles: Int
    let habitacionesOcupadas: Int
    let porcentajeOcupacion: Double
    let ingresos: Decimal
    let adr: Decimal
    let revpar: Decimal
}

struct IngresoPorCategoria: Decodable, Identifiable, Sendable {
    let categoriaId: Int
    let categoriaNombre: String
    let reservas: Int
    let ingresos: Decimal

    var id: Int { categoriaId }
}

struct IngresoPorConcepto: Decodable, Identifiable, Sendable {
    let concepto: String
    let monto: Decimal

    var id: String { concepto }
}

struct OcupacionDiaria: Decodable, Identifiable, Sendable {
    let fecha: String
    let ocupadas: Int
    let disponibles: Int
    let porcentaje: Double

    var id: String { fecha }
}

struct ReporteOcupacion: Decodable, Sendable {
    let sedeId: Int
    let desde: String
    let hasta: String
    let dias: [OcupacionDiaria]
}

// MARK: - Administración (usuarios, roles, sedes)

struct CrearUsuarioRequest: Encodable, Sendable {
    let nombre: String
    let email: String
    let password: String
    let telefono: String?
    let roles: [String]
    let sedes: [Int]?
}

struct ActualizarUsuarioRequest: Encodable, Sendable {
    let nombre: String
    let telefono: String?
    let fotoUrl: String?
    let roles: [String]?
    let sedes: [Int]?
}

struct CambiarEstadoUsuarioRequest: Encodable, Sendable {
    let activo: Bool
    let motivo: String?
}

struct CrearRolRequest: Encodable, Sendable {
    let nombre: String
    let descripcion: String?
    let permisos: [String]?
}

struct BloqueoCuenta: Decodable, Sendable {
    let usuarioId: Int
    let email: String
    let nombre: String
    let intentosFallidos: Int
    let nivelBloqueo: Int
    let bloqueado: Bool
    let bloqueadoHasta: String?
    let reintentarEnSegundos: Int?
}
