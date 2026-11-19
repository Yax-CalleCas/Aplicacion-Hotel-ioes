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
                    Button {
                        filtro = f
                        Task { await cargar() }
                    } label: {
                        Text(etiquetaFiltro(f))
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(filtro == f ? Tema.azul : Tema.superficie)
                            .foregroundStyle(filtro == f ? .white : Tema.texto)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private func tarjeta(_ t: TareaLimpieza) -> some View {
        let estado = Etiquetas.estadoTarea(t.estado)

        return Tarjeta {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Habitación \(t.habitacionNumero)")
                            .font(.system(size: 16, weight: .semibold))
                        Text(t.tipo)
                            .font(.system(size: 10))
                            .foregroundStyle(Tema.textoSecundario)
                    }

                    Spacer()

                    if t.urgente {
                        EtiquetaEstado(texto: "Urgente", color: Tema.peligro,
                                       icono: "exclamationmark.triangle.fill")
                    } else {
                        EtiquetaEstado(texto: estado.texto, color: estado.color)
                    }
                }

                if let inicio = t.inicioEn {
                    Label("Inicio: \(FechaAPI.formatearConHora(FechaAPI.parsear(inicio)))",
                          systemImage: "clock")
                        .font(.system(size: 10))
                        .foregroundStyle(Tema.textoSecundario)
                }

                if let fin = t.finEn {
                    Label("Fin: \(FechaAPI.formatearConHora(FechaAPI.parsear(fin)))",
                          systemImage: "checkmark.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(Tema.textoSecundario)
                }

                acciones(t)
            }
        }
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
                Text("Pendiente de verificación del supervisor")
                    .font(.system(size: 10))
                    .foregroundStyle(Tema.textoSecundario)
            }

        default:
            Label("Verificada", systemImage: "checkmark.seal.fill")
                .font(.system(size: 10))
                .foregroundStyle(Tema.exito)
        }
    }

    private func boton(_ titulo: String, _ icono: String,
                       _ tarea: TareaLimpieza, _ nuevoEstado: String) -> some View {
        Button {
            Task { await avanzar(tarea, nuevoEstado) }
        } label: {
            HStack(spacing: 6) {
                if procesando == tarea.id {
                    ProgressView().tint(.white).scaleEffect(0.8)
                } else {
                    Image(systemName: icono)
                }
                Text(titulo)
                    .font(.system(size: 12, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Tema.azul)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .disabled(procesando != nil)
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
