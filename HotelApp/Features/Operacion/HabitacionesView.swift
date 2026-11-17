import SwiftUI
import UIKit

/// Tablero de habitaciones por estado (recepción, admin).
///
/// Permite filtrar, ver el detalle y —si el rol lo autoriza— cambiar el estado
/// (mantenimiento, fuera de servicio) o bloquear la habitación con un motivo.
struct HabitacionesView: View {

    @Environment(SesionStore.self) private var sesion
    @Environment(OperacionStore.self) private var operacion
    @Environment(CatalogoStore.self) private var catalogo
    @Environment(SedeActivaStore.self) private var sedeActiva

    @State private var filtro: String?
    @State private var seleccionada: Habitacion?
    @State private var error: String?

    private var usuario: Usuario? { sesion.usuario }

    private var sedeId: Int? {
        guard let usuario else { return sesion.sedePrincipal?.id }
        return sedeActiva.idEfectivo(para: usuario)
    }

    private var sedeActual: Sede? {
        guard let usuario else { return sesion.sedePrincipal }
        return sedeActiva.efectiva(para: usuario)
    }

    /// Filtro del tablero. `estado == nil` es "Todas".
    private struct FiltroHabitacion: Identifiable {
        let estado: String?
        let titulo: String
        let icono: String

        var id: String { titulo }
    }

    private let filtros: [FiltroHabitacion] = [
        FiltroHabitacion(estado: nil, titulo: "Todas", icono: "square.grid.2x2"),
        FiltroHabitacion(estado: "DISPONIBLE", titulo: "Disponibles",
                         icono: "checkmark.circle"),
        FiltroHabitacion(estado: "OCUPADA", titulo: "Ocupadas", icono: "person.fill"),
        FiltroHabitacion(estado: "LIMPIEZA", titulo: "Limpieza", icono: "sparkles"),
        FiltroHabitacion(estado: "MANTENIMIENTO", titulo: "Mantenimiento",
                         icono: "wrench.and.screwdriver"),
        FiltroHabitacion(estado: "FUERA_SERVICIO", titulo: "Fuera",
                         icono: "exclamationmark.octagon"),
    ]

    private var cargandoInicial: Bool {
        operacion.cargando && operacion.habitaciones == nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let resumen = operacion.habitaciones?.resumen {
                    resumenGrid(resumen)
                } else if cargandoInicial {
                    resumenGridPlaceholder
                }

                filtrosScroll

                contenido

                if let error {
                    Aviso(tipo: .peligro, titulo: "Error", mensaje: error)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Tema.fondo.ignoresSafeArea())
        .navigationTitle(sedeActual.map { "Habitaciones · \($0.nombre)" } ?? "Habitaciones")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let usuario, usuario.puedeVerReportes, usuario.sedes.count > 1 {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        ForEach(usuario.sedes) { sede in
                            Button {
                                guard sedeActiva.seleccionar(sede.id, para: usuario) else { return }
                                Task { await recargar(forzar: true) }
                            } label: {
                                if sede.id == sedeId {
                                    Label(sede.nombre, systemImage: "checkmark")
                                } else {
                                    Text(sede.nombre)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "building.2")
                    }
                    .accessibilityLabel("Cambiar de sede")
                }
            }
        }
        .refreshable { await recargar(forzar: true) }
        .task { await cargar() }
        .sheet(item: $seleccionada) { h in
            DetalleHabitacionSheet(
                habitacion: h,
                sedeId: sedeId ?? 0,
                puedeCambiarEstado: sesion.esAdmin,
                alActualizar: { await recargar(forzar: true) })
        }
    }

    // MARK: - Contenido

    @ViewBuilder
    private var contenido: some View {
        if cargandoInicial {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)],
                      spacing: 12) {
                ForEach(0..<6, id: \.self) { _ in
                    Tarjeta(padding: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("000").font(.title2.weight(.bold))
                            Text("Categoría").font(.caption)
                            Text("Piso 0").font(.caption2)
                            Spacer(minLength: 0)
                        }
                        .frame(height: 84, alignment: .leading)
                    }
                }
            }
            .redacted(reason: .placeholder)
            .allowsHitTesting(false)
        } else if let lista = operacion.habitaciones, lista.habitaciones.isEmpty {
            EstadoVacio(icono: "bed.double",
                        titulo: "Sin habitaciones",
                        mensaje: "No hay habitaciones con ese filtro.")
        } else if let lista = operacion.habitaciones {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)],
                      spacing: 12) {
                ForEach(lista.habitaciones) { h in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        seleccionada = h
                    } label: {
                        tarjeta(h)
                    }
                    .buttonStyle(EstiloPresionable())
                    .accessibilityLabel(accessibilityTarjeta(h))
                }
            }
            .animation(.snappy(duration: 0.25), value: lista.habitaciones)
        }
    }

    // MARK: - Resumen

    private func resumenGrid(_ r: ResumenEstados) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8)],
                  spacing: 8) {
            resumenItem(valor: r.total, titulo: "Total",
                        icono: "square.grid.2x2.fill", color: Tema.azulOscuro)
            resumenItem(valor: r.disponibles, titulo: "Libres",
                        icono: "checkmark.circle.fill", color: Tema.exito)
            resumenItem(valor: r.ocupadas, titulo: "Ocupadas",
                        icono: "person.fill", color: Tema.azul)
            resumenItem(valor: r.limpieza, titulo: "Limpieza",
                        icono: "sparkles", color: Tema.info)
            resumenItem(valor: r.mantenimiento + r.fueraServicio,
                        titulo: "Mant./Fuera",
                        icono: "wrench.and.screwdriver.fill", color: Tema.alerta)
        }
    }

    /// Mismo alto que la rejilla real: evita el salto al terminar de cargar.
    private var resumenGridPlaceholder: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8)],
                  spacing: 8) {
            ForEach(0..<5, id: \.self) { _ in
                Tarjeta(padding: 10) {
                    VStack(spacing: 4) {
                        Image(systemName: "circle").font(.footnote)
                            .foregroundStyle(Tema.textoSecundario)
                        Text("0").font(.title3.weight(.bold))
                        Text("Métrica").font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
    }

    private func resumenItem(valor: Int, titulo: String,
                             icono: String, color: Color) -> some View {
        Tarjeta(padding: 10) {
            VStack(spacing: 4) {
                Image(systemName: icono)
                    .font(.footnote)
                    .foregroundStyle(color)

                Text("\(valor)")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(color)
                    .contentTransition(.numericText())

                Text(titulo)
                    .font(.caption2)
                    .foregroundStyle(Tema.textoSecundario)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(titulo): \(valor)")
    }

    // MARK: - Filtros

    private var filtrosScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filtros) { f in
                    let activo = filtro == f.estado
                    Button {
                        // Tocar el filtro ya activo no recarga nada.
                        guard !activo else { return }
                        filtro = f.estado
                        Task { await recargar(forzar: true) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: f.icono)
                                .font(.caption2.weight(.semibold))
                            Text(f.titulo)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(activo ? Tema.azul : Tema.superficie)
                        .foregroundStyle(activo ? Color.white : Tema.texto)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(activo ? Color.clear : Tema.borde,
                                             lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .animation(.snappy(duration: 0.2), value: activo)
                    .accessibilityLabel("Filtro \(f.titulo)")
                    .accessibilityAddTraits(activo ? AccessibilityTraits.isSelected : AccessibilityTraits())
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Tarjeta

    private func tarjeta(_ h: Habitacion) -> some View {
        let estado = Etiquetas.estadoHabitacion(h.estado)

        return HStack(spacing: 0) {
            // Franja lateral del color de estado.
            Rectangle()
                .fill(estado.color)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(h.numero)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Tema.texto)
                    Spacer(minLength: 0)
                    Circle()
                        .fill(estado.color)
                        .frame(width: 8, height: 8)
                }

                Text(h.categoriaNombre)
                    .font(.caption)
                    .foregroundStyle(Tema.textoSecundario)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Label("Piso \(h.pisoNumero)", systemImage: "building.2")
                    Label("\(h.capacidadAdultos)", systemImage: "person.fill")
                }
                .font(.caption2)
                .foregroundStyle(Tema.textoSecundario)
                .labelStyle(.titleAndIcon)

                Text(estado.texto)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(estado.color)
                    .lineLimit(1)

                if !h.activo {
                    Text("Inactiva")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Tema.peligro)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.superficie)
        .clipShape(RoundedRectangle(cornerRadius: Tema.radio, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Tema.radio, style: .continuous)
                .stroke(Tema.borde, lineWidth: 1))
        .shadow(color: Tema.colorSombra, radius: 12, x: 0, y: 4)
    }

    private func accessibilityTarjeta(_ h: Habitacion) -> String {
        let estado = Etiquetas.estadoHabitacion(h.estado)
        return "Habitación \(h.numero), \(h.categoriaNombre), "
            + "piso \(h.pisoNumero), \(estado.texto)"
    }

    // MARK: - Carga

    private func cargar() async {
        await recargar(forzar: true)
    }

    /// Recarga el tablero. `forzar == false` evita repetir la petición cuando
    /// ya hay datos de la misma sede y filtro (por ejemplo, al cambiar de
    /// pestaña y volver).
    private func recargar(forzar: Bool) async {
        guard let sedeId else {
            error = "No tienes sede asignada."
            return
        }
        guard forzar || operacion.habitaciones == nil else { return }

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

    private var motivoLimpio: String {
        motivo.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var incidenciaLimpia: String {
        incidencia.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    cabecera

                    if puedeCambiarEstado && !habitacion.estaOcupada {
                        Tarjeta {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Cambiar estado")
                                    .font(.headline)

                                Picker("Estado", selection: $estadoDestino) {
                                    Text("Disponible").tag("DISPONIBLE")
                                    Text("Mantenimiento").tag("MANTENIMIENTO")
                                    Text("Fuera de servicio").tag("FUERA_SERVICIO")
                                }
                                .pickerStyle(.segmented)
                                .onChange(of: estadoDestino) { _, _ in
                                    // El motivo pertenece al estado anterior.
                                    motivo = ""
                                    error = nil
                                }

                                if estadoDestino != "DISPONIBLE" {
                                    TextField("Motivo (aire acondicionado, pintura...)",
                                              text: $motivo, axis: .vertical)
                                        .lineLimit(1...3)
                                        .font(.body)
                                        .padding(9)
                                        .background(Tema.fondo)
                                        .clipShape(RoundedRectangle(
                                            cornerRadius: Tema.radioPequeno,
                                            style: .continuous))
                                }

                                BotonPrincipal(titulo: "Aplicar cambio",
                                               icono: "arrow.triangle.2.circlepath",
                                               cargando: procesando,
                                               deshabilitado: estadoDestino != "DISPONIBLE"
                                                && motivoLimpio.isEmpty) {
                                    Task { await cambiarEstado() }
                                }
                            }
                        }

                        Tarjeta {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Reportar incidencia")
                                    .font(.headline)

                                Text("Se registra en mantenimiento con prioridad normal.")
                                    .font(.caption)
                                    .foregroundStyle(Tema.textoSecundario)

                                TextField("Describe el problema...",
                                          text: $incidencia, axis: .vertical)
                                    .lineLimit(1...3)
                                    .font(.body)
                                    .padding(9)
                                    .background(Tema.fondo)
                                    .clipShape(RoundedRectangle(
                                        cornerRadius: Tema.radioPequeno,
                                        style: .continuous))

                                BotonPrincipal(titulo: "Enviar incidencia",
                                               icono: "wrench.and.screwdriver",
                                               cargando: reportando,
                                               deshabilitado: incidenciaLimpia.isEmpty) {
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
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var cabecera: some View {
        let estado = Etiquetas.estadoHabitacion(habitacion.estado)

        return VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottom) {
                ImagenRemota(
                    ruta: catalogo.fotoCategoria(habitacion.categoriaNombre,
                                                 url: categoria?.imagenUrl),
                    iconoRespaldo: "bed.double.fill",
                    alto: 180)

                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.55)],
                    startPoint: .center,
                    endPoint: .bottom)

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Habitación")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.8))
                        Text(habitacion.numero)
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(.white)
                    }
                    Spacer(minLength: 8)
                    EtiquetaEstado(texto: estado.texto,
                                   color: estado.color,
                                   icono: "circle.fill")
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 180)
            .frame(maxWidth: .infinity)
            .clipped()

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(habitacion.categoriaNombre)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Tema.texto)

                    Spacer(minLength: 8)

                    if let precio = categoria?.precioBase {
                        HStack(spacing: 2) {
                            Text(Tema.soles(precio))
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Tema.azul)
                            Text("/noche")
                                .font(.caption2)
                                .foregroundStyle(Tema.textoSecundario)
                        }
                    } else if categoria != nil {
                        Text("Sin tarifa")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Tema.alerta)
                    }
                }

                HStack(spacing: 14) {
                    Label("Piso \(habitacion.pisoNumero)", systemImage: "building.2")
                    Label("\(habitacion.capacidadAdultos) adulto(s) + \(habitacion.capacidadNinos) niño(s)",
                          systemImage: "person.2")
                }
                .font(.caption)
                .foregroundStyle(Tema.textoSecundario)

                if let motivoBloqueo = habitacion.motivoBloqueo,
                   !motivoBloqueo.isEmpty {
                    Label(motivoBloqueo, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Tema.alerta)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
        .background(Tema.superficie)
        .clipShape(RoundedRectangle(cornerRadius: Tema.radio, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Tema.radio, style: .continuous)
                .stroke(Tema.borde, lineWidth: 1))
        .shadow(color: Tema.colorSombra, radius: 12, x: 0, y: 4)
    }

    // MARK: - Acciones

    private func cambiarEstado() async {
        guard sedeId != 0 else { return }
        if estadoDestino != "DISPONIBLE" && motivoLimpio.isEmpty {
            error = "Indica el motivo del bloqueo."
            return
        }

        procesando = true
        error = nil

        do {
            try await operacion.cambiarEstado(
                habitacionId: habitacion.id,
                estado: estadoDestino,
                motivo: estadoDestino == "DISPONIBLE" ? nil : motivoLimpio,
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
        let descripcion = incidenciaLimpia
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