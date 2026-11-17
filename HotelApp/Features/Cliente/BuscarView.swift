import SwiftUI
import UIKit

/// Búsqueda de disponibilidad y reserva (cliente).
///
/// Estructura:
///  1. Selector de sede con foto.
///  2. Fechas y ocupantes.
///  3. Resultado de la búsqueda (solo categorías con habitaciones libres).
///
/// Sin búsqueda activa se muestra el catálogo completo de la sede para que el
/// cliente vea las fotos antes de decidir, igual que en la web.
struct BuscarView: View {

    @Environment(CatalogoStore.self) private var catalogo
    @Environment(ReservaStore.self) private var reservas

    @State private var sedeId = 0
    @State private var checkIn = FechaAPI.hoy().addingTimeInterval(86400)
    @State private var checkOut = FechaAPI.hoy().addingTimeInterval(86400 * 3)
    @State private var adultos = 2
    @State private var ninos = 0
    @State private var seleccionada: Disponibilidad?
    @State private var mostrarSedes = false

    /// Sedes disponibles para el selector.
    private var sedanActual: Sede? {
        catalogo.sedes.first { $0.id == sedeId } ?? catalogo.sedes.first
    }

    /// Items visibles: resultado de búsqueda si existe, si no el catálogo.
    private var items: [Disponibilidad] {
        if !catalogo.resultados.isEmpty { return catalogo.resultados }
        return catalogo.categorias.map { c in
            Disponibilidad(
                categoriaId: c.id,
                categoriaNombre: c.nombre,
                descripcion: c.descripcion,
                imagenUrl: c.imagenUrl,
                precioDesde: c.precioBase ?? 0,
                habitacionesDisponibles: 0,
                capacidadAdultos: c.capacidadAdultos,
                capacidadNinos: c.capacidadNinos,
                camas: c.camas,
                metrosCuadrados: c.metrosCuadrados)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero

                selectorSede
                buscador

                if !catalogo.resultados.isEmpty {
                    avisoFiltro
                }

                if catalogo.buscando {
                    esqueleto
                } else if items.isEmpty {
                    EstadoVacio(
                        icono: "bed.double",
                        titulo: catalogo.resultados.isEmpty ? "Sin habitaciones" : "Sin disponibilidad",
                        mensaje: catalogo.resultados.isEmpty
                            ? "Esta sede aún no tiene categorías publicadas."
                            : "No quedan habitaciones para esas fechas. Prueba con otras.")
                } else {
                    listado
                }

                if let error = catalogo.error {
                    Aviso(tipo: .peligro, titulo: "Error", mensaje: error)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Tema.fondo.ignoresSafeArea())
        .navigationTitle("Reservar")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await cargarSedes() }
        .task {
            if catalogo.sedes.isEmpty { await cargarSedes() }
        }
        .sheet(item: $seleccionada) { item in
            ConfirmarReservaSheet(item: item, sedeId: sedeId,
                                  checkIn: checkIn, checkOut: checkOut,
                                  adultos: adultos, ninos: ninos) { _ in
                await reservas.cargar()
                seleccionada = nil
            }
        }
    }

    // MARK: - Subvistas

    /// Cabecera de marca: la primera impresión del cliente.
    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TU PRÓXIMA ESTADÍA")
                .font(.caption2.weight(.bold))
                .tracking(1.8)
                .foregroundStyle(.white.opacity(0.65))

            Text("Encuentra tu\nhabitación ideal")
                .font(.title.weight(.bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text("Reserva directa, sin intermediarios.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                LinearGradient(colors: [Tema.azulOscuro, Tema.azul],
                               startPoint: .topLeading,
                               endPoint: .bottomTrailing)

                Circle()
                    .fill(Tema.dorado.opacity(0.18))
                    .frame(width: 160, height: 160)
                    .blur(radius: 40)
                    .offset(x: 130, y: -50)
            }
            .clipShape(RoundedRectangle(cornerRadius: Tema.radio, style: .continuous))
        )
        .shadow(color: Tema.azul.opacity(0.22), radius: 16, x: 0, y: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Encuentra tu habitación ideal. Reserva directa, sin intermediarios.")
    }

    /// Carrusel horizontal de sedes: en vertical ocupaba media pantalla y
    /// empujaba las habitaciones fuera de la vista.
    private var selectorSede: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nuestras sedes")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(catalogo.sedes) { sede in
                        let activa = sede.id == sedeId
                        Button {
                            Task { await elegirSede(sede) }
                        } label: {
                            sedeChip(sede, activa: activa)
                        }
                        .buttonStyle(EstiloPresionable())
                        .accessibilityLabel("\(sede.nombre)"
                                            + (activa ? ", seleccionada" : ""))
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func sedeChip(_ sede: Sede, activa: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                ImagenRemota(ruta: catalogo.fotoSede(sede),
                             iconoRespaldo: "building.2",
                             alto: 96)
                    .frame(width: 190)

                if activa {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.white, Tema.exito)
                        .padding(7)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(sede.nombre)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Tema.texto)
                    .lineLimit(1)

                if let ciudad = sede.ciudad {
                    Label(ciudad, systemImage: "mappin.and.ellipse")
                        .font(.caption2)
                        .foregroundStyle(Tema.textoSecundario)
                        .lineLimit(1)
                }
            }
            .padding(10)
            .frame(width: 190, alignment: .leading)
        }
        .background(Tema.superficie)
        .clipShape(RoundedRectangle(cornerRadius: Tema.radioPequeno,
                                    style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Tema.radioPequeno, style: .continuous)
                .stroke(activa ? Tema.azul : Tema.borde,
                        lineWidth: activa ? 2 : 1))
        .shadow(color: Tema.colorSombra, radius: 10, x: 0, y: 3)
    }

    private var buscador: some View {
        Tarjeta {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("Entrada", systemImage: "arrow.down.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Tema.textoSecundario)
                        DatePicker("", selection: $checkIn,
                                   in: FechaAPI.hoy()..., displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.compact)
                    }

                    Divider().frame(height: 34)

                    VStack(alignment: .leading, spacing: 5) {
                        Label("Salida", systemImage: "arrow.up.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Tema.textoSecundario)
                        DatePicker("", selection: $checkOut,
                                   in: checkIn.addingTimeInterval(86400)...,
                                   displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.compact)
                    }
                }

                HStack(spacing: 10) {
                    contador("Adultos", valor: $adultos, rango: 1...6,
                             icono: "person.fill")
                    contador("Niños", valor: $ninos, rango: 0...4,
                             icono: "figure.child")
                }

                if noches > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "moon.stars.fill")
                            .font(.caption2)
                        Text("\(noches) noche(s) · \(FechaAPI.formatear(checkIn)) → \(FechaAPI.formatear(checkOut))")
                            .font(.caption)
                    }
                    .foregroundStyle(Tema.azul)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                BotonPrincipal(titulo: "Buscar disponibilidad",
                               icono: "magnifyingglass",
                               cargando: catalogo.buscando) {
                    Task { await buscar() }
                }
                .disabled(sedeId == 0)
            }
        }
    }

    /// Contador táctil compacto: reemplaza el `Stepper`, que ocupaba una
    /// fila entera por campo y desalineaba las cifras.
    private func contador(_ titulo: String, valor: Binding<Int>,
                          rango: ClosedRange<Int>, icono: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icono)
                .font(.caption)
                .foregroundStyle(Tema.azul)

            VStack(alignment: .leading, spacing: 0) {
                Text(titulo)
                    .font(.caption2)
                    .foregroundStyle(Tema.textoSecundario)
                Text("\(valor.wrappedValue)")
                    .font(.subheadline.weight(.bold))
                    .contentTransition(.numericText())
            }

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Button {
                    if valor.wrappedValue > rango.lowerBound {
                        valor.wrappedValue -= 1
                    }
                } label: {
                    Image(systemName: "minus")
                        .font(.caption2.weight(.bold))
                        .frame(width: 30, height: 30)
                        .background(Tema.fondo)
                        .foregroundStyle(valor.wrappedValue > rango.lowerBound
                                         ? Tema.azul : Tema.textoSecundario.opacity(0.4))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(valor.wrappedValue <= rango.lowerBound)
                .accessibilityLabel("Quitar \(titulo.lowercased())")

                Button {
                    if valor.wrappedValue < rango.upperBound {
                        valor.wrappedValue += 1
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.caption2.weight(.bold))
                        .frame(width: 30, height: 30)
                        .background(Tema.azul.opacity(0.10))
                        .foregroundStyle(valor.wrappedValue < rango.upperBound
                                         ? Tema.azul : Tema.textoSecundario.opacity(0.4))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(valor.wrappedValue >= rango.upperBound)
                .accessibilityLabel("Añadir \(titulo.lowercased())")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Tema.fondo)
        .clipShape(RoundedRectangle(cornerRadius: Tema.radioPequeno,
                                    style: .continuous))
    }

    private var avisoFiltro: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.subheadline)
                .foregroundStyle(Tema.exito)

            VStack(alignment: .leading, spacing: 2) {
                Text("Disponibles para tus fechas")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Tema.texto)
                Text("\(noches) noche(s) · \(FechaAPI.formatear(checkIn)) → \(FechaAPI.formatear(checkOut))")
                    .font(.caption)
                    .foregroundStyle(Tema.textoSecundario)
            }

            Spacer(minLength: 0)

            Button {
                catalogo.limpiarBusqueda()
            } label: {
                Text("Quitar")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .frame(minHeight: 32)
                    .background(Tema.superficie)
                    .foregroundStyle(Tema.azul)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Quitar filtro de fechas")
        }
        .padding(12)
        .background(Tema.azul.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Tema.radioPequeno,
                                    style: .continuous))
    }

    private var listado: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(catalogo.resultados.isEmpty
                     ? "Conoce nuestras habitaciones"
                     : "Disponibles")
                    .font(.headline)

                if !catalogo.resultados.isEmpty {
                    Text("\(catalogo.resultados.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Tema.exito)
                        .clipShape(Capsule())
                }

                Spacer(minLength: 0)
            }

            ForEach(items) { item in
                categoriaCard(item)
            }
        }
    }

    private func categoriaCard(_ item: Disponibilidad) -> some View {
        let libres = catalogo.resultados.isEmpty ? nil : item.habitacionesDisponibles

        return VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                ImagenRemota(
                    ruta: catalogo.fotoCategoria(item.categoriaNombre, url: item.imagenUrl),
                    iconoRespaldo: iconoCategoria(item.categoriaNombre),
                    alto: 170)

                LinearGradient(colors: [.clear, Color.black.opacity(0.62)],
                               startPoint: .center,
                               endPoint: .bottom)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.categoriaNombre)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if item.capacidadNinos > 0 {
                        Text("\(item.capacidadAdultos) adultos · \(item.capacidadNinos) niños")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    } else {
                        Text("\(item.capacidadAdultos) personas · \(item.camas) cama(s)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)

                if let libres {
                    Text(libres > 0 ? "\(libres) libre(s)" : "Última")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(libres > 0 ? Tema.exito : Tema.alerta)
                        .clipShape(Capsule())
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: .topTrailing)
                }
            }
            .frame(height: 170)
            .frame(maxWidth: .infinity)
            .clipped()

            VStack(alignment: .leading, spacing: 10) {
                if let descripcion = item.descripcion, !descripcion.isEmpty {
                    Text(descripcion)
                        .font(.caption)
                        .foregroundStyle(Tema.textoSecundario)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 14) {
                    Label("\(item.camas) cama(s)", systemImage: "bed.double")
                    if let metros = item.metrosCuadrados {
                        Label("\(Int(metros)) m²", systemImage: "square.dashed")
                    }
                }
                .font(.caption2)
                .foregroundStyle(Tema.textoSecundario)

                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Desde")
                            .font(.caption2)
                            .foregroundStyle(Tema.textoSecundario)
                        HStack(spacing: 2) {
                            Text(Tema.soles(item.precioDesde))
                                .font(.title3.weight(.bold))
                                .foregroundStyle(Tema.azul)
                            Text("/noche")
                                .font(.caption2)
                                .foregroundStyle(Tema.textoSecundario)
                        }
                    }

                    Spacer(minLength: 8)

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        seleccionada = item
                    } label: {
                        HStack(spacing: 6) {
                            Text("Reservar")
                                .font(.subheadline.weight(.semibold))
                            Image(systemName: "arrow.right")
                                .font(.caption2.weight(.bold))
                        }
                        .padding(.horizontal, 18)
                        .frame(minHeight: 44)
                        .background(Tema.azul)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(EstiloPresionable())
                    .accessibilityLabel("Reservar \(item.categoriaNombre)")
                }
            }
            .padding(14)
        }
        .background(Tema.superficie)
        .clipShape(RoundedRectangle(cornerRadius: Tema.radio, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Tema.radio, style: .continuous)
                .stroke(Tema.borde, lineWidth: 1))
        .shadow(color: Tema.colorSombra, radius: 12, x: 0, y: 4)
        .accessibilityElement(children: .contain)
    }

    /// Esqueleto con la forma de la lista: evita el salto al llegar datos.
    private var esqueleto: some View {
        VStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 0) {
                    Rectangle()
                        .fill(Tema.textoSecundario.opacity(0.12))
                        .frame(height: 170)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Categoría de habitación").font(.headline)
                        Text("Descripción de la habitación").font(.caption)
                        Text("S/ 000.00").font(.title3)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Tema.superficie)
                .clipShape(RoundedRectangle(cornerRadius: Tema.radio,
                                            style: .continuous))
            }
        }
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
    }

    // MARK: - Acciones

    private var noches: Int {
        FechaAPI.noches(desde: checkIn, hasta: checkOut)
    }

    private func cargarSedes() async {
        await catalogo.cargarSedes()
        if let primera = catalogo.sedes.first, sedeId == 0 {
            sedeId = primera.id
        }
    }

    private func elegirSede(_ sede: Sede) async {
        sedeId = sede.id
        await catalogo.seleccionar(sedeId: sede.id)
    }

    private func buscar() async {
        guard sedeId != 0 else { return }
        await catalogo.buscar(
            sedeId: sedeId,
            checkIn: FechaAPI.soloFecha(checkIn),
            checkOut: FechaAPI.soloFecha(checkOut))
    }

    private func iconoCategoria(_ nombre: String) -> String {
        let n = nombre.lowercased()
        if n.contains("suite") { return "crown.fill" }
        if n.contains("matrimonial") || n.contains("doble") { return "bed.double.fill" }
        return "bed.double"
    }
}

/// Hoja de confirmación de reserva.
///
/// Recibe las fechas ya elegidas en la búsqueda para no pedirlas dos veces.
struct ConfirmarReservaSheet: View {

    let item: Disponibilidad
    let sedeId: Int
    let alConfirmar: (Reserva) async -> Void

    @Environment(ReservaStore.self) private var reservas
    @Environment(\.dismiss) private var dismiss

    @State private var checkIn: Date
    @State private var checkOut: Date
    @State private var adultos: Int
    @State private var ninos: Int
    @State private var observaciones = ""
    @State private var creando = false
    @State private var error: String?

    init(item: Disponibilidad, sedeId: Int,
         checkIn: Date, checkOut: Date,
         adultos: Int, ninos: Int,
         alConfirmar: @escaping (Reserva) async -> Void) {
        self.item = item
        self.sedeId = sedeId
        self.alConfirmar = alConfirmar

        _checkIn = State(initialValue: checkIn)
        _checkOut = State(initialValue: checkOut)
        _adultos = State(initialValue: min(adultos, max(1, item.capacidadAdultos)))
        _ninos = State(initialValue: min(ninos, max(0, item.capacidadNinos)))
    }

    private var noches: Int { FechaAPI.noches(desde: checkIn, hasta: checkOut) }
    private var total: Decimal { item.precioDesde * Decimal(noches) }
    private var deposito: Decimal { (total * Decimal(string: "0.5")!).rounded(2) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    cabecera

                    Tarjeta {
                        VStack(spacing: 14) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Label("Entrada", systemImage: "arrow.down.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Tema.textoSecundario)
                                    DatePicker("", selection: $checkIn,
                                               in: FechaAPI.hoy()..., displayedComponents: .date)
                                        .labelsHidden()
                                }

                                Divider().frame(height: 34)

                                VStack(alignment: .leading, spacing: 5) {
                                    Label("Salida", systemImage: "arrow.up.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Tema.textoSecundario)
                                    DatePicker("", selection: $checkOut,
                                               in: checkIn.addingTimeInterval(86400)...,
                                               displayedComponents: .date)
                                        .labelsHidden()
                                }
                            }

                            Divider()

                            contador("Adultos", valor: $adultos,
                                     rango: 1...max(1, item.capacidadAdultos),
                                     icono: "person.fill")
                            contador("Niños", valor: $ninos,
                                     rango: 0...max(0, item.capacidadNinos),
                                     icono: "figure.child")

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Observaciones (opcional)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Tema.textoSecundario)
                                TextField("Llegada tarde, cuna, alergias...",
                                          text: $observaciones, axis: .vertical)
                                    .font(.body)
                                    .lineLimit(2...4)
                                    .padding(10)
                                    .background(Tema.fondo)
                                    .clipShape(RoundedRectangle(
                                        cornerRadius: Tema.radioPequeno,
                                        style: .continuous))
                            }
                        }
                    }

                    Tarjeta {
                        VStack(spacing: 10) {
                            fila("\(noches) noche(s) × \(Tema.soles(item.precioDesde))",
                                 Tema.soles(total))
                            Divider()
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Depósito requerido")
                                        .font(.subheadline.weight(.semibold))
                                    Text("50 % del total")
                                        .font(.caption2)
                                        .foregroundStyle(Tema.textoSecundario)
                                }
                                Spacer()
                                Text(Tema.soles(deposito))
                                    .font(.title2.weight(.bold))
                                    .foregroundStyle(Tema.azul)
                            }
                        }
                    }

                    if let error {
                        Aviso(tipo: .peligro, titulo: "No se pudo reservar", mensaje: error)
                    }

                    BotonPrincipal(titulo: "Confirmar reserva", icono: "checkmark",
                                   cargando: creando) {
                        Task { await confirmar() }
                    }

                    Text("Al confirmar se crea la reserva en estado PENDIENTE. "
                         + "Debes pagar el depósito del 50 % para confirmarla.")
                        .font(.caption)
                        .foregroundStyle(Tema.textoSecundario)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
            }
            .background(Tema.fondo.ignoresSafeArea())
            .navigationTitle("Confirmar reserva")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var cabecera: some View {
        ZStack(alignment: .bottomLeading) {
            ImagenRemota(ruta: item.imagenUrl, iconoRespaldo: icono, alto: 150)

            LinearGradient(colors: [.clear, Color.black.opacity(0.60)],
                           startPoint: .center, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.categoriaNombre)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("\(Tema.soles(item.precioDesde)) por noche")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 150)
        .frame(maxWidth: .infinity)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: Tema.radio, style: .continuous))
        .shadow(color: Tema.colorSombra, radius: 12, x: 0, y: 4)
    }

    /// Contador táctil de huéspedes, coherente con el de la búsqueda.
    private func contador(_ titulo: String, valor: Binding<Int>,
                          rango: ClosedRange<Int>, icono: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icono)
                .font(.caption)
                .foregroundStyle(Tema.azul)

            Text(titulo)
                .font(.subheadline)
                .foregroundStyle(Tema.texto)

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Button {
                    if valor.wrappedValue > rango.lowerBound {
                        valor.wrappedValue -= 1
                    }
                } label: {
                    Image(systemName: "minus")
                        .font(.caption2.weight(.bold))
                        .frame(width: 30, height: 30)
                        .background(Tema.azulClaro)
                        .foregroundStyle(valor.wrappedValue > rango.lowerBound
                                         ? Tema.azul : Tema.textoSecundario.opacity(0.4))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(valor.wrappedValue <= rango.lowerBound)
                .accessibilityLabel("Quitar \(titulo.lowercased())")

                Text("\(valor.wrappedValue)")
                    .font(.subheadline.weight(.bold))
                    .frame(minWidth: 18)
                    .contentTransition(.numericText())

                Button {
                    if valor.wrappedValue < rango.upperBound {
                        valor.wrappedValue += 1
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.caption2.weight(.bold))
                        .frame(width: 30, height: 30)
                        .background(Tema.azul.opacity(0.12))
                        .foregroundStyle(valor.wrappedValue < rango.upperBound
                                         ? Tema.azul : Tema.textoSecundario.opacity(0.4))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(valor.wrappedValue >= rango.upperBound)
                .accessibilityLabel("Añadir \(titulo.lowercased())")
            }
        }
    }

    private var icono: String {
        let n = item.categoriaNombre.lowercased()
        if n.contains("suite") { return "crown.fill" }
        if n.contains("matrimonial") || n.contains("doble") { return "bed.double.fill" }
        return "bed.double"
    }

    private func fila(_ etiqueta: String, _ valor: String) -> some View {
        HStack {
            Text(etiqueta)
                .font(.subheadline)
                .foregroundStyle(Tema.textoSecundario)
            Spacer()
            Text(valor).font(.subheadline.weight(.medium))
        }
    }

    private func confirmar() async {
        guard !creando else { return }
        creando = true
        error = nil

        do {
            let reserva = try await reservas.crear(
                sedeId: sedeId,
                categoriaId: item.categoriaId,
                checkIn: FechaAPI.soloFecha(checkIn),
                checkOut: FechaAPI.soloFecha(checkOut),
                adultos: adultos,
                ninos: ninos,
                observaciones: observaciones.isEmpty ? nil : observaciones)

            await alConfirmar(reserva)
            dismiss()
        } catch let apiError as APIError {
            error = apiError.mensajeUsuario
        } catch {
            self.error = "No se pudo crear la reserva."
        }

        creando = false
    }
}

extension Decimal {
    /// Redondea a la cantidad de decimales indicada.
    func rounded(_ scale: Int) -> Decimal {
        var entrada = self
        var salida = Decimal()
        NSDecimalRound(&salida, &entrada, scale, .plain)
        return salida
    }
}
