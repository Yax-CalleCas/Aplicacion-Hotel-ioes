import SwiftUI
import UIKit

/// Mis reservas (cliente).
///
/// Incluye búsqueda por código y detalle con folio completo.
struct MisReservasView: View {

    @Environment(ReservaStore.self) private var reservas

    @State private var codigo = ""
    @State private var buscandoCodigo = false
    @State private var reservaEncontrada: Reserva?
    @State private var irADetalle = false
    @State private var errorCodigo: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                buscadorCodigo

                if reservas.desdeCache {
                    Aviso(tipo: .alerta, titulo: "Sin conexión",
                          mensaje: "Mostrando reservas guardadas en el dispositivo.")
                }

                if reservas.cargando && reservas.reservas.isEmpty {
                    ProgressView("Cargando reservas...").padding(.top, 40)
                } else if reservas.reservas.isEmpty {
                    EstadoVacio(icono: "calendar",
                                titulo: "Sin reservas",
                                mensaje: "Busca disponibilidad y reserva tu primera estadía.")
                } else {
                    ForEach(reservas.reservas) { r in
                        NavigationLink {
                            DetalleReservaView(reservaId: r.id)
                        } label: {
                            tarjeta(r)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
        }
        .background(Tema.fondo.ignoresSafeArea())
        .navigationTitle("Mis reservas")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reservas.cargar() }
        .task {
            if reservas.reservas.isEmpty { await reservas.cargar() }
        }
        .navigationDestination(isPresented: $irADetalle) {
            if let reservaEncontrada {
                DetalleReservaView(reservaId: reservaEncontrada.id)
            }
        }
    }

    // MARK: - Subvistas

    private var buscadorCodigo: some View {
        Tarjeta {
            VStack(alignment: .leading, spacing: 8) {
                Text("Buscar por código")
                    .font(.system(size: 12, weight: .semibold))

                HStack(spacing: 8) {
                    TextField("RES-2026-00001", text: $codigo)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(size: 13, design: .monospaced))
                        .padding(10)
                        .background(Tema.fondo)
                        .clipShape(RoundedRectangle(cornerRadius: 9))

                    Button {
                        Task { await buscarPorCodigo() }
                    } label: {
                        if buscandoCodigo {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "magnifyingglass")
                        }
                    }
                    .frame(width: 44, height: 40)
                    .background(Tema.azul)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .disabled(codigo.trimmingCharacters(in: .whitespaces).isEmpty || buscandoCodigo)
                }

                if let errorCodigo {
                    Text(errorCodigo)
                        .font(.system(size: 11))
                        .foregroundStyle(Tema.peligro)
                }
            }
        }
    }

    private func tarjeta(_ r: ReservaResumen) -> some View {
        let estado = Etiquetas.estadoReserva(r.estado)

        return Tarjeta {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(r.codigo)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    Spacer()
                    EtiquetaEstado(texto: estado.texto, color: estado.color)
                }

                // El cliente debe saber en la lista si le falta pagar, si su
                // pago esta en revision o si ya esta todo en orden.
                if r.estado == "PENDIENTE" {
                    HStack(spacing: 6) {
                        Image(systemName: r.pagoEnRevision
                              ? "clock.arrow.circlepath" : "exclamationmark.circle")
                            .font(.system(size: 10))
                        Text(r.pagoEnRevision
                             ? "Pago en revisión por recepción"
                             : "Falta el depósito del 50 %")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(r.pagoEnRevision ? Tema.info : Tema.alerta)
                }

                HStack {
                    Label(FechaAPI.formatear(FechaAPI.parsear(r.checkIn)),
                          systemImage: "calendar")
                        .font(.system(size: 11))
                        .foregroundStyle(Tema.textoSecundario)
                    Text("→").foregroundStyle(Tema.textoSecundario)
                    Text(FechaAPI.formatear(FechaAPI.parsear(r.checkOut)))
                        .font(.system(size: 11))
                        .foregroundStyle(Tema.textoSecundario)
                }

                HStack {
                    Text(r.huespedNombre)
                        .font(.system(size: 12))
                        .foregroundStyle(Tema.textoSecundario)
                    Spacer()
                    Text(Tema.soles(r.montoTotal))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Tema.azul)
                }
            }
        }
    }

    // MARK: - Acciones

    private func buscarPorCodigo() async {
        let limpio = codigo.trimmingCharacters(in: .whitespaces).uppercased()
        guard !limpio.isEmpty else { return }

        buscandoCodigo = true
        errorCodigo = nil

        do {
            reservaEncontrada = try await reservas.obtener(codigo: limpio)
            irADetalle = true
        } catch let apiError as APIError {
            errorCodigo = apiError.status == 404
                ? "No existe una reserva con ese código."
                : apiError.mensajeUsuario
        } catch {
            errorCodigo = "No se pudo buscar la reserva."
        }

        buscandoCodigo = false
    }
}

/// Detalle de reserva con folio, cargos y pago del depósito.
struct DetalleReservaView: View {

    let reservaId: Int

    @Environment(ReservaStore.self) private var reservas
    @Environment(SesionStore.self) private var sesion
    @Environment(\.scenePhase) private var escena

    @State private var reserva: Reserva?
    @State private var folio: Folio?
    @State private var cargando = true
    @State private var metodo = "TARJETA"
    @State private var pagando = false
    @State private var generandoQr = false
    @State private var qr: PagoQr?
    @State private var escaneandoPago = false
    @State private var imagenReserva: UIImage?
    @State private var cancelando = false
    @State private var error: String?
    @State private var mensajeExito: String?

    private struct MetodoPago: Identifiable {
        let id: String
        let etiqueta: String
    }

    private let metodos: [MetodoPago] = [
        MetodoPago(id: "TARJETA", etiqueta: "Tarjeta"),
        MetodoPago(id: "EFECTIVO", etiqueta: "Efectivo"),
        MetodoPago(id: "TRANSFERENCIA", etiqueta: "Transf."),
        MetodoPago(id: "YAPE", etiqueta: "Yape"),
        MetodoPago(id: "PLIN", etiqueta: "Plin"),
    ]

    var body: some View {
        ScrollView {
            if cargando {
                ProgressView().padding(.top, 60)
            } else if let reserva {
                VStack(spacing: 16) {
                    cabecera(reserva)
                    habitaciones(reserva)

                    if let folio {
                        cuenta(folio)
                    }

                    if reserva.estaPendiente, let folio, folio.saldo > 0, sesion.esCliente {
                        bloqueDeposito(reserva, folio: folio)
                    }

                    // Con la reserva confirmada el huesped ya puede mostrar su
                    // QR en recepcion para el check-in.
                    if sesion.esCliente && (reserva.estaConfirmada || reserva.enCurso) {
                        qrCheckIn(reserva)
                    }

                    avisos

                    if reserva.sePuedeCancelar && sesion.esCliente {
                        botonCancelar
                    }
                }
                .padding(16)
            } else {
                EstadoVacio(icono: "exclamationmark.triangle",
                            titulo: "Reserva no encontrada",
                            mensaje: "Verifica el enlace e intenta de nuevo.")
                    .padding(16)
            }
        }
        .background(Tema.fondo.ignoresSafeArea())
        .navigationTitle(reserva?.codigo ?? "Reserva")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await cargar() }
        .task { await cargar() }
        // Al volver de Safari (tras confirmar el pago) se refresca el estado:
        // sin esto el cliente sigue viendo "esperando deposito" hasta que
        // recuerde tirar hacia abajo.
        .onChange(of: escena) { _, nueva in
            guard nueva == .active else { return }
            Task { await cargar() }
        }
        .sheet(isPresented: $escaneandoPago) {
            EscanerQrView(modo: .pagoCliente)
        }
    }

    // MARK: - Subvistas

    @ViewBuilder
    private var avisos: some View {
        if let error {
            Aviso(tipo: .peligro, titulo: "Error", mensaje: error)
        }
        if let mensajeExito {
            Aviso(tipo: .exito, titulo: "Listo", mensaje: mensajeExito)
        }
    }

    private var botonCancelar: some View {
        Button(role: .destructive) {
            Task { await cancelar() }
        } label: {
            HStack {
                if cancelando {
                    ProgressView().tint(Tema.peligro)
                } else {
                    Image(systemName: "xmark.circle")
                }
                Text(cancelando ? "Cancelando..." : "Cancelar reserva")
                    .font(.system(size: 13, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Tema.peligro.opacity(0.08))
            .foregroundStyle(Tema.peligro)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .disabled(cancelando || pagando)
    }

    private func cabecera(_ r: Reserva) -> some View {
        let estado = Etiquetas.estadoReserva(r.estado)

        return Tarjeta {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    EtiquetaEstado(texto: estado.texto, color: estado.color)
                    Spacer()
                    Text(Tema.soles(r.montoTotal))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Tema.azul)
                }

                Text(r.sedeNombre)
                    .font(.system(size: 14, weight: .semibold))

                Label("\(FechaAPI.formatear(FechaAPI.parsear(r.checkIn))) → \(FechaAPI.formatear(FechaAPI.parsear(r.checkOut)))",
                      systemImage: "calendar")
                    .font(.system(size: 12))
                    .foregroundStyle(Tema.textoSecundario)

                Label("\(r.noches) noche(s) · \(r.adultos) adulto(s)" +
                      (r.ninos > 0 ? " · \(r.ninos) niño(s)" : ""),
                      systemImage: "person.2")
                    .font(.system(size: 12))
                    .foregroundStyle(Tema.textoSecundario)

                if r.estaPendiente, let expira = FechaAPI.parsear(r.expiraEn) {
                    Label("Expira \(FechaAPI.formatearConHora(expira))",
                          systemImage: "clock.badge.exclamationmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Tema.alerta)
                }
            }
        }
    }

    private func habitaciones(_ r: Reserva) -> some View {
        Tarjeta {
            VStack(alignment: .leading, spacing: 10) {
                Text("Habitaciones")
                    .font(.system(size: 13, weight: .semibold))

                ForEach(r.lineas) { linea in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(linea.categoriaNombre)
                                .font(.system(size: 12, weight: .medium))
                            Text("\(FechaAPI.formatear(FechaAPI.parsear(linea.checkIn))) → \(FechaAPI.formatear(FechaAPI.parsear(linea.checkOut))) · \(linea.noches) noche(s)")
                                .font(.system(size: 10))
                                .foregroundStyle(Tema.textoSecundario)
                            Text(linea.habitacionNumero.map { "Hab. \($0)" } ?? "Se asigna al confirmar")
                                .font(.system(size: 10))
                                .foregroundStyle(Tema.textoSecundario)
                        }
                        Spacer()
                        Text(Tema.soles(linea.subtotal))
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
            }
        }
    }

    private func cuenta(_ folio: Folio) -> some View {
        Tarjeta {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Cuenta")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    EtiquetaEstado(
                        texto: folio.saldo > 0 ? "Saldo pendiente" : "Pagado",
                        color: folio.saldo > 0 ? Tema.alerta : Tema.exito)
                }

                if folio.cargos.isEmpty {
                    Text("Sin cargos registrados.")
                        .font(.system(size: 11))
                        .foregroundStyle(Tema.textoSecundario)
                } else {
                    ForEach(folio.cargos) { cargo in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(cargo.concepto.capitalized)
                                    .font(.system(size: 11, weight: .medium))
                                Text(cargo.descripcion)
                                    .font(.system(size: 9))
                                    .foregroundStyle(Tema.textoSecundario)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Text(Tema.soles(cargo.monto))
                                .font(.system(size: 11, weight: .medium))
                                .strikethrough(cargo.anulado)
                        }
                        .opacity(cargo.anulado ? 0.45 : 1)
                    }
                }

                Divider()

                fila("Total cargos", Tema.soles(folio.totalCargos))
                fila("Pagado", "− " + Tema.soles(folio.totalPagado))
                HStack {
                    Text("Saldo").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(Tema.soles(folio.saldo))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(folio.saldo > 0 ? Tema.peligro : Tema.exito)
                }

                if !folio.pagos.isEmpty {
                    Divider()
                    Text("Pagos")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Tema.textoSecundario)

                    ForEach(folio.pagos) { pago in
                        let estado = Etiquetas.estadoPago(pago.estado)
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(pago.tipo) · \(pago.metodo)")
                                    .font(.system(size: 10, weight: .medium))
                                if let fecha = pago.creadoEn {
                                    Text(FechaAPI.formatearConHora(FechaAPI.parsear(fecha)))
                                        .font(.system(size: 9))
                                        .foregroundStyle(Tema.textoSecundario)
                                }
                            }
                            Spacer()
                            EtiquetaEstado(texto: estado.texto, color: estado.color)
                            Text(Tema.soles(pago.monto))
                                .font(.system(size: 10, weight: .medium))
                        }
                    }
                }
            }
        }
    }

    private func bloqueDeposito(_ r: Reserva, folio: Folio) -> some View {
        // El backend exige el monto exacto del deposito (50 %). Se muestra el
        // requerido, nunca un importe recortado contra el saldo.
        let monto = r.depositoRequerido
        let enRevision = folio.pagosEnVerificacion.first { $0.tipo == "DEPOSITO" }

        return Tarjeta {
            VStack(alignment: .leading, spacing: 12) {
                Text(enRevision == nil ? "Pagar depósito" : "Pago en revisión")
                    .font(.system(size: 14, weight: .semibold))

                if let enRevision {
                    Text("Registramos tu depósito y recepción lo está validando. No necesitas volver a pagar: la reserva se confirma automáticamente.")
                        .font(.system(size: 11))
                        .foregroundStyle(Tema.textoSecundario)

                    Text(Tema.soles(enRevision.monto))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(Tema.azul)

                    Aviso(tipo: .info, titulo: "En verificación",
                          mensaje: "Método: \(enRevision.metodo). Te avisaremos al confirmarlo.")
                } else {
                    Text("Paga el 50 % para confirmar tu reserva. El saldo restante se cobra al llegar.")
                        .font(.system(size: 11))
                        .foregroundStyle(Tema.textoSecundario)

                    Text(Tema.soles(monto))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(Tema.azul)

                    // Pago con QR: el codigo lo genera el backend y la
                    // confirmacion tambien ocurre alli. La app solo muestra.
                    if let qr {
                        VStack(spacing: 8) {
                            if let imagen = imagenQr(qr) {
                                Image(uiImage: imagen)
                                    .interpolation(.none)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 190, height: 190)
                                    .background(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }

                            Text("Escanea el código con la cámara del celular o ábrelo aquí.")
                                .font(.system(size: 10))
                                .foregroundStyle(Tema.textoSecundario)
                                .multilineTextAlignment(.center)

                            Button {
                                abrirPasarela(qr)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "safari")
                                    Text("Abrir pasarela")
                                }
                                .font(.system(size: 12, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Tema.azul.opacity(0.10))
                                .foregroundStyle(Tema.azul)
                                .clipShape(RoundedRectangle(cornerRadius: 9))
                            }
                            .buttonStyle(.plain)

                            Button {
                                escaneandoPago = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "qrcode.viewfinder")
                                    Text("Escanear con la cámara")
                                }
                                .font(.system(size: 12, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Tema.azul.opacity(0.10))
                                .foregroundStyle(Tema.azul)
                                .clipShape(RoundedRectangle(cornerRadius: 9))
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    } else {
                        BotonPrincipal(titulo: "Pagar con QR",
                                       icono: "qrcode",
                                       cargando: generandoQr) {
                            Task { await generarQr(r) }
                        }

                        // Registro manual (Yape, transferencia...). Queda en
                        // segundo plano: el camino principal es el QR.
                        Text("Método para el registro manual")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Tema.textoSecundario)
                            .padding(.top, 4)

                        Picker("Método", selection: $metodo) {
                            ForEach(metodos) { m in
                                Text(m.etiqueta).tag(m.id)
                            }
                        }
                        .pickerStyle(.segmented)

                        Button {
                            Task { await pagar(r) }
                        } label: {
                            Text("Registrar el pago de otra forma")
                                .font(.system(size: 11))
                                .foregroundStyle(Tema.textoSecundario)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .disabled(pagando)
                    }
                }
            }
        }
    }

    /// Decodifica el PNG que envia el backend.
    private func imagenQr(_ qr: PagoQr) -> UIImage? {
        guard let data = Data(base64Encoded: qr.imagenBase64) else { return nil }
        return UIImage(data: data)
    }

    /// Abre la pasarela en Safari. Al confirmar alli, el pago se aprueba en
    /// el servidor; al volver a la app, `refreshable` recarga el estado.
    private func abrirPasarela(_ qr: PagoQr) {
        guard let url = URL(string: qr.url) else { return }
        UIApplication.shared.open(url)
    }

    /// QR de la reserva para el check-in en recepcion.
    private func qrCheckIn(_ r: Reserva) -> some View {
        Tarjeta {
            VStack(alignment: .leading, spacing: 10) {
                Text("Tu código de check-in")
                    .font(.system(size: 13, weight: .semibold))

                Text("Muéstralo en recepción al llegar.")
                    .font(.system(size: 11))
                    .foregroundStyle(Tema.textoSecundario)

                if let imagen = imagenReserva {
                    Image(uiImage: imagen)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 170, height: 170)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .frame(maxWidth: .infinity)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                }

                Text(r.codigo)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(Tema.textoSecundario)
            }
        }
        .task(id: r.id) {
            // Se pide una sola vez por reserva: el QR no cambia.
            if imagenReserva == nil {
                imagenReserva = (try? await HotelAPI.shared.qrReserva(reservaId: r.id))
                    .flatMap { UIImage(data: $0) }
            }
        }
    }

    private func fila(_ etiqueta: String, _ valor: String) -> some View {
        HStack {
            Text(etiqueta)
                .font(.system(size: 11))
                .foregroundStyle(Tema.textoSecundario)
            Spacer()
            Text(valor).font(.system(size: 11, weight: .medium))
        }
    }

    // MARK: - Acciones

    private func cargar() async {
        cargando = true
        reserva = await reservas.obtener(id: reservaId)
        folio = (try? await HotelAPI.shared.folio(reservaId: reservaId)) ?? reserva?.folio
        cargando = false
    }

    /// Pide al backend el QR del deposito (pasarela simulada).
    private func generarQr(_ r: Reserva) async {
        guard !generandoQr else { return }
        generandoQr = true
        error = nil
        mensajeExito = nil

        do {
            qr = try await HotelAPI.shared.qrDeposito(reservaId: r.id)
        } catch let apiError as APIError {
            error = apiError.mensajeUsuario
        } catch {
            self.error = "No se pudo generar el código QR."
        }

        generandoQr = false
    }

    private func pagar(_ r: Reserva) async {
        guard !pagando else { return }
        pagando = true
        error = nil
        mensajeExito = nil

        do {
            _ = try await reservas.pagarDeposito(reserva: r, metodo: metodo)
            mensajeExito = "Depósito registrado. Recepción lo verificará en breve."
            await cargar()
        } catch let apiError as APIError {
            error = apiError.mensajeUsuario
        } catch {
            self.error = "No se pudo registrar el pago."
        }

        pagando = false
    }

    private func cancelar() async {
        guard !cancelando else { return }
        cancelando = true
        error = nil

        do {
            _ = try await reservas.cancelar(id: reservaId,
                                            motivo: "Cancelada por el cliente")
            mensajeExito = "Reserva cancelada."
            await cargar()
        } catch let apiError as APIError {
            error = apiError.mensajeUsuario
        } catch {
            self.error = "No se pudo cancelar la reserva."
        }

        cancelando = false
    }
}
