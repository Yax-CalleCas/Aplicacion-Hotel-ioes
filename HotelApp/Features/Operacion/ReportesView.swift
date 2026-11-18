import SwiftUI

/// Reportes de gestión: KPIs, ocupación diaria e ingresos.
///
/// Solo visible para ADMIN y GERENTE (`/reportes/kpis` está restringido).
///
/// Jerarquía pensada para leerse de pie y con prisa: primero el KPI
/// protagonista, luego las cifras de apoyo, después el detalle. El rango de
/// fechas vive en una hoja para no robar espacio a los datos.
struct ReportesView: View {

    @Environment(SesionStore.self) private var sesion
    @Environment(SedeActivaStore.self) private var sedeActiva

    @State private var sedeId = 0
    @State private var desde = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var hasta = Date()

    @State private var kpi: Kpi?
    @State private var ocupacion: ReporteOcupacion?
    @State private var porCategoria: [IngresoPorCategoria] = []
    @State private var porConcepto: [IngresoPorConcepto] = []

    @State private var cargando = false
    @State private var error: String?
    @State private var mostrarRango = false

    private let api = HotelAPI.shared

    private var usuario: Usuario? { sesion.usuario }

    /// Suma de ingresos del desglose por concepto, para la barra de
    /// participación. Sin esto habría que dividir por `kpi.ingresos`, que
    /// puede incluir conceptos no listados.
    private var totalConceptos: Decimal {
        porConcepto.reduce(Decimal.zero) { $0 + $1.monto }
    }

    private var maximoCategoria: Decimal {
        porCategoria.map(\.ingresos).max() ?? 1
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                cabecera

                if cargando && kpi == nil {
                    esqueleto
                } else if let kpi {
                    heroOcupacion(kpi)
                    metricasApoyo(kpi)

                    if let ocupacion, !ocupacion.dias.isEmpty {
                        tarjetaOcupacion(ocupacion)
                    }

                    if !porCategoria.isEmpty {
                        tarjetaCategorias
                    }

                    if !porConcepto.isEmpty {
                        tarjetaConceptos
                    }
                } else {
                    EstadoVacio(icono: "chart.bar",
                                titulo: "Sin datos",
                                mensaje: error ?? "Ajusta el rango de fechas y vuelve a consultar.")
                }

                if let error, kpi != nil {
                    Aviso(tipo: .alerta, titulo: "Aviso", mensaje: error)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Tema.fondo.ignoresSafeArea())
        .navigationTitle("Reportes")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if sedeId == 0 {
                if let usuario {
                    sedeId = sedeActiva.idEfectivo(para: usuario) ?? 0
                }
            }
            if kpi == nil { await cargar() }
        }
        .sheet(isPresented: $mostrarRango) {
            RangoFechasSheet(desde: $desde, hasta: $hasta) {
                Task { await cargar() }
            }
        }
    }

    // MARK: - Cabecera

    private var cabecera: some View {
        HStack(spacing: 10) {
            if let sedes = usuario?.sedes, sedes.count > 1 {
                Menu {
                    ForEach(sedes) { sede in
                        Button {
                            guard sede.id != sedeId else { return }
                            sedeId = sede.id
                            Task { await cargar() }
                        } label: {
                            if sede.id == sedeId {
                                Label(sede.nombre, systemImage: "checkmark")
                            } else {
                                Text(sede.nombre)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "building.2.fill")
                            .font(.caption)
                        Text(nombreSede)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(Tema.azul)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 38)
                    .background(Tema.superficie)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Tema.borde, lineWidth: 1))
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "building.2.fill").font(.caption)
                    Text(nombreSede)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(Tema.textoSecundario)
            }

            Spacer(minLength: 0)

            Button {
                mostrarRango = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar").font(.caption)
                    Text(rangoCorto).font(.caption.weight(.semibold))
                }
                .foregroundStyle(Tema.azul)
                .padding(.horizontal, 12)
                .frame(minHeight: 38)
                .background(Tema.azul.opacity(0.10))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cambiar rango de fechas")
        }
    }

    private var nombreSede: String {
        usuario?.sedes.first { $0.id == sedeId }?.nombre ?? "Sede"
    }

    private var rangoCorto: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_PE")
        f.dateFormat = "d MMM"
        return "\(f.string(from: desde)) – \(f.string(from: hasta))"
    }

    // MARK: - Hero

    /// Tarjeta de marca con la ocupación, que es el dato que se mira primero.
    private func heroOcupacion(_ k: Kpi) -> some View {
        let proporcion = min(max(k.porcentajeOcupacion / 100, 0), 1)

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("OCUPACIÓN")
                    .font(.caption2.weight(.bold))
                    .tracking(1.6)
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Image(systemName: "bed.double.fill")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.45))
            }

            Text("\(Int(k.porcentajeOcupacion))%")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.16))
                    Capsule()
                        .fill(Tema.dorado)
                        .frame(width: max(6, geo.size.width * proporcion))
                }
            }
            .frame(height: 6)

            HStack(spacing: 16) {
                Label("\(k.habitacionesOcupadas) ocupadas", systemImage: "person.fill")
                Label("\(k.habitacionesDisponibles) libres", systemImage: "door.left.hand.open")
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.7))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Tema.azulOscuro, Tema.azul],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: Tema.radio, style: .continuous))
        .shadow(color: Tema.azul.opacity(0.25), radius: 16, x: 0, y: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ocupación \(Int(k.porcentajeOcupacion)) por ciento, "
                            + "\(k.habitacionesOcupadas) de "
                            + "\(k.habitacionesOcupadas + k.habitacionesDisponibles) habitaciones")
    }

    // MARK: - Métricas de apoyo

    private func metricasApoyo(_ k: Kpi) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10)],
                  spacing: 10) {
            metrica("ADR", Tema.soles(k.adr), "tag.fill", Tema.exito,
                    pie: "tarifa media")
            metrica("RevPAR", Tema.soles(k.revpar), "chart.line.uptrend.xyaxis", Tema.info,
                    pie: "por habitación")
            metrica("Ingresos", Tema.soles(k.ingresos), "banknote.fill", Tema.alerta,
                    pie: "en el periodo")
            metrica("Reservas", "\(porCategoria.reduce(0) { $0 + $1.reservas })",
                    "calendar.badge.checkmark", Tema.azul,
                    pie: "confirmadas")
        }
    }

    private func metrica(_ titulo: String, _ valor: String, _ icono: String,
                         _ color: Color, pie: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icono)
                    .font(.caption)
                    .foregroundStyle(color)
                    .frame(width: 26, height: 26)
                    .background(color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text(titulo.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(Tema.textoSecundario)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }

            Text(valor)
                .font(.title3.weight(.bold))
                .foregroundStyle(Tema.texto)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Text(pie)
                .font(.caption2)
                .foregroundStyle(Tema.textoSecundario)
                .lineLimit(1)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.superficie)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Tema.borde, lineWidth: 1))
        .shadow(color: Tema.colorSombra, radius: 10, x: 0, y: 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(titulo): \(valor), \(pie)")
    }

    // MARK: - Ocupación diaria

    private func tarjetaOcupacion(_ r: ReporteOcupacion) -> some View {
        // Solo los últimos 14 días: con 30 barras la tarjeta no cabe y el
        // detalle diario deja de leerse.
        let dias = Array(r.dias.suffix(14))
        let maximo = max(dias.map(\.porcentaje).max() ?? 100, 1)

        return Tarjeta {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Ocupación diaria")
                        .font(.headline)
                    Spacer()
                    Text("últimos \(dias.count) días")
                        .font(.caption2)
                        .foregroundStyle(Tema.textoSecundario)
                }

                VStack(spacing: 8) {
                    ForEach(dias) { dia in
                        HStack(spacing: 10) {
                            Text(fechaCorta(dia.fecha))
                                .font(.caption2)
                                .foregroundStyle(Tema.textoSecundario)
                                .frame(width: 46, alignment: .leading)

                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Tema.fondo)
                                    Capsule()
                                        .fill(colorOcupacion(dia.porcentaje))
                                        .frame(width: max(3,
                                            geo.size.width * CGFloat(dia.porcentaje / maximo)))
                                }
                            }
                            .frame(height: 7)

                            Text("\(Int(dia.porcentaje))%")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Tema.texto)
                                .frame(width: 34, alignment: .trailing)
                                .monospacedDigit()
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(fechaCorta(dia.fecha)): "
                                            + "\(Int(dia.porcentaje)) por ciento")
                    }
                }
            }
        }
    }

    private func colorOcupacion(_ porcentaje: Double) -> Color {
        if porcentaje >= 80 { return Tema.exito }
        if porcentaje >= 45 { return Tema.azul }
        return Tema.alerta
    }

    private func fechaCorta(_ texto: String) -> String {
        guard let fecha = FechaAPI.parsear(texto) else { return texto }
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_PE")
        f.dateFormat = "d MMM"
        return f.string(from: fecha)
    }

    // MARK: - Ingresos por categoría

    private var tarjetaCategorias: some View {
        Tarjeta {
            VStack(alignment: .leading, spacing: 12) {
                Text("Ingresos por categoría")
                    .font(.headline)

                VStack(spacing: 12) {
                    ForEach(porCategoria) { item in
                        VStack(spacing: 5) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(item.categoriaNombre)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Tema.texto)
                                    .lineLimit(1)

                                Text("\(item.reservas) res.")
                                    .font(.caption2)
                                    .foregroundStyle(Tema.textoSecundario)

                                Spacer(minLength: 0)

                                Text(Tema.soles(item.ingresos))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Tema.texto)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }

                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Tema.fondo)
                                    Capsule()
                                        .fill(Tema.azul)
                                        .frame(width: max(4,
                                            geo.size.width * proporcion(item.ingresos)))
                                }
                            }
                            .frame(height: 5)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(item.categoriaNombre): "
                                            + "\(Tema.soles(item.ingresos)), "
                                            + "\(item.reservas) reservas")
                    }
                }
            }
        }
    }

    private func proporcion(_ valor: Decimal) -> CGFloat {
        guard maximoCategoria > 0 else { return 0 }
        let ratio = NSDecimalNumber(decimal: valor).doubleValue
            / NSDecimalNumber(decimal: maximoCategoria).doubleValue
        return CGFloat(min(max(ratio, 0), 1))
    }

    // MARK: - Ingresos por concepto

    private var tarjetaConceptos: some View {
        Tarjeta {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Ingresos por concepto")
                        .font(.headline)
                    Spacer()
                    Text(Tema.soles(totalConceptos))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Tema.exito)
                }

                VStack(spacing: 10) {
                    ForEach(porConcepto) { item in
                        HStack(spacing: 10) {
                            Image(systemName: iconoConcepto(item.concepto))
                                .font(.caption)
                                .foregroundStyle(Tema.info)
                                .frame(width: 24, height: 24)
                                .background(Tema.info.opacity(0.10))
                                .clipShape(Circle())

                            Text(item.concepto.capitalized)
                                .font(.subheadline)
                                .foregroundStyle(Tema.texto)
                                .lineLimit(1)

                            Spacer(minLength: 0)

                            Text(Tema.soles(item.monto))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Tema.texto)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(item.concepto): \(Tema.soles(item.monto))")
                    }
                }
            }
        }
    }

    private func iconoConcepto(_ concepto: String) -> String {
        switch concepto.uppercased() {
        case "ALOJAMIENTO": return "bed.double.fill"
        case "SERVICIO_HABITACION", "SERVICIOS": return "bell.fill"
        case "RESTAURANTE": return "fork.knife"
        case "PENALIDAD", "PENALIDADES": return "exclamationmark.triangle.fill"
        default: return "creditcard.fill"
        }
    }

    // MARK: - Esqueleto

    private var esqueleto: some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: Tema.radio, style: .continuous)
                .fill(Tema.superficie)
                .frame(height: 190)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10)],
                      spacing: 10) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Tema.superficie)
                        .frame(height: 100)
                }
            }
        }
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .overlay(alignment: .bottom) {
            ProgressView().tint(Tema.azul)
        }
    }

    // MARK: - Acciones

    private func cargar() async {
        guard sedeId != 0 else { return }
        cargando = true
        error = nil

        let d = FechaAPI.soloFecha(desde)
        let h = FechaAPI.soloFecha(hasta)

        do {
            kpi = try await api.kpis(sedeId: sedeId, desde: d, hasta: h)
            ocupacion = try? await api.ocupacion(sedeId: sedeId, desde: d, hasta: h)
            porCategoria = (try? await api.ingresosPorCategoria(sedeId: sedeId,
                                                                desde: d, hasta: h)) ?? []
            porConcepto = (try? await api.ingresosPorConcepto(sedeId: sedeId,
                                                              desde: d, hasta: h)) ?? []
        } catch let apiError as APIError {
            error = apiError.mensajeUsuario
        } catch {
            self.error = "No se pudieron cargar los reportes."
        }

        cargando = false
    }
}

// MARK: - Rango de fechas

/// Selector de rango en hoja aparte, con atajos para los periodos que más
/// se consultan. Evita que el formulario ocupe media pantalla en la vista
/// principal.
struct RangoFechasSheet: View {

    @Binding var desde: Date
    @Binding var hasta: Date

    let alAplicar: () -> Void

    @Environment(\.dismiss) private var dismiss

    private struct Atajo: Identifiable {
        let id: String
        let titulo: String
        let dias: Int
    }

    private let atajos: [Atajo] = [
        Atajo(id: "hoy", titulo: "Hoy", dias: 0),
        Atajo(id: "7", titulo: "Últimos 7 días", dias: 7),
        Atajo(id: "30", titulo: "Últimos 30 días", dias: 30),
        Atajo(id: "90", titulo: "Últimos 90 días", dias: 90),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Tarjeta {
                        VStack(spacing: 14) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Desde")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Tema.textoSecundario)
                                    DatePicker("", selection: $desde,
                                               in: ...hasta, displayedComponents: .date)
                                        .labelsHidden()
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("Hasta")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Tema.textoSecundario)
                                    DatePicker("", selection: $hasta,
                                               in: desde..., displayedComponents: .date)
                                        .labelsHidden()
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Periodos frecuentes")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Tema.textoSecundario)
                            .padding(.leading, 4)

                        ForEach(atajos) { atajo in
                            Button {
                                aplicar(atajo.dias)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .font(.subheadline)
                                        .foregroundStyle(Tema.azul)

                                    Text(atajo.titulo)
                                        .font(.subheadline)
                                        .foregroundStyle(Tema.texto)

                                    Spacer(minLength: 0)

                                    Image(systemName: "chevron.right")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(Tema.textoSecundario.opacity(0.6))
                                }
                                .padding(.horizontal, 14)
                                .frame(minHeight: 44)
                                .background(Tema.superficie)
                                .clipShape(RoundedRectangle(
                                    cornerRadius: Tema.radioPequeno,
                                    style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Tema.radioPequeno,
                                                     style: .continuous)
                                        .stroke(Tema.borde, lineWidth: 1))
                            }
                            .buttonStyle(EstiloPresionable())
                        }
                    }

                    BotonPrincipal(titulo: "Consultar", icono: "chart.bar") {
                        alAplicar()
                        dismiss()
                    }
                }
                .padding(16)
            }
            .background(Tema.fondo.ignoresSafeArea())
            .navigationTitle("Periodo")
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

    private func aplicar(_ dias: Int) {
        hasta = Date()
        desde = Calendar.current.date(byAdding: .day, value: -dias, to: Date()) ?? Date()
        alAplicar()
        dismiss()
    }
}
