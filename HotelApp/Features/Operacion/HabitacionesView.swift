import SwiftUI

/// Tablero de habitaciones por estado (recepción, admin).
///
/// Permite filtrar, ver el detalle y —si el rol lo autoriza— cambiar el estado
/// (mantenimiento, fuera de servicio) o bloquear la habitación con un motivo.
struct HabitacionesView: View {

    @Environment(SesionStore.self) private var sesion
    @Environment(OperacionStore.self) private var operacion
    @Environment(CatalogoStore.self) private var catalogo

    @State private var filtro: String?
    @State private var seleccionada: Habitacion?
    @State private var error: String?

    private var sedeId: Int? { sesion.sedePrincipal?.id }

    private let filtros: [(String?, String)] = [
        (nil, "Todas"),
        ("DISPONIBLE", "Disponibles"),
        ("OCUPADA", "Ocupadas"),
        ("LIMPIEZA", "Limpieza"),
        ("MANTENIMIENTO", "Mantenimiento"),
        ("FUERA_SERVICIO", "Fuera"),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let resumen = operacion.habitaciones?.resumen {
                    resumenGrid(resumen)
                }

                filtrosScroll

                if operacion.cargando && operacion.habitaciones == nil {
                    ProgressView().padding(.top, 40)
                } else if let lista = operacion.habitaciones, lista.habitaciones.isEmpty {
                    EstadoVacio(icono: "bed.double",
                                titulo: "Sin habitaciones",
                                mensaje: "No hay habitaciones con ese filtro.")
                } else if let lista = operacion.habitaciones {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)],
                              spacing: 10) {
                        ForEach(lista.habitaciones) { h in
                            Button {
                                seleccionada = h
                            } label: {
                                tarjeta(h)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if let error {
                    Aviso(tipo: .peligro, titulo: "Error", mensaje: error)
                }
            }
            .padding(16)
        }
        .background(Tema.fondo.ignoresSafeArea())
        .navigationTitle("Habitaciones")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await cargar() }
        .task { await cargar() }
        .sheet(item: $seleccionada) { h in
            DetalleHabitacionSheet(
                habitacion: h,
                sedeId: sedeId ?? 0,
                puedeCambiarEstado: sesion.esAdmin,
                alActualizar: { await cargar() })
        }
    }

    private func resumenGrid(_ r: ResumenEstados) -> some View {
        HStack(spacing: 8) {
            resumenItem("\(r.total)", "Total", Tema.textoSecundario)
            resumenItem("\(r.disponibles)", "Libres", Tema.exito)
            resumenItem("\(r.ocupadas)", "Ocup.", Tema.azul)
            resumenItem("\(r.limpieza)", "Limp.", Tema.info)
        }
    }

    private func resumenItem(_ valor: String, _ titulo: String, _ color: Color) -> some View {
        Tarjeta(padding: 10) {
            VStack(spacing: 2) {
                Text(valor)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                Text(titulo)
                    .font(.system(size: 9))
                    .foregroundStyle(Tema.textoSecundario)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var filtrosScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filtros, id: \.1) { f in
                    Button {
                        filtro = f.0
                        Task { await cargar() }
                    } label: {
                        Text(f.1)
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(filtro == f.0 ? Tema.azul : Tema.superficie)
                            .foregroundStyle(filtro == f.0 ? .white : Tema.texto)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private func tarjeta(_ h: Habitacion) -> some View {
        let estado = Etiquetas.estadoHabitacion(h.estado)

        return Tarjeta(padding: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(h.numero)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Spacer()
                    Circle()
                        .fill(estado.color)
                        .frame(width: 8, height: 8)
                }

                Text(h.categoriaNombre)
                    .font(.system(size: 10))
                    .foregroundStyle(Tema.textoSecundario)
                    .lineLimit(1)

                Text("Piso \(h.pisoNumero)")
                    .font(.system(size: 9))
                    .foregroundStyle(Tema.textoSecundario)

                Text(estado.texto)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(estado.color)

                if !h.activo {
                    Text("Inactiva")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Tema.peligro)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func cargar() async {
        guard let sedeId else {
            error = "No tienes sede asignada."
            return
        }
        error = nil
        await operacion.cargarHabitaciones(sedeId: sedeId, estado: filtro)
        if operacion.error != nil { error = operacion.error }

        // Las categorías se usan solo para resolver la foto de la habitación.
        // Se recargan si no corresponden a esta sede.
        if !catalogo.categorias.contains(where: { $0.sedeId == sedeId }) {
            await catalogo.cargarCategorias(sedeId: sedeId)
        }
    }
}

/// Detalle de habitación con foto, datos y cambio de estado.
struct DetalleHabitacionSheet: View {

    let habitacion: Habitacion
    let sedeId: Int
    let puedeCambiarEstado: Bool
    let alActualizar: () async -> Void

    @Environment(CatalogoStore.self) private var catalogo
    @Environment(OperacionStore.self) private var operacion
    @Environment(\.dismiss) private var dismiss

    @State private var motivo = ""
    @State private var estadoDestino = "MANTENIMIENTO"
    @State private var incidencia = ""
    @State private var procesando = false
    @State private var reportando = false
    @State private var error: String?

    private let api = HotelAPI.shared

    private var categoria: CategoriaHabitacion? {
        catalogo.categorias.first { $0.id == habitacion.categoriaId }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Tarjeta(padding: 0) {
                        VStack(alignment: .leading, spacing: 0) {
                            ImagenRemota(
                                ruta: catalogo.fotoCategoria(habitacion.categoriaNombre,
                                                             url: categoria?.imagenUrl),
                                iconoRespaldo: "bed.double.fill",
                                alto: 170)

                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Habitación \(habitacion.numero)")
                                        .font(.system(size: 20, weight: .bold, design: .rounded))
                                    Spacer()
                                    let estado = Etiquetas.estadoHabitacion(habitacion.estado)
                                    EtiquetaEstado(texto: estado.texto, color: estado.color)
                                }

                                Text(habitacion.categoriaNombre)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Tema.textoSecundario)

                                Label("Piso \(habitacion.pisoNumero)", systemImage: "building.2")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Tema.textoSecundario)

                                Label("\(habitacion.capacidadAdultos) adulto(s) + \(habitacion.capacidadNinos) niño(s)",
                                      systemImage: "person.2")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Tema.textoSecundario)

                                if let motivoBloqueo = habitacion.motivoBloqueo,
                                   !motivoBloqueo.isEmpty {
                                    Label(motivoBloqueo, systemImage: "exclamationmark.triangle")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Tema.alerta)
                                }
                            }
                            .padding(14)
                        }
                    }

                    if puedeCambiarEstado && !habitacion.estaOcupada {
                        Tarjeta {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Cambiar estado")
                                    .font(.system(size: 13, weight: .semibold))

                                Picker("Estado", selection: $estadoDestino) {
                                    Text("Disponible").tag("DISPONIBLE")
                                    Text("Mantenimiento").tag("MANTENIMIENTO")
                                    Text("Fuera de servicio").tag("FUERA_SERVICIO")
                                }
                                .pickerStyle(.segmented)

                                if estadoDestino != "DISPONIBLE" {
                                    TextField("Motivo (aire acondicionado, pintura...)",
                                              text: $motivo, axis: .vertical)
                                        .lineLimit(1...3)
                                        .font(.system(size: 12))
                                        .padding(9)
                                        .background(Tema.fondo)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }

                                BotonPrincipal(titulo: "Aplicar cambio",
                                               icono: "arrow.triangle.2.circlepath",
                                               cargando: procesando) {
                                    Task { await cambiarEstado() }
                                }
                            }
                        }

                        Tarjeta {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Reportar incidencia")
                                    .font(.system(size: 13, weight: .semibold))

                                Text("Se registra en mantenimiento con prioridad normal.")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Tema.textoSecundario)

                                TextField("Describe el problema...",
                                          text: $incidencia, axis: .vertical)
                                    .lineLimit(1...3)
                                    .font(.system(size: 12))
                                    .padding(9)
                                    .background(Tema.fondo)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))

                                BotonPrincipal(titulo: "Enviar incidencia",
                                               icono: "wrench.and.screwdriver",
                                               cargando: reportando,
                                               deshabilitado: incidencia
                                                .trimmingCharacters(in: .whitespaces).isEmpty) {
                                    Task { await enviarIncidencia() }
                                }
                            }
                        }
                    } else if habitacion.estaOcupada {
                        Aviso(tipo: .info, titulo: "Habitación ocupada",
                              mensaje: "Solo el check-out del huésped puede liberarla.")
                    } else if habitacion.enLimpieza {
                        Aviso(tipo: .info, titulo: "En limpieza",
                              mensaje: "Housekeeping debe verificar la tarea para liberarla.")
                    }

                    if let error {
                        Aviso(tipo: .peligro, titulo: "Error", mensaje: error)
                    }
                }
                .padding(16)
            }
            .background(Tema.fondo.ignoresSafeArea())
            .navigationTitle("Habitación \(habitacion.numero)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }

    private func cambiarEstado() async {
        guard sedeId != 0 else { return }
        if estadoDestino != "DISPONIBLE" && motivo.trimmingCharacters(in: .whitespaces).isEmpty {
            error = "Indica el motivo del bloqueo."
            return
        }

        procesando = true
        error = nil

        do {
            try await operacion.cambiarEstado(
                habitacionId: habitacion.id,
                estado: estadoDestino,
                motivo: estadoDestino == "DISPONIBLE" ? nil : motivo,
                sedeId: sedeId)
            await alActualizar()
            dismiss()
        } catch let apiError as APIError {
            error = apiError.mensajeUsuario
        } catch {
            self.error = "No se pudo cambiar el estado."
        }

        procesando = false
    }

    /// Registra una incidencia de mantenimiento desde la habitación.
    private func enviarIncidencia() async {
        let descripcion = incidencia.trimmingCharacters(in: .whitespaces)
        guard !descripcion.isEmpty else { return }

        reportando = true
        error = nil

        do {
            try await api.crearIncidencia(
                habitacionId: habitacion.id,
                descripcion: descripcion,
                prioridad: "NORMAL")
            incidencia = ""
            await alActualizar()
            dismiss()
        } catch let apiError as APIError {
            error = apiError.mensajeUsuario
        } catch {
            self.error = "No se pudo registrar la incidencia."
        }

        reportando = false
    }
}
