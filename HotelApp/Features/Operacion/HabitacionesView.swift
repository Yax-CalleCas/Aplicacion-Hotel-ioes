import SwiftUI
import UIKit

/// Tablero de habitaciones por estado (recepción, admin).
///
/// Muestra habitaciones en una cuadrícula de 2 columnas estilo Airbnb con
/// foto, favorito, título, precio y calificación.
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
}

// MARK: - Contenido de la cuadrícula

private extension HabitacionesView {

    var contenido: some View {
        if cargandoInicial {
            loadingPlaceholder
        } else if let lista = operacion.habitaciones, lista.habitaciones.isEmpty {
            EstadoVacio(icono: "bed.double",
                        titulo: "Sin habitaciones",
                        mensaje: "No hay habitaciones con ese filtro.")
        } else if let lista = operacion.habitaciones {
            habitacionesGrid(lista.habitaciones)
        } else {
            EmptyView()
        }
    }

    // Grilla de 2 columnas estilo Airbnb
    func habitacionesGrid(_ habitaciones: [Habitacion]) -> some View {
        LazyVGrid(columns: columns2, spacing: 16) {
            ForEach(habitaciones) { h in
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
        .padding(.horizontal, 4) // espaciado lateral de la grid
    }

    /// Dos columnas fijas con ancho adaptativo.
    private var columns2: some View {
        LazyVGridColumns(
            flexible: .init(minimum: 160, maximum: 200),
            flexible: .init(minimum: 160, maximum: 200),
            spacing: 16)
    }

    // MARK: - Subvistas de la tarjeta

    private func tarjeta(_ h: Habitacion) -> some View {
        let estado = Etiquetas.estadoHabitacion(h.estado)

        // Obtenemos la categoría del catálogo para la foto y precio.
        let categoria = catalogo.categorias.first(where: { $0.id == h.categoriaId })

        return VStack(alignment: .leading, spacing: 8) {
            // Foto con corners redondeadas y object-fit cover
            ZStack(alignment: .topTrailing) {
                ImagenRemota(
                    ruta: categoria?.imagenUrl,
                    iconoRespaldo: "bed.double.fill",
                    alto: 140)

                // Corazón/favorito arriba a la derecha
                BotonFavorito(habitacion: h)
                    .frame(width: 24, height: 24)
            }
            .frame(height: 140)
            .clipped()

            // Título debajo de la foto
            Text(h.categoriaNombre)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Tema.texto)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Precio por noche
            if let precio = categoria?.precioBase {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(Tema.soles(precio))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Tema.azul)
                    Text("/noche")
                        .font(.caption2)
                        .foregroundStyle(Tema.textoSecundario)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Etiqueta de estado
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Label("Piso \(h.pisoNumero)", systemImage: "building.2")
                    .font(.caption2)
                    .foregroundStyle(Tema.textoSecundario)
                Label("\(h.capacidadAdultos) adulto(s)", systemImage: "person.fill")
                    .font(.caption2)
                    .foregroundStyle(Tema.textoSecundario)
            }
            .font(.caption2)
            .foregroundStyle(Tema.textoSecundario)

            // Estado colorido
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
        .padding(10)
        .background(Tema.superficie)
        .clipShape(RoundedRectangle(cornerRadius: Tema.radio, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Tema.radio, style: .continuous)
                .stroke(Tema.borde, lineWidth: 1))
        .shadow(color: Tema.colorSombra, radius: 8, x: 0, y: 4)
    }

    // MARK: - Favorito (corazón)

    struct BotonFavorito: View {
        let habitacion: Habitacion
        @Environment(SesionStore.self) private var sesion
        @Environment(OperacionStore.self) private var operacion
        @State private var esFavorito = false

        var body: some View {
            Button {
                // TODO: Llamar al backend para togglear favorito
                // por ahora solo toggle local
                esFavorito.toggle()
            } label: {
                Image(systemName: esFavorito ? "heart.fill" : "heart")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(esFavorito ? .red : .white)
                    .frame(width: 24, height: 24)
                    .background(.black.opacity(0.4))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(esFavorito ? "Quitar de favoritos" : "Añadir a favoritos")
            .frame(alignment: .topTrailing)
        }
    }

    // MARK: - Placeholder de carga

    var loadingPlaceholder: some View {
        LazyVGrid(columns: columns2, spacing: 16) {
            ForEach(0..<6, id: \.self) { _ in
                TarjetaVacia()
            }
        }
        .padding(.horizontal, 4)
    }

    private struct TarjetaVacia: View {
        var body: some View {
            VStack(spacing: 8) {
                ImagenRemota(
                    ruta: nil,
                    iconoRespaldo: "bed.double.fill",
                    alto: 140)
                Text("").font(.headline)
            }
            .frame(height: 180)
            .frame(maxWidth: .infinity)
            .background(Tema.superficie)
            .clipShape(RoundedRectangle(cornerRadius: Tema.radio, style: .continuous))
        }
    }
}

// MARK: - Ayudas auxiliares

private struct LazyVGridColumns: View {
    let flexible: [LazyVGridItem]
    let spacing: CGFloat

    init(flexible: LazyVGridItem, flexible: LazyVGridItem, spacing: CGFloat) {
        self.flexible = [flexible, flexible]
        self.spacing = spacing
    }

    var body: some View {
        LazyVGrid(columns: flexible, spacing: spacing)
    }
}