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
            VStack(spacing: 16) {
                buscadorCodigo

                if reservas.desdeCache {
                    Aviso(tipo: .alerta, titulo: "Sin conexión",
                          mensaje: "Mostrando reservas guardadas en el dispositivo.")
                }

                if reservas.cargando && reservas.reservas.isEmpty {
                    esqueleto
                } else if reservas.reservas.isEmpty {
                    EstadoVacio(icono: "calendar",
                                titulo: "Sin reservas",
                                mensaje: "Busca disponibilidad y reserva tu primera estadía.")
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(reservas.reservas) { r in
                            NavigationLink {
                                DetalleReservaView(reservaId: r.id)
                            } label: {
                                tarjeta(r)
                            }
                            .buttonStyle(EstiloPresionable())
                            .accessibilityLabel(accessibilityTarjeta(r))
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
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
            VStack(alignment: .leading, spacing: 10) {
                Label("Buscar por código", systemImage: "number")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Tema.texto)

                HStack(spacing: 8) {
                    TextField("RES-2026-00001", text: $codigo)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                        .padding(11)
                        .background(Tema.fondo)
                        .clipShape(RoundedRectangle(cornerRadius: Tema.radioPequeno,
                                                    style: .continuous))

                    Button {
                        Task { await buscarPorCodigo() }
                    } label: {
                        Group {
                            if buscandoCodigo {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "magnifyingglass")
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                        .frame(width: 46, height: 46)
                        .background(codigoLimpio.isEmpty ? Tema.azul.opacity(0.4) : Tema.azul)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: Tema.radioPequeno,
                                                    style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(codigoLimpio.isEmpty || buscandoCodigo)
                    .accessibilityLabel("Buscar reserva por código")
                }

                if let errorCodigo {
                    Label(errorCodigo, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Tema.peligro)
                }
            }
        }
    }

    private var codigoLimpio: String {
        codigo.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func tarjeta(_ r: ReservaResumen) -> some View {
        let estado = Etiquetas.estadoReserva(r.estado)

        return HStack(spacing: 0) {
            Rectangle()
                .fill(estado.color)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.codigo)
                            .font(.caption.weight(.semibold).monospaced())
                            .foregroundStyle(Tema.textoSecundario)
                        Text(FechaAPI.formatear(FechaAPI.parsear(r.checkIn))
                             + " → " + FechaAPI.formatear(FechaAPI.parsear(r.checkOut)))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Tema.texto)
                    }

                    Spacer(minLength: 8)

                    EtiquetaEstado(texto: estado.texto, color: estado.color)
                }

                // El cliente debe saber en la lista si le falta pagar, si su
                // pago está en revisión o si ya está todo en orden.
                if r.estado == "PENDIENTE" {
                    HStack(spacing: 6) {
                        Image(systemName: r.pagoEnRevision
                              ? "clock.arrow.circlepath" : "exclamationmark.circle.fill")
                            .font(.caption2)
                        Text(r.pagoEnRevision
                             ? "Pago en revisión por recepción"
                             : "Falta el depósito del 50 %")
                            .font(.caption.weight(.medium))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(r.pagoEnRevision ? Tema.info : Tema.alerta)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background((r.pagoEnRevision ? Tema.info : Tema.alerta).opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                HStack(alignment: .firstTextBaseline) {
                    Label(r.huespedNombre, systemImage: "person")
                        .font(.caption)
                        .foregroundStyle(Tema.textoSecundario)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(Tema.soles(r.montoTotal))
                        .font(.headline)
                        .foregroundStyle(Tema.azul)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Tema.superficie)
        .clipShape(RoundedRectangle(cornerRadius: Tema.radio, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Tema.radio, style: .continuous)
                .stroke(Tema.borde, lineWidth: 1))
        .shadow(color: Tema.colorSombra, radius: 12, x: 0, y: 4)
    }

    private func accessibilityTarjeta(_ r: ReservaResumen) -> String {
        let estado = Etiquetas.estadoReserva(r.estado)
        return "Reserva \(r.codigo), \(estado.texto), "
            + "\(FechaAPI.formatear(FechaAPI.parsear(r.checkIn))) a "
            + "\(FechaAPI.formatear(FechaAPI.parsear(r.checkOut))), "
            + "\(Tema.soles(r.montoTotal))"
    }

    private var esqueleto: some View {
        VStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in
                Tarjeta {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("RES-2026-00000").font(.caption)
                        Text("01 ene → 03 ene").font(.subheadline)
                        Divider()
                        Text("S/ 000.00").font(.headline)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
    }

    // MARK: - Acciones

    private func buscarPorCodigo() async {
        let limpio = codigoLimpio.uppercased()
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
                    .font(.subheadline.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Tema.peligro.opacity(0.08))
            .foregroundStyle(Tema.peligro)
            .clipShape(RoundedRectangle(cornerRadius: Tema.radioPequeno,
                                        style: .continuous))
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
                        .font(.title.weight(.bold))
                        .foregroundStyle(Tema.azul)
                }

                Text(r.sedeNombre)
                    .font(.subheadline.weight(.semibold))

                Label("\(FechaAPI.formatear(FechaAPI.parsear(r.checkIn))) → \(FechaAPI.formatear(FechaAPI.parsear(r.checkOut)))",
                      systemImage: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(Tema.textoSecundario)

                Label("\(r.noches) noche(s) · \(r.adultos) adulto(s)" +
                      (r.ninos > 0 ? " · \(r.ninos) niño(s)" : ""),
                      systemImage: "person.2")
                    .font(.subheadline)
                    .foregroundStyle(Tema.textoSecundario)

                if r.estaPendiente, let expira = FechaAPI.parsear(r.expiraEn) {
                    Label("Expira \(FechaAPI.formatearConHora(expira))",
                          systemImage: "clock.badge.exclamationmark")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Tema.alerta)
                }
            }
        }
    }

    private func habitaciones(_ r: Reserva) -> some View {
        Tarjeta {
            VStack(alignment: .leading, spacing: 10) {
                Text("Habitaciones")
                    .font(.headline)

                ForEach(r.lineas) { linea in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(linea.categoriaNombre)
                                .font(.subheadline.weight(.medium))
                            Text("\(FechaAPI.formatear(FechaAPI.parsear(linea.checkIn))) → \(FechaAPI.formatear(FechaAPI.parsear(linea.checkOut))) · \(linea.noches) noche(s)")
                                .font(.caption2)
                                .foregroundStyle(Tema.textoSecundario)
                            Text(linea.habitacionNumero.map { "Hab. \($0)" } ?? "Se asigna al confirmar")
                                .font(.caption2)
                                .foregroundStyle(Tema.textoSecundario)
                        }
                        Spacer()
                        Text(Tema.soles(linea.subtotal))
                            .font(.subheadline.weight(.semibold))
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
                        .font(.headline)
                    Spacer()
                    EtiquetaEstado(
                        texto: folio.saldo > 0 ? "Saldo pendiente" : "Pagado",
                        color: folio.saldo > 0 ? Tema.alerta : Tema.exito)
                }

                if folio.cargos.isEmpty {
                    Text("Sin cargos registrados.")
                        .font(.caption)
                        .foregroundStyle(Tema.textoSecundario)
                } else {
                    ForEach(folio.cargos) { cargo in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(cargo.concepto.capitalized)
                                    .font(.caption.weight(.medium))
                                Text(cargo.descripcion)
                                    .font(.caption2)
                                    .foregroundStyle(Tema.textoSecundario)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Text(Tema.soles(cargo.monto))
                                .font(.caption.weight(.medium))
                                .strikethrough(cargo.anulado)
                        }
                        .opacity(cargo.anulado ? 0.45 : 1)
                    }
                }

                Divider()

                fila("Total cargos", Tema.soles(folio.totalCargos))
                fila("Pagado", "− " + Tema.soles(folio.totalPagado))
                HStack {
                    Text("Saldo").font(.headline)
                    Spacer()
                    Text(Tema.soles(folio.saldo))
                        .font(.headline)
                        .foregroundStyle(folio.saldo > 0 ? Tema.peligro : Tema.exito)
                }

                if !folio.pagos.isEmpty {
                    Divider()
                    Text("Pagos")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Tema.textoSecundario)

                    ForEach(folio.pagos) { pago in
                        let estado = Etiquetas.estadoPago(pago.estado)
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(pago.tipo) · \(pago.metodo)")
                                    .font(.caption2.weight(.medium))
                                if let fecha = pago.creadoEn {
                                    Text(FechaAPI.formatearConHora(FechaAPI.parsear(fecha)))
                                        .font(.caption2)
                                        .foregroundStyle(Tema.textoSecundario)
                                }
                            }
                            Spacer()
                            EtiquetaEstado(texto: estado.texto, color: estado.color)
                            Text(Tema.soles(pago.monto))
                                .font(.caption2.weight(.medium))
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
                    .font(.subheadline.weight(.semibold))

                if let enRevision {
                    Text("Registramos tu depósito y recepción lo está validando. No necesitas volver a pagar: la reserva se confirma automáticamente.")
                        .font(.caption)
                        .foregroundStyle(Tema.textoSecundario)

                    Text(Tema.soles(enRevision.monto))
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(Tema.azul)

                    Aviso(tipo: .info, titulo: "En verificación",
                          mensaje: "Método: \(enRevision.metodo). Te avisaremos al confirmarlo.")
                } else {
                    Text("Paga el 50 % para confirmar tu reserva. El saldo restante se cobra al llegar.")
                        .font(.caption)
                        .foregroundStyle(Tema.textoSecundario)

                    Text(Tema.soles(monto))
                        .font(.largeTitle.weight(.bold))
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
                                .font(.caption2)
                                .foregroundStyle(Tema.textoSecundario)
                                .multilineTextAlignment(.center)

                            Button {
                                abrirPasarela(qr)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "safari")
                                    Text("Abrir pasarela")
                                }
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Tema.azul.opacity(0.10))
                                .foregroundStyle(Tema.azul)
                                .clipShape(RoundedRectangle(cornerRadius: Tema.radioPequeno,
                                            style: .continuous))
                            }
                            .buttonStyle(.plain)

                            Button {
                                escaneandoPago = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "qrcode.viewfinder")
                                    Text("Escanear con la cámara")
                                }
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Tema.azul.opacity(0.10))
                                .foregroundStyle(Tema.azul)
                                .clipShape(RoundedRectangle(cornerRadius: Tema.radioPequeno,
                                            style: .continuous))
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
                            .font(.caption2.weight(.semibold))
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
                                .font(.caption)
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
                    .font(.headline)

                Text("Muéstralo en recepción al llegar.")
                    .font(.caption)
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
                    .font(.subheadline.weight(.semibold).monospaced())
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
                .font(.caption)
                .foregroundStyle(Tema.textoSecundario)
            Spacer()
            Text(valor).font(.caption.weight(.medium))
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
