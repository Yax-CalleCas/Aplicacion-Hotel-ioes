import SwiftUI

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
                encabezado
                selectorSede
                buscador

                if !catalogo.resultados.isEmpty {
                    avisoFiltro
                }

                if catalogo.buscando {
                    ProgressView("Buscando disponibilidad...")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 30)
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
            .padding(16)
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

    private var encabezado: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Encuentra tu habitación")
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text("Reserva directa, sin intermediarios.")
                .font(.system(size: 13))
                .foregroundStyle(Tema.textoSecundario)
        }
    }

    private var selectorSede: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nuestras sedes")
                .font(.system(size: 13, weight: .semibold))

            ForEach(catalogo.sedes) { sede in
                Button {
                    Task { await elegirSede(sede) }
                } label: {
                    Tarjeta(padding: 0) {
                        VStack(alignment: .leading, spacing: 10) {
                            ImagenRemota(ruta: catalogo.fotoSede(sede),
                                         iconoRespaldo: "building.2",
                                         alto: 120)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(sede.nombre)
                                        .font(.system(size: 15, weight: .semibold))
                                    Spacer()
                                    if sede.id == sedeId {
                                        EtiquetaEstado(texto: "Seleccionada",
                                                       color: Tema.exito,
                                                       icono: "checkmark")
                                    }
                                }

                                if let direccion = sede.direccion {
                                    Label(direccion, systemImage: "mappin.and.ellipse")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Tema.textoSecundario)
                                }

                                Text("Check-in \(sede.checkInCorto) · Check-out \(sede.checkOutCorto)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Tema.textoSecundario)
                            }
                            .padding(.horizontal, 14)
                            .padding(.bottom, 14)
                        }
                    }
                }
                .buttonStyle(.plain)
                .overlay(
                    RoundedRectangle(cornerRadius: Tema.radio, style: .continuous)
                        .stroke(sede.id == sedeId ? Tema.azul : .clear, lineWidth: 2))
            }
        }
    }

    private var buscador: some View {
        Tarjeta {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Entrada").font(.system(size: 11, weight: .semibold))
                        DatePicker("", selection: $checkIn,
                                   in: FechaAPI.hoy()..., displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.compact)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Salida").font(.system(size: 11, weight: .semibold))
                        DatePicker("", selection: $checkOut,
                                   in: checkIn.addingTimeInterval(86400)...,
                                   displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.compact)
                    }
                }

                HStack(spacing: 12) {
                    Stepper("Adultos: \(adultos)", value: $adultos, in: 1...6)
                        .font(.system(size: 12))
                    Stepper("Niños: \(ninos)", value: $ninos, in: 0...4)
                        .font(.system(size: 12))
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

    private var avisoFiltro: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Disponibles para tus fechas")
                    .font(.system(size: 13, weight: .semibold))
                Text("\(noches) noche(s) · \(FechaAPI.formatear(checkIn)) → \(FechaAPI.formatear(checkOut))")
                    .font(.system(size: 11))
                    .foregroundStyle(Tema.textoSecundario)
            }
            Spacer()
            Button("Quitar filtro") {
                catalogo.limpiarBusqueda()
            }
            .font(.system(size: 11, weight: .semibold))
        }
        .padding(12)
        .background(Tema.azulClaro)
        .clipShape(RoundedRectangle(cornerRadius: Tema.radioPequeno))
    }

    private var listado: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(catalogo.resultados.isEmpty
                 ? "Conoce nuestras habitaciones"
                 : "\(catalogo.resultados.count) categoría(s) disponible(s)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Tema.textoSecundario)

            ForEach(items) { item in
                categoriaCard(item)
            }
        }
    }

    private func categoriaCard(_ item: Disponibilidad) -> some View {
        Tarjeta(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                ImagenRemota(
                    ruta: catalogo.fotoCategoria(item.categoriaNombre, url: item.imagenUrl),
                    iconoRespaldo: iconoCategoria(item.categoriaNombre),
                    alto: 160)
                    .overlay(alignment: .topTrailing) {
                        if !catalogo.resultados.isEmpty {
                            EtiquetaEstado(
                                texto: "\(item.habitacionesDisponibles) libre(s)",
                                color: Tema.exito,
                                icono: "bed.double.fill")
                            .padding(8)
                        }
                    }

                VStack(alignment: .leading, spacing: 10) {
                    Text(item.categoriaNombre)
                        .font(.system(size: 17, weight: .semibold))

                    if let descripcion = item.descripcion, !descripcion.isEmpty {
                        Text(descripcion)
                            .font(.system(size: 11))
                            .foregroundStyle(Tema.textoSecundario)
                            .lineLimit(2)
                    }

                    HStack(spacing: 10) {
                        Label("\(item.capacidadAdultos) adultos", systemImage: "person.2")
                        if item.capacidadNinos > 0 {
                            Label("\(item.capacidadNinos) niños", systemImage: "figure.child")
                        }
                        Label("\(item.camas) cama(s)", systemImage: "bed.double")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(Tema.textoSecundario)

                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Desde").font(.system(size: 9)).foregroundStyle(Tema.textoSecundario)
                            Text("\(Tema.soles(item.precioDesde)) / noche")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Tema.azul)
                        }
                        Spacer()
                        Button {
                            seleccionada = item
                        } label: {
                            Text("Reservar")
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 9)
                                .background(Tema.azul)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 9))
                        }
                    }
                }
                .padding(14)
            }
        }
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
                    Tarjeta(padding: 0) {
                        VStack(alignment: .leading, spacing: 0) {
                            ImagenRemota(
                                ruta: item.imagenUrl,
                                iconoRespaldo: icono,
                                alto: 140)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.categoriaNombre)
                                    .font(.system(size: 18, weight: .semibold))
                                Text("\(Tema.soles(item.precioDesde)) por noche")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Tema.textoSecundario)
                            }
                            .padding(14)
                        }
                    }

                    Tarjeta {
                        VStack(spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Entrada").font(.system(size: 11, weight: .semibold))
                                    DatePicker("", selection: $checkIn,
                                               in: FechaAPI.hoy()..., displayedComponents: .date)
                                        .labelsHidden()
                                }
                                Spacer()
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Salida").font(.system(size: 11, weight: .semibold))
                                    DatePicker("", selection: $checkOut,
                                               in: checkIn.addingTimeInterval(86400)...,
                                               displayedComponents: .date)
                                        .labelsHidden()
                                }
                            }

                            Stepper("Adultos: \(adultos)", value: $adultos,
                                    in: 1...max(1, item.capacidadAdultos))
                                .font(.system(size: 13))
                            Stepper("Niños: \(ninos)", value: $ninos,
                                    in: 0...max(0, item.capacidadNinos))
                                .font(.system(size: 13))

                            VStack(alignment: .leading, spacing: 5) {
                                Text("Observaciones (opcional)")
                                    .font(.system(size: 11, weight: .semibold))
                                TextField("Llegada tarde, cuna, alergias...",
                                          text: $observaciones, axis: .vertical)
                                    .lineLimit(2...4)
                                    .padding(10)
                                    .background(Tema.fondo)
                                    .clipShape(RoundedRectangle(cornerRadius: 9))
                            }
                        }
                    }

                    Tarjeta {
                        VStack(spacing: 8) {
                            fila("\(noches) noche(s) × \(Tema.soles(item.precioDesde))",
                                 Tema.soles(total))
                            Divider()
                            HStack {
                                Text("Depósito requerido (50 %)")
                                    .font(.system(size: 13, weight: .semibold))
                                Spacer()
                                Text(Tema.soles(deposito))
                                    .font(.system(size: 20, weight: .bold))
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

                    Text("Al confirmar se crea la reserva en estado PENDIENTE. Debes pagar el depósito del 50 % para confirmarla.")
                        .font(.system(size: 11))
                        .foregroundStyle(Tema.textoSecundario)
                        .multilineTextAlignment(.center)
                }
                .padding(16)
            }
            .background(Tema.fondo.ignoresSafeArea())
            .navigationTitle("Confirmar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
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
                .font(.system(size: 12))
                .foregroundStyle(Tema.textoSecundario)
            Spacer()
            Text(valor).font(.system(size: 13, weight: .medium))
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
