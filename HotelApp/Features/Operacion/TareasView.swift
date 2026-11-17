import SwiftUI

/// Tareas de housekeeping.
///
/// Flujo del backend:
///   PENDIENTE → EN_PROCESO → COMPLETADA → VERIFICADA
///
/// Solo al verificar (supervisor) la habitación pasa a DISPONIBLE.
struct TareasView: View {

    @Environment(SesionStore.self) private var sesion
    @Environment(CatalogoStore.self) private var catalogo

    @State private var tareas: [TareaLimpieza] = []
    @State private var cargando = true
    @State private var filtro = "PENDIENTE"
    @State private var procesando: Int?
    @State private var error: String?

    private let api = HotelAPI.shared
    private let filtros = ["PENDIENTE", "EN_PROCESO", "COMPLETADA", "VERIFICADA"]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                filtrosScroll

                if cargando {
                    ProgressView().padding(.top, 40)
                } else if tareas.isEmpty {
                    EstadoVacio(icono: "sparkles",
                                titulo: "Sin tareas",
                                mensaje: "No hay tareas en este estado.")
                } else {
                    ForEach(tareas) { tarea in
                        tarjeta(tarea)
                    }
                }

                if let error {
                    Aviso(tipo: .peligro, titulo: "Error", mensaje: error)
                }
            }
            .padding(16)
        }
        .background(Tema.fondo.ignoresSafeArea())
        .navigationTitle("Housekeeping")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await cargar() }
        .task {
            await cargar()
            if let sedeId = sesion.sedePrincipal?.id, catalogo.categorias.isEmpty {
                await catalogo.cargarCategorias(sedeId: sedeId)
            }
        }
    }

    // MARK: - Subvistas

    private var filtrosScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filtros, id: \.self) { f in
                    let activo = filtro == f
                    Button {
                        // Tocar el filtro ya activo no recarga.
                        guard !activo else { return }
                        filtro = f
                        Task { await cargar() }
                    } label: {
                        Text(etiquetaFiltro(f))
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 40)
                            .background(activo ? Tema.azul : Tema.superficie)
                            .foregroundStyle(activo ? Color.white : Tema.texto)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(activo ? Color.clear : Tema.borde,
                                                 lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .animation(.snappy(duration: 0.2), value: activo)
                    .accessibilityAddTraits(activo ? AccessibilityTraits.isSelected
                                                   : AccessibilityTraits())
                }
            }
        }
    }

    private func tarjeta(_ t: TareaLimpieza) -> some View {
        let estado = Etiquetas.estadoTarea(t.estado)

        return HStack(spacing: 0) {
            Rectangle()
                .fill(t.urgente ? Tema.peligro : estado.color)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Habitación \(t.habitacionNumero)")
                            .font(.headline)
                            .foregroundStyle(Tema.texto)
                        Text(t.tipo.capitalized)
                            .font(.caption)
                            .foregroundStyle(Tema.textoSecundario)
                    }

                    Spacer(minLength: 0)

                    if t.urgente {
                        EtiquetaEstado(texto: "Urgente", color: Tema.peligro,
                                       icono: "exclamationmark.triangle.fill")
                    } else {
                        EtiquetaEstado(texto: estado.texto, color: estado.color)
                    }
                }

                if t.inicioEn != nil || t.finEn != nil {
                    HStack(spacing: 12) {
                        if let inicio = t.inicioEn {
                            Label(FechaAPI.formatearConHora(FechaAPI.parsear(inicio)),
                                  systemImage: "clock")
                                .font(.caption2)
                                .foregroundStyle(Tema.textoSecundario)
                        }
                        if let fin = t.finEn {
                            Label(FechaAPI.formatearConHora(FechaAPI.parsear(fin)),
                                  systemImage: "checkmark.circle")
                                .font(.caption2)
                                .foregroundStyle(Tema.textoSecundario)
                        }
                    }
                }

                acciones(t)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Tema.superficie)
        .clipShape(RoundedRectangle(cornerRadius: Tema.radio, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Tema.radio, style: .continuous)
                .stroke(Tema.borde, lineWidth: 1))
        .shadow(color: Tema.colorSombra, radius: 12, x: 0, y: 4)
    }

    @ViewBuilder
    private func acciones(_ t: TareaLimpieza) -> some View {
        switch t.estado {
        case "PENDIENTE":
            boton("Iniciar limpieza", "play.fill", t, "EN_PROCESO")

        case "EN_PROCESO":
            boton("Marcar completada", "checkmark", t, "COMPLETADA")

        case "COMPLETADA":
            if sesion.esAdmin || sesion.esGerente {
                boton("Verificar y liberar", "checkmark.seal.fill", t, "VERIFICADA")
            } else {
                Label("Pendiente del supervisor", systemImage: "hourglass")
                    .font(.caption)
                    .foregroundStyle(Tema.textoSecundario)
            }

        default:
            Label("Verificada", systemImage: "checkmark.seal.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Tema.exito)
        }
    }

    private func boton(_ titulo: String, _ icono: String,
                       _ tarea: TareaLimpieza, _ nuevoEstado: String) -> some View {
        Button {
            Task { await avanzar(tarea, nuevoEstado) }
        } label: {
            HStack(spacing: 7) {
                if procesando == tarea.id {
                    ProgressView().tint(.white).scaleEffect(0.8)
                } else {
                    Image(systemName: icono)
                        .font(.subheadline.weight(.semibold))
                }
                Text(procesando == tarea.id ? "Guardando..." : titulo)
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .background(procesando == tarea.id ? Tema.azul.opacity(0.6) : Tema.azul)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: Tema.radioPequeno,
                                        style: .continuous))
        }
        .buttonStyle(EstiloPresionable())
        .disabled(procesando != nil)
        .accessibilityLabel(titulo)
    }

    private func etiquetaFiltro(_ valor: String) -> String {
        switch valor {
        case "PENDIENTE": return "Pendientes"
        case "EN_PROCESO": return "En proceso"
        case "COMPLETADA": return "Completadas"
        case "VERIFICADA": return "Verificadas"
        default: return valor
        }
    }

    // MARK: - Acciones

    private func cargar() async {
        cargando = true
        error = nil

        do {
            // Admin y gerente ven todas las tareas; housekeeping solo las suyas.
            if sesion.esAdmin || sesion.esGerente {
                let todas = try await api.todasLasTareas()
                tareas = todas.filter { $0.estado == filtro }
            } else {
                tareas = try await api.tareas(estado: filtro)
            }
        } catch let apiError as APIError {
            error = apiError.mensajeUsuario
        } catch {
            self.error = "No se pudieron cargar las tareas."
        }

        cargando = false
    }

    private func avanzar(_ tarea: TareaLimpieza, _ estado: String) async {
        procesando = tarea.id
        error = nil

        do {
            // PATCH con body: el backend exige `ActualizarTareaRequest`.
            _ = try await api.actualizarTarea(id: tarea.id, estado: estado)
            await cargar()
        } catch let apiError as APIError {
            error = apiError.mensajeUsuario
        } catch {
            self.error = "No se pudo actualizar la tarea."
        }

        procesando = nil
    }
}
