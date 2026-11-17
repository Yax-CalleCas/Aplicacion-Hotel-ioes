import SwiftUI

/// Home de operación: KPIs, llegadas/salidas del día, pagos por verificar y
/// accesos rápidos.
///
/// Jerarquía visual (de arriba abajo):
///  1. Cabecera: saludo, avatar y selector de sede.
///  2. Hero: ocupación con anillo de progreso y el pulso del día.
///  3. Cuatro métricas en una cuadrícula 2x2.
///  4. Alertas accionables (pagos por verificar, limpieza pendiente).
///  5. Accesos rápidos (iconos grandes, tres columnas).
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
    @State private var animarAnillo = false

    /// Rol operativo del panel (admin, gerente, recepción).
    private var esPanelCompleto: Bool { usuario.puedeOperar }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                cabecera
                    .padding(.top, 6)

                if !esPanelCompleto {
                    homeHousekeeping
                } else if operacion.cargando && operacion.dashboard == nil {
                    esqueletoCarga
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
            .padding(.horizontal, 18)
            .padding(.bottom, 32)
        }
        .background(fondoPanel)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .refreshable { await cargar() }
        .task { await cargar() }
        .sheet(isPresented: $mostrandoWalkIn) {
            if let sede = sedeId ?? usuario.sedePrincipal?.id {
                WalkInView(sedeId: sede)
            }
        }
    }

    // MARK: - Fondo

    /// Fondo claro con halos de color: da profundidad sin competir con el
    /// contenido, y hace que las tarjetas blancas floten.
    private var fondoPanel: some View {
        ZStack {
            LinearGradient(
                colors: [Tema.azulClaro.opacity(0.75),
                         Tema.fondo,
                         Tema.fondo],
                startPoint: .top,
                endPoint: .bottom)

            Circle()
                .fill(Tema.azul.opacity(0.10))
                .frame(width: 260, height: 260)
                .blur(radius: 70)
                .offset(x: 140, y: -220)

            Circle()
                .fill(Tema.dorado.opacity(0.10))
                .frame(width: 220, height: 220)
                .blur(radius: 80)
                .offset(x: -150, y: 330)
        }
        .ignoresSafeArea()
    }

    // MARK: - Contenido principal

    @ViewBuilder
    private func contenido(_ d: Dashboard) -> some View {
        heroOcupacion(d)

        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)],
                  spacing: 12) {
            metrica("Por cobrar", Tema.soles(d.cuentasPorCobrar),
                    "banknote.fill", Tema.alerta,
                    pie: "\(d.reservasPendientes) reserva(s) pendiente(s)")
            metrica("Ingresos del mes", Tema.soles(d.ingresosMes),
                    "chart.line.uptrend.xyaxis", Tema.exito,
                    pie: "mes en curso")
            metrica("Habitaciones libres", "\(max(0, d.totalHabitaciones - d.habitacionesOcupadas))",
                    "door.left.hand.open", Tema.azul,
                    pie: "de \(d.totalHabitaciones) en total")
            metrica("Limpieza", "\(d.tareasPendientes)",
                    "sparkles", Tema.info,
                    pie: "tarea(s) pendiente(s)")
        }

        alertas()
        ocupacionPorSede(d)
        accesos
        movimientoDelDia
    }

    // MARK: - Ocupación por sede

    /// Comparativa rápida entre sedes. Solo se dibuja si el backend devuelve
    /// más de una: con una sola sede repetiría el hero.
    @ViewBuilder
    private func ocupacionPorSede(_ d: Dashboard) -> some View {
        if d.porSede.count > 1 {
            VStack(alignment: .leading, spacing: 10) {
                tituloSeccion("Ocupación por sede", "building.2.fill", Tema.azul)

                VStack(spacing: 12) {
                    ForEach(d.porSede, id: \.sedeId) { sede in
                        VStack(spacing: 6) {
                            HStack(spacing: 6) {
                                Text(sede.sedeNombre)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Tema.texto)
                                    .lineLimit(1)

                                Spacer(minLength: 0)

                                Text("\(sede.ocupadas)/\(sede.habitaciones)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Tema.textoSecundario)
                                Text("\(Int(sede.porcentaje))%")
                                    .font(.system(size: 11, weight: .bold,
                                                  design: .rounded))
                                    .foregroundStyle(colorOcupacion(sede.porcentaje))
                            }

                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Tema.fondo)
                                    Capsule()
                                        .fill(colorOcupacion(sede.porcentaje))
                                        .frame(width: max(6,
                                            geo.size.width * CGFloat(min(max(sede.porcentaje / 100, 0), 1))))
                                }
                            }
                            .frame(height: 6)
                        }
                    }
                }
                .padding(14)
                .background(Tema.superficie)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Tema.borde, lineWidth: 1))
                .shadow(color: Tema.sombra.opacity(0.55), radius: 8, x: 0, y: 3)
            }
        }
    }

    /// Semáforo de ocupación: alta demanda en dorado, media en azul y baja en
    /// verde, para leer la salud del hotel de un vistazo.
    private func colorOcupacion(_ porcentaje: Double) -> Color {
        if porcentaje >= 80 { return Tema.dorado }
        if porcentaje >= 45 { return Tema.azul }
        return Tema.exito
    }

    // MARK: - Cabecera

    private var cabecera: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                avatar

                VStack(alignment: .leading, spacing: 3) {
                    Text(saludoTexto)
                        .font(.system(size: 21, weight: .bold,
                                      design: .rounded))
                        .foregroundStyle(Tema.texto)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(Tema.exito)
                            .frame(width: 6, height: 6)
                        Text((usuario.nombresRol.first ?? "Operación").capitalized)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Tema.textoSecundario)
                    }
                }

                Spacer(minLength: 0)

                NavigationLink { NotificacionesView() } label: {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Tema.azul)
                        .frame(width: 42, height: 42)
                        .background(Tema.superficie)
                        .clipShape(Circle())
                        .shadow(color: Tema.sombra, radius: 8, x: 0, y: 3)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                selectorSede

                Spacer(minLength: 0)

                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                        .font(.system(size: 10, weight: .semibold))
                    Text(fechaCorta)
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Tema.textoSecundario)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Tema.superficie.opacity(0.9))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Tema.borde, lineWidth: 1))
            }
        }
    }

    /// Fecha de hoy en formato corto ("lun 16 nov"), solo presentación.
    private var fechaCorta: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_PE")
        formatter.dateFormat = "EEE d MMM"
        return formatter.string(from: Date()).replacingOccurrences(of: ".", with: "")
    }

    /// Avatar del usuario: foto si existe y, si no, iniciales sobre el
    /// degradado de marca.
    private var avatar: some View {
        ZStack {
            Tema.degradadoMarca

            if let url = AppConfig.imagenURL(usuario.fotoUrl) {
                AsyncImage(url: url) { fase in
                    if let imagen = fase.image {
                        imagen.resizable().scaledToFill()
                    } else {
                        inicialesAvatar
                    }
                }
            } else {
                inicialesAvatar
            }
        }
        .frame(width: 46, height: 46)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white, lineWidth: 2))
        .shadow(color: Tema.azul.opacity(0.28), radius: 10, x: 0, y: 5)
    }

    private var inicialesAvatar: some View {
        Text(usuario.iniciales.isEmpty
             ? String(usuario.nombre.prefix(1)).uppercased()
             : usuario.iniciales)
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
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
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 11, weight: .semibold))
                    Text(sedeActual?.nombre ?? "Sede")
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(Tema.azul)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Tema.superficie)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Tema.azul.opacity(0.14), lineWidth: 1))
                .shadow(color: Tema.sombra.opacity(0.6), radius: 6, x: 0, y: 2)
            }
        } else if let sede = sedeActual {
            HStack(spacing: 5) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 10, weight: .semibold))
                Text(sede.nombre)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(Tema.textoSecundario)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Tema.superficie.opacity(0.85))
            .clipShape(Capsule())
        }
    }

    private var sedeActual: Sede? {
        guard let id = sedeId else { return usuario.sedePrincipal }
        return usuario.sedes.first { $0.id == id } ?? usuario.sedePrincipal
    }

    // MARK: - Hero: ocupación

    /// Tarjeta de marca con el KPI principal en anillo de progreso y el
    /// pulso del día (llegadas/salidas) integrado abajo.
    private func heroOcupacion(_ d: Dashboard) -> some View {
        let proporcion = CGFloat(min(max(d.porcentajeOcupacion / 100, 0), 1))
        let ocupadas = d.habitacionesOcupadas
        let total = d.totalHabitaciones

        return VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 18) {
                anillo(proporcion: animarAnillo ? proporcion : 0,
                       porcentaje: d.porcentajeOcupacion)
                    .frame(width: 108, height: 108)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "bed.double.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text("OCUPACIÓN HOY")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.4)
                    }
                    .foregroundStyle(.white.opacity(0.62))

                    Text("\(ocupadas) de \(total)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text("habitaciones ocupadas")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(2)

                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.forward.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("\(total - ocupadas) libres")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Tema.dorado.opacity(0.95))
                    .padding(.top, 2)
                }

                Spacer(minLength: 0)
            }

            Rectangle()
                .fill(.white.opacity(0.10))
                .frame(height: 1)

            HStack(spacing: 0) {
                pulso("arrow.down.right", "Llegadas", "\(d.llegadasHoy)",
                      Tema.dorado)

                Rectangle()
                    .fill(.white.opacity(0.10))
                    .frame(width: 1, height: 30)

                pulso("arrow.up.right", "Salidas", "\(d.salidasHoy)",
                      .white.opacity(0.85))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                Tema.degradadoMarca

                Circle()
                    .fill(.white.opacity(0.07))
                    .frame(width: 180, height: 180)
                    .offset(x: 130, y: -80)

                Circle()
                    .fill(Tema.dorado.opacity(0.16))
                    .frame(width: 140, height: 140)
                    .blur(radius: 26)
                    .offset(x: -120, y: 100)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1))
        .shadow(color: Tema.azul.opacity(0.30), radius: 18, x: 0, y: 10)
        .onAppear {
            withAnimation(.easeOut(duration: 0.9)) { animarAnillo = true }
        }
        .onChange(of: d.porcentajeOcupacion) { _, _ in
            animarAnillo = false
            withAnimation(.easeOut(duration: 0.9)) { animarAnillo = true }
        }
    }

    /// Anillo de ocupación: pista translúcida + arco dorado degradado.
    private func anillo(proporcion: CGFloat, porcentaje: Double) -> some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.14), lineWidth: 11)

            Circle()
                .trim(from: 0, to: max(0.001, proporcion))
                .stroke(
                    AngularGradient(
                        colors: [Tema.dorado.opacity(0.65),
                                 Color(red: 0.98, green: 0.83, blue: 0.47),
                                 Tema.dorado],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)),
                    style: StrokeStyle(lineWidth: 11, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: -2) {
                Text("\(Int(porcentaje))")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("%")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    private func pulso(_ icono: String, _ titulo: String, _ valor: String,
                       _ color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icono)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(.white.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 0) {
                Text(titulo)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.60))
                Text(valor)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Métricas secundarias

    /// Tarjeta de métrica. Icono en pastilla de color, cifra grande y pie que
    /// contextualiza el número.
    private func metrica(_ titulo: String, _ valor: String,
                         _ icono: String, _ color: Color,
                         pie: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icono)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 30, height: 30)
                    .background(color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 9,
                                                style: .continuous))

                Spacer(minLength: 0)

                Circle()
                    .fill(color.opacity(0.16))
                    .frame(width: 7, height: 7)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(valor)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Tema.texto)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                Text(titulo)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Tema.textoSecundario)
                    .lineLimit(1)

                if let pie {
                    Text(pie)
                        .font(.system(size: 9))
                        .foregroundStyle(Tema.textoSecundario.opacity(0.75))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.superficie)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Tema.borde, lineWidth: 1))
        .shadow(color: Tema.sombra.opacity(0.55), radius: 8, x: 0, y: 3)
    }

    // MARK: - Alertas accionables

    /// Solo aparece lo que requiere una acción. Si no hay nada pendiente, la
    /// sección no se muestra.
    @ViewBuilder
    private func alertas() -> some View {
        let hayPagos = !operacion.pagosPendientes.isEmpty
        let hayLimpieza = !operacion.tareasPendientes.isEmpty

        if hayPagos || hayLimpieza {
            VStack(alignment: .leading, spacing: 10) {
                tituloSeccion("Requiere atención", "exclamationmark.circle.fill",
                              Tema.alerta)

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
        tarjetaAlerta(
            icono: "creditcard.fill",
            titulo: "\(operacion.pagosPendientes.count) pago(s) por verificar",
            detalle: Tema.soles(montoPendiente),
            color: Tema.alerta)
    }

    private var alertaLimpieza: some View {
        tarjetaAlerta(
            icono: "sparkles",
            titulo: "\(operacion.tareasPendientes.count) tarea(s) de limpieza",
            detalle: "Habitaciones esperando limpieza",
            color: Tema.info)
    }

    private func tarjetaAlerta(icono: String, titulo: String, detalle: String,
                               color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icono)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(
                    LinearGradient(colors: [color.opacity(0.85), color],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing))
                .clipShape(RoundedRectangle(cornerRadius: 12,
                                            style: .continuous))
                .shadow(color: color.opacity(0.30), radius: 8, x: 0, y: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(titulo)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Tema.texto)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(detalle)
                    .font(.system(size: 11))
                    .foregroundStyle(Tema.textoSecundario)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.12))
                .clipShape(Circle())
        }
        .padding(12)
        .background(Tema.superficie)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(color.opacity(0.18), lineWidth: 1))
        .shadow(color: color.opacity(0.10), radius: 8, x: 0, y: 3)
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
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Tema.textoSecundario)
                    .padding(.top, 6)

                NavigationLink { SedesAdminView() } label: {
                    HStack(spacing: 14) {
                        RoundedRectangle(cornerRadius: Tema.radioPequeno,
                                         style: .continuous)
                            .fill(Tema.dorado.opacity(0.15))
                            .frame(width: 42, height: 42)
                            .overlay(
                                Image(systemName: "building.2.fill")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(Tema.dorado))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sedes y fotos")
                                .font(.headline)
                                .foregroundStyle(Tema.texto)
                            Text("Gestiona fotos y datos de cada sede")
                                .font(.caption)
                                .foregroundStyle(Tema.textoSecundario)
                        }

                        Spacer(minLength: 8)

                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Tema.textoSecundario.opacity(0.6))
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Tema.superficie)
                    .clipShape(RoundedRectangle(cornerRadius: Tema.radio,
                                                style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Tema.radio,
                                         style: .continuous)
                            .stroke(Tema.borde, lineWidth: 1))
                    .shadow(color: Tema.colorSombra, radius: 12, x: 0, y: 4)
                }
                               .buttonStyle(EstiloPresionable())
                .accessibilityLabel("Sedes y fotos. Gestiona fotos y datos de cada sede")
            }          // cierra if usuario.esAdmin
        }              // cierra el VStack de accesos
    }                  // cierra la var accesos

    /// Atajo vertical: icono grande en placa de color y etiqueta debajo.
    private func atajo(_ titulo: String, _ icono: String, _ color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icono)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 14,
                                            style: .continuous))

            Text(titulo)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Tema.texto)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(height: 26, alignment: .top)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .background(Tema.superficie)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Tema.borde, lineWidth: 1))
        .shadow(color: Tema.sombra.opacity(0.55), radius: 8, x: 0, y: 3)
    }

    /// Atajo horizontal ancho, para la fila de administración.
    private func atajoAncho(_ titulo: String, _ icono: String,
                            _ color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icono)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 11,
                                            style: .continuous))

            Text(titulo)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Tema.texto)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Tema.superficie)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Tema.borde, lineWidth: 1))
        .shadow(color: Tema.sombra.opacity(0.55), radius: 8, x: 0, y: 3)
    }

    private func tituloSeccion(_ texto: String, _ icono: String,
                               _ color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icono)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
            Text(texto)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Tema.texto)
        }
    }

    // MARK: - Movimiento del día

    /// Llegadas y salidas. Con listas vacías no se dibuja la tarjeta.
    @ViewBuilder
    private var movimientoDelDia: some View {
        let hay = !operacion.llegadas.isEmpty || !operacion.salidas.isEmpty

        if hay {
            VStack(alignment: .leading, spacing: 10) {
                tituloSeccion("Movimiento de hoy", "clock.fill", Tema.azul)

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
            HStack(spacing: 7) {
                Image(systemName: icono)
                    .font(.system(size: 10, weight: .bold))
                Text(titulo.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                Spacer()
                Text("\(reservas.count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(color)
                    .clipShape(Capsule())
            }
            .foregroundStyle(color)
            .padding(.horizontal, 14)
            .padding(.top, 13)
            .padding(.bottom, 9)

            ForEach(Array(reservas.enumerated()), id: \.element.id) { indice, r in
                NavigationLink {
                    DetalleReservaOperacionView(reservaId: r.id)
                } label: {
                    filaReserva(r, color: color)
                }
                .buttonStyle(.plain)

                if indice < reservas.count - 1 {
                    Divider()
                        .padding(.leading, 60)
                        .opacity(0.6)
                }
            }
        }
        .padding(.bottom, 4)
        .background(Tema.superficie)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Tema.borde, lineWidth: 1))
        .shadow(color: Tema.sombra.opacity(0.55), radius: 8, x: 0, y: 3)
    }

    private func filaReserva(_ r: ReservaResumen, color: Color) -> some View {
        HStack(spacing: 11) {
            Text(inicialesDe(r.huespedNombre))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .frame(width: 34, height: 34)
                .background(color.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(r.huespedNombre)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Tema.texto)
                    .lineLimit(1)
                Text(r.codigo)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Tema.textoSecundario)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                Text(Tema.soles(r.montoTotal))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Tema.texto)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Tema.textoSecundario.opacity(0.40))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    private func inicialesDe(_ nombre: String) -> String {
        let letras = nombre.split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
            .uppercased()
        return letras.isEmpty ? "?" : letras
    }

    // MARK: - Esqueleto de carga

    /// Placeholder con las mismas siluetas del contenido: la pantalla no
    /// "salta" cuando llegan los datos.
    private var esqueletoCarga: some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Tema.superficie.opacity(0.7))
                .frame(height: 196)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)],
                      spacing: 12) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Tema.superficie.opacity(0.7))
                        .frame(height: 108)
                }
            }

            ProgressView()
                .tint(Tema.azul)
                .padding(.top, 4)
        }
    }

    // MARK: - Home de housekeeping

    @ViewBuilder
    private var homeHousekeeping: some View {
        if operacion.cargando && operacion.tareasPendientes.isEmpty {
            esqueletoCarga
        } else {
            VStack(alignment: .leading, spacing: 18) {
                tarjetaTareas

                NavigationLink { NotificacionesView() } label: {
                    tarjetaAlerta(icono: "bell.fill", titulo: "Notificaciones",
                                  detalle: "Avisos de tus habitaciones asignadas",
                                  color: Tema.peligro)
                }
                .buttonStyle(.plain)

                if operacion.tareasPendientes.isEmpty {
                    EstadoVacio(icono: "checkmark.seal.fill",
                                titulo: "Sin tareas pendientes",
                                mensaje: "No hay habitaciones asignadas por limpiar.")
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        tituloSeccion("Mis tareas", "sparkles", Tema.info)

                        ForEach(operacion.tareasPendientes) { t in
                            Tarjeta(padding: 12) {
                                HStack(spacing: 11) {
                                    Text(t.habitacionNumero)
                                        .font(.system(size: 14, weight: .bold,
                                                      design: .rounded))
                                        .foregroundStyle(Tema.info)
                                        .frame(width: 40, height: 40)
                                        .background(Tema.info.opacity(0.12))
                                        .clipShape(RoundedRectangle(cornerRadius: 12,
                                                                    style: .continuous))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Habitación \(t.habitacionNumero)")
                                            .font(.system(size: 13, weight: .semibold))
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

    private var tarjetaTareas: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.12))
                Circle()
                    .stroke(.white.opacity(0.22), lineWidth: 1.5)
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Tema.dorado)
            }
            .frame(width: 62, height: 62)

            VStack(alignment: .leading, spacing: 3) {
                Text("TAREAS PENDIENTES")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.60))
                Text("\(operacion.tareasPendientes.count)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("habitaciones por limpiar")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.62))
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.degradadoMarca)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Tema.azul.opacity(0.28), radius: 16, x: 0, y: 8)
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
