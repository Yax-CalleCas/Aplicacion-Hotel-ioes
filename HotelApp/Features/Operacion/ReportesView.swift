import SwiftUI

/// Reportes de gestión: KPIs, ocupación diaria e ingresos.
///
/// Solo visible para ADMIN y GERENTE (`/reportes/kpis` está restringido).
struct ReportesView: View {

    @Environment(SesionStore.self) private var sesion

    @State private var sedeId = 0
    @State private var desde = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var hasta = Date()

    @State private var kpi: Kpi?
    @State private var ocupacion: ReporteOcupacion?
    @State private var porCategoria: [IngresoPorCategoria] = []
    @State private var porConcepto: [IngresoPorConcepto] = []

    @State private var cargando = false
    @State private var error: String?

    private let api = HotelAPI.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                filtros

                if cargando {
                    ProgressView().padding(.top, 40)
                } else if let kpi {
                    tarjetaKpis(kpi)

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
            .padding(16)
        }
        .background(Tema.fondo.ignoresSafeArea())
        .navigationTitle("Reportes")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if sedeId == 0 {
                sedeId = sesion.sedePrincipal?.id ?? sesion.usuario?.sedes.first?.id ?? 0
            }
            await cargar()
        }
    }

    // MARK: - Subvistas

    private var filtros: some View {
        Tarjeta {
            VStack(spacing: 12) {
                if let sedes = sesion.usuario?.sedes, sedes.count > 1 {
                    Picker("Sede", selection: $sedeId) {
                        ForEach(sedes) { sede in
                            Text(sede.nombre).tag(sede.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Desde").font(.system(size: 11, weight: .semibold))
                        DatePicker("", selection: $desde,
                                   in: ...hasta, displayedComponents: .date)
                            .labelsHidden()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hasta").font(.system(size: 11, weight: .semibold))
                        DatePicker("", selection: $hasta,
                                   in: desde..., displayedComponents: .date)
                            .labelsHidden()
                    }
                }

                BotonPrincipal(titulo: "Consultar", icono: "chart.bar",
                               cargando: cargando) {
                    Task { await cargar() }
                }
                .disabled(sedeId == 0)
            }
        }
    }

    private func tarjetaKpis(_ k: Kpi) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                metrica("Ocupación", "\(Int(k.porcentajeOcupacion))%", Tema.azul)
                metrica("ADR", Tema.soles(k.adr), Tema.exito)
            }
            HStack(spacing: 10) {
                metrica("RevPAR", Tema.soles(k.revpar), Tema.info)
                metrica("Ingresos", Tema.soles(k.ingresos), Tema.alerta)
            }

            Tarjeta {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Habitaciones ocupadas").font(.system(size: 10))
                            .foregroundStyle(Tema.textoSecundario)
                        Text("\(k.habitacionesOcupadas)")
                            .font(.system(size: 20, weight: .bold))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Disponibles").font(.system(size: 10))
                            .foregroundStyle(Tema.textoSecundario)
                        Text("\(k.habitacionesDisponibles)")
                            .font(.system(size: 20, weight: .bold))
                    }
                }
            }
        }
    }

    private func metrica(_ titulo: String, _ valor: String, _ color: Color) -> some View {
        Tarjeta {
            VStack(alignment: .leading, spacing: 4) {
                Text(titulo)
                    .font(.system(size: 10))
                    .foregroundStyle(Tema.textoSecundario)
                Text(valor)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
    }

    private func tarjetaOcupacion(_ r: ReporteOcupacion) -> some View {
        Tarjeta {
            VStack(alignment: .leading, spacing: 10) {
                Text("Ocupación diaria")
                    .font(.system(size: 13, weight: .semibold))

                ForEach(r.dias) { dia in
                    HStack(spacing: 10) {
                        Text(FechaAPI.formatear(FechaAPI.parsear(dia.fecha)))
                            .font(.system(size: 10))
                            .foregroundStyle(Tema.textoSecundario)
                            .frame(width: 90, alignment: .leading)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Tema.fondo)
                                Capsule()
                                    .fill(Tema.azul.opacity(0.75))
                                    .frame(width: max(2, geo.size.width * dia.porcentaje / 100))
                            }
                        }
                        .frame(height: 6)

                        Text("\(Int(dia.porcentaje))%")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 34, alignment: .trailing)
                    }
                }
            }
        }
    }

    private var tarjetaCategorias: some View {
        Tarjeta {
            VStack(alignment: .leading, spacing: 8) {
                Text("Ingresos por categoría")
                    .font(.system(size: 13, weight: .semibold))

                ForEach(porCategoria) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.categoriaNombre)
                                .font(.system(size: 11, weight: .medium))
                            Text("\(item.reservas) reserva(s)")
                                .font(.system(size: 9))
                                .foregroundStyle(Tema.textoSecundario)
                        }
                        Spacer()
                        Text(Tema.soles(item.ingresos))
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
            }
        }
    }

    private var tarjetaConceptos: some View {
        Tarjeta {
            VStack(alignment: .leading, spacing: 8) {
                Text("Ingresos por concepto")
                    .font(.system(size: 13, weight: .semibold))

                ForEach(porConcepto) { item in
                    HStack {
                        Text(item.concepto.capitalized)
                            .font(.system(size: 11))
                        Spacer()
                        Text(Tema.soles(item.monto))
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
            }
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
