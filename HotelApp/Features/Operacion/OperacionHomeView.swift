import SwiftUI

/// Home de operación: KPIs, llegadas/salidas del día, pagos por verificar y
/// accesos rápidos.
///
/// Jerarquía visual (de arriba abajo):
///  1. Cabecera: quién eres y en qué sede estás.
///  2. Métrica protagonista: ocupación (el dato que se mira primero).
///  3. Tres métricas secundarias en una sola fila.
///  4. Alertas accionables (pagos por verificar, limpieza pendiente).
///  5. Accesos rápidos.
///  6. Movimiento del día (llegadas y salidas).
///
/// Housekeeping tiene un home reducido (tareas + habitaciones): su rol no
/// tiene permiso sobre `/reportes/dashboard`, `/reservas` ni
/// `/pagos/pendientes`, y pedirlos devolvía 403 en bucle.
struct OperacionHomeView: View {

    let usuario: Usuario

    @Environment(OperacionStore.self) private var operacion

    @State private var sedeId: Int?
    @State private var mostrandoWalkIn = false

    /// Rol operativo del panel (admin, gerente, recepción).
    private var esPanelCompleto: Bool { usuario.puedeOperar }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                cabecera

                if !esPanelCompleto {
                    homeHousekeeping
                } else if operacion.cargando && operacion.dashboard == nil {
                    ProgressView().padding(.top, 60)
                } else if let dashboard = operacion.dashboard {
                    contenido(dashboard)
                } else {
                    Aviso(tipo: .peligro, titulo: "Sin datos",
                          mensaje: operacion.error ?? "No se pudo cargar el panel.")
                }

                if let error = operacion.error, operacion.dashboard != nil {
                    Aviso(tipo: .alerta, titulo: "Aviso", mensaje: error)
                }

                if let errorPagos = operacion.errorPagos, esPanelCompleto {
                    Aviso(tipo: .alerta, titulo: "Pagos pendientes",
                          mensaje: errorPagos)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Tema.fondo.ignoresSafeArea())
        .navigationTitle("Panel")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await cargar() }
        .task { await cargar() }
        .sheet(isPresented: $mostrandoWalkIn) {
            if let sede = sedeId ?? usuario.sedePrincipal?.id {
                WalkInView(sedeId: sede)
            }
        }
    }

    // MARK: - Contenido principal

    @ViewBuilder
    private func contenido(_ d: Dashboard) -> some View {
        heroOcupacion(d)

        // 2x2: las cuatro cifras del dashboard web, con espacio suficiente
        // para los importes. En fila de tres, "S/ 5,553.00" se cortaba.
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10)],
                  spacing: 10) {
            metrica("Llegadas", "\(d.llegadasHoy)",
                    "arrow.down.right", Tema.exito, pie: "check-in de hoy")
            metrica("Salidas", "\(d.salidasHoy)",
                    "arrow.up.right", Tema.info, pie: "check-out de hoy")
            metrica("Por cobrar", Tema.soles(d.cuentasPorCobrar),
                    "banknote", Tema.alerta,
                    pie: "\(d.reservasPendientes) reserva(s) pendiente(s)")
            metrica("Ingresos del mes", Tema.soles(d.ingresosMes),
                    "chart.line.uptrend.xyaxis", Tema.exito,
                    pie: "mes en curso")
        }

        alertas()
        accesos
        movimientoDelDia
    }

    // MARK: - Cabecera

    private var cabecera: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(saludoTexto)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Tema.texto)
                    Text(usuario.nombresRol.first?.capitalized ?? "Operación")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Tema.azul)
                }
                Spacer()
            }

            selectorSede
        }
        .padding(.top, 8)
    }

    private var saludoTexto: String {
        let nombre = usuario.nombre.split(separator: " ").first.map(String.init) ?? ""
        return nombre.isEmpty ? "Hola" : "Hola, \(nombre)"
    }

    /// Admin y gerente alternan entre sedes; recepción queda en la suya.
    @ViewBuilder
    private var selectorSede: some View {
        if usuario.puedeVerReportes && usuario.sedes.count > 1 {
            Menu {
                ForEach(usuario.sedes) { sede in
                    Button {
                        guard sede.id != (sedeId ?? usuario.sedePrincipal?.id) else { return }
                        sedeId = sede.id
                        Task { await cargar() }
                    } label: {
                        if sede.id == (sedeId ?? usuario.sedePrincipal?.id) {
                            Label(sede.nombre, systemImage: "checkmark")
                        } else {
                            Text(sede.nombre)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "building.2.fill")
                        .font(.system(size: 11))
                    Text(sedeActual?.nombre ?? "Sede")
                        .font(.system(size: 13, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(Tema.azul)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Tema.azulClaro)
                .clipShape(Capsule())
            }
        } else if let sede = sedeActual {
            HStack(spacing: 6) {
                Image(systemName: "building.2.fill")
                    .font(.system(size: 11))
                Text(sede.nombre)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Tema.textoSecundario)
        }
    }

    private var sedeActual: Sede? {
        guard let id = sedeId else { return usuario.sedePrincipal }
        return usuario.sedes.first { $0.id == id } ?? usuario.sedePrincipal
    }

    // MARK: - Hero: ocupación

    /// Tarjeta oscura de marca con el KPI principal y barra de progreso.
    private func heroOcupacion(_ d: Dashboard) -> some View {
        let proporcion = min(max(d.porcentajeOcupacion / 100, 0), 1)
        let ocupadas = d.habitacionesOcupadas
        let total = d.totalHabitaciones

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("OCUPACIÓN")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Image(systemName: "bed.double.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.45))
            }

            Text("\(Int(d.porcentajeOcupacion))%")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.16))
                    Capsule()
                        .fill(Tema.dorado)
                        .frame(width: max(6, geo.size.width * proporcion))
                }
            }
            .frame(height: 6)

            Text("\(ocupadas) de \(total) habitaciones ocupadas")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.65))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Tema.azulOscuro, Tema.azul],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: Tema.radio, style: .continuous))
    }

    // MARK: - Métricas secundarias

    /// Tarjeta de métrica secundaria. El pie explica el número sin repetir el
    /// título, que es lo que hacía parecer duplicado el bloque de KPIs.
    private func metrica(_ titulo: String, _ valor: String,
                         _ icono: String, _ color: Color,
                         pie: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icono)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                Text(titulo.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(Tema.textoSecundario)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            Text(valor)
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .foregroundStyle(Tema.texto)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            if let pie {
                Text(pie)
                    .font(.system(size: 10))
                    .foregroundStyle(Tema.textoSecundario)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.superficie)
        .clipShape(RoundedRectangle(cornerRadius: Tema.radioPequeno,
                                    style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Tema.radioPequeno, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1))
    }

    // MARK: - Alertas accionables

    /// Solo aparece lo que requiere una acción. Si no hay nada pendiente, la
    /// sección no se muestra (antes se repetían los mismos números del bloque
    /// de KPIs, que es lo que se veía duplicado).
    @ViewBuilder
    private func alertas() -> some View {
        let hayPagos = !operacion.pagosPendientes.isEmpty
        let hayLimpieza = !operacion.tareasPendientes.isEmpty

        if hayPagos || hayLimpieza {
            VStack(alignment: .leading, spacing: 10) {
                Text("Requiere atención")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Tema.texto)

                if hayPagos {
                    navegacion(alertaPagos) { PagosPendientesView() }
                }

                if hayLimpieza {
                    navegacion(alertaLimpieza) { TareasView() }
                }
            }
        }
    }

    private var alertaPagos: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Tema.alerta.opacity(0.14)).frame(width: 36, height: 36)
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Tema.alerta)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("\(operacion.pagosPendientes.count) pago(s) por verificar")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Tema.texto)
                Text(Tema.soles(montoPendiente))
                    .font(.system(size: 11))
                    .foregroundStyle(Tema.textoSecundario)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Tema.textoSecundario.opacity(0.6))
        }
        .padding(14)
        .background(Tema.superficie)
        .clipShape(RoundedRectangle(cornerRadius: Tema.radioPequeno,
                                    style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Tema.radioPequeno, style: .continuous)
                .stroke(Tema.alerta.opacity(0.22), lineWidth: 1))
    }

    private var alertaLimpieza: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Tema.info.opacity(0.12)).frame(width: 36, height: 36)
                Image(systemName: "sparkles")
                    .font(.system(size: 14))
                    .foregroundStyle(Tema.info)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("\(operacion.tareasPendientes.count) tarea(s) de limpieza")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Tema.texto)
                Text("Habitaciones esperando limpieza")
                    .font(.system(size: 11))
                    .foregroundStyle(Tema.textoSecundario)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Tema.textoSecundario.opacity(0.6))
        }
        .padding(14)
        .background(Tema.superficie)
        .clipShape(RoundedRectangle(cornerRadius: Tema.radioPequeno,
                                    style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Tema.radioPequeno, style: .continuous)
                .stroke(Tema.info.opacity(0.18), lineWidth: 1))
    }

    private var montoPendiente: Decimal {
        operacion.pagosPendientes.reduce(Decimal.zero) { $0 + $1.monto }
    }

    /// Envuelve una tarjeta en NavigationLink conservando el estilo propio.
    private func navegacion<Destino: View>(
        _ contenido: some View,
        @ViewBuilder destino: () -> Destino
    ) -> some View {
        NavigationLink { destino() } label: {
            contenido.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Accesos rápidos

    private var accesos: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Accesos rápidos")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Tema.texto)

            // Grid de 2 columnas: se ve todo sin scroll horizontal, que
            // ocultaba accesos sin ninguna pista visual.
            //
            // No se repiten aquí "Habitaciones" ni "Tareas": ya son pestañas
            // fijas del tab bar. Duplicarlas era parte de lo que se veía
            // redundante.
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10)],
                      spacing: 10) {
                if esPanelCompleto {
                    Button {
                        mostrandoWalkIn = true
                    } label: {
                        atajo("Nuevo huésped", "person.badge.plus", Tema.exito)
                    }
                    .buttonStyle(.plain)

                    NavigationLink { CheckInQrView() } label: {
                        atajo("Check-in QR", "qrcode.viewfinder", Tema.azulOscuro)
                    }
                    .buttonStyle(.plain)

                    NavigationLink { PagosPendientesView() } label: {
                        atajo("Verificar pagos", "creditcard", Tema.alerta)
                    }
                    .buttonStyle(.plain)

                    NavigationLink { SolicitudesRecepcionView() } label: {
                        atajo("Servicio hab.", "bell.badge.fill", Tema.dorado)
                    }
                    .buttonStyle(.plain)
                }

                if usuario.puedeVerReportes {
                    NavigationLink { ReportesView() } label: {
                        atajo("Reportes", "chart.bar.fill", Tema.azul)
                    }
                    .buttonStyle(.plain)
                }

                NavigationLink { NotificacionesView() } label: {
                    atajo("Notificaciones", "bell.fill", Tema.peligro)
                }
                .buttonStyle(.plain)
            }

            // Administración: antes solo se llegaba desde Perfil, lo que hacía
            // el "acceso total" poco descubrible desde el panel.
            if usuario.esAdmin {
                Text("Administración")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Tema.texto)
                    .padding(.top, 6)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                    GridItem(.flexible(), spacing: 10)],
                          spacing: 10) {
                    NavigationLink { UsuariosAdminView() } label: {
                        atajo("Usuarios", "person.2.badge.gearshape",
                              Tema.azulOscuro)
                    }
                    .buttonStyle(.plain)

                    NavigationLink { SedesAdminView() } label: {
                        atajo("Sedes", "building.2", Tema.dorado)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func atajo(_ titulo: String, _ icono: String, _ color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icono)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 26)

            Text(titulo)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Tema.texto)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(Tema.superficie)
        .clipShape(RoundedRectangle(cornerRadius: Tema.radioPequeno,
                                    style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Tema.radioPequeno, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1))
    }

    // MARK: - Movimiento del día

    /// Llegadas y salidas. Con listas vacías no se dibuja la tarjeta: antes
    /// aparecía un título "Llegadas de hoy" sin contenido.
    @ViewBuilder
    private var movimientoDelDia: some View {
        let hay = !operacion.llegadas.isEmpty || !operacion.salidas.isEmpty

        if hay {
            VStack(alignment: .leading, spacing: 10) {
                Text("Movimiento de hoy")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Tema.texto)

                if !operacion.llegadas.isEmpty {
                    grupo("Llegadas", "arrow.down.right", Tema.exito,
                          reservas: operacion.llegadas)
                }

                if !operacion.salidas.isEmpty {
                    grupo("Salidas", "arrow.up.right", Tema.info,
                          reservas: operacion.salidas)
                }
            }
        }
    }

    private func grupo(_ titulo: String, _ icono: String, _ color: Color,
                       reservas: [ReservaResumen]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: icono)
                    .font(.system(size: 10, weight: .bold))
                Text(titulo.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                Spacer()
                Text("\(reservas.count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(color)
            }
            .foregroundStyle(color)
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ForEach(Array(reservas.enumerated()), id: \.element.id) { indice, r in
                NavigationLink {
                    DetalleReservaOperacionView(reservaId: r.id)
                } label: {
                    filaReserva(r)
                }
                .buttonStyle(.plain)

                if indice < reservas.count - 1 {
                    Divider().padding(.leading, 14)
                }
            }
        }
        .background(Tema.superficie)
        .clipShape(RoundedRectangle(cornerRadius: Tema.radioPequeno,
                                    style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Tema.radioPequeno, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1))
    }

    private func filaReserva(_ r: ReservaResumen) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(r.huespedNombre)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Tema.texto)
                Text(r.codigo)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Tema.textoSecundario)
            }

            Spacer()

            Text(Tema.soles(r.montoTotal))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Tema.texto)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Tema.textoSecundario.opacity(0.5))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    // MARK: - Home de housekeeping

    @ViewBuilder
    private var homeHousekeeping: some View {
        if operacion.cargando && operacion.tareasPendientes.isEmpty {
            ProgressView().padding(.top, 60)
        } else {
            VStack(alignment: .leading, spacing: 20) {
                Tarjeta {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Tareas pendientes")
                                .font(.system(size: 11))
                                .foregroundStyle(Tema.textoSecundario)
                            Text("\(operacion.tareasPendientes.count)")
                                .font(.system(size: 30, weight: .bold,
                                              design: .rounded))
                                .foregroundStyle(Tema.azul)
                        }
                        Spacer()
                        Image(systemName: "sparkles")
                            .font(.system(size: 24))
                            .foregroundStyle(Tema.info)
                    }
                }

                // Housekeeping ya tiene Habitaciones y Tareas en el tab bar:
                // repetirlas aquí era parte de la redundancia. Solo se deja el
                // acceso a notificaciones, que no está en ninguna pestaña.
                NavigationLink { NotificacionesView() } label: {
                    Tarjeta(padding: 14) {
                        HStack(spacing: 10) {
                            Image(systemName: "bell.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Tema.peligro)
                                .frame(width: 26)
                            Text("Notificaciones")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Tema.texto)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Tema.textoSecundario.opacity(0.5))
                        }
                    }
                }
                .buttonStyle(.plain)

                if operacion.tareasPendientes.isEmpty {
                    EstadoVacio(icono: "checkmark.seal",
                                titulo: "Sin tareas pendientes",
                                mensaje: "No hay habitaciones asignadas por limpiar.")
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Mis tareas")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Tema.texto)

                        ForEach(operacion.tareasPendientes) { t in
                            Tarjeta(padding: 12) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Habitación \(t.habitacionNumero)")
                                            .font(.system(size: 13, weight: .medium))
                                        Text(t.tipo)
                                            .font(.system(size: 10))
                                            .foregroundStyle(Tema.textoSecundario)
                                    }
                                    Spacer()
                                    if t.urgente {
                                        EtiquetaEstado(
                                            texto: "Urgente",
                                            color: Tema.peligro,
                                            icono: "exclamationmark.triangle.fill")
                                    }
                                }
                            }
                        }
                    }
                }

                if let error = operacion.error {
                    Aviso(tipo: .alerta, titulo: "Aviso", mensaje: error)
                }
            }
        }
    }

    // MARK: - Carga

    private func cargar() async {
        let sede = sedeId ?? usuario.sedePrincipal?.id

        // Housekeeping puro: sin dashboard, sin reservas y sin pagos.
        guard esPanelCompleto else {
            await operacion.cargarTareasPendientes()
            return
        }

        await operacion.cargarDashboard(sedeId: sede)
        await operacion.cargarPagosPendientes()
        await operacion.cargarTareasPendientesOperacion()
    }
}
