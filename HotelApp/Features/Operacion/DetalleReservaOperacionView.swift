import SwiftUI

/// Detalle de reserva para recepción: check-in, check-out y cobro del saldo.
///
/// Reglas del backend que esta vista respeta:
///  - El check-in exige el depósito pagado y la habitación DISPONIBLE.
///  - El check-out exige saldo cero y deja la habitación en LIMPIEZA.
///  - Aprobar un pago es una acción aparte del registro.
struct DetalleReservaOperacionView: View {

    let reservaId: Int

    @Environment(ReservaStore.self) private var reservas
    @Environment(OperacionStore.self) private var operacion

    @State private var reserva: Reserva?
    @State private var estadia: Estadia?
    @State private var cargando = true
    @State private var procesando = false
    @State private var error: String?
    @State private var mensaje: String?

    private let api = HotelAPI.shared

    var body: some View {
        ScrollView {
            if cargando {
                ProgressView().padding(.top, 60)
            } else if let reserva {
                VStack(spacing: 16) {
                    cabecera(reserva)

                    if let folio = reserva.folio {
                        cuenta(folio)
                    }

                    acciones(reserva)

                    if let error {
                        Aviso(tipo: .peligro, titulo: "Error", mensaje: error)
                    }
                    if let mensaje {
                        Aviso(tipo: .exito, titulo: "Listo", mensaje: mensaje)
                    }
                }
                .padding(16)
            } else {
                EstadoVacio(icono: "exclamationmark.triangle",
                            titulo: "Reserva no encontrada",
                            mensaje: "Verifica el código e intenta de nuevo.")
                    .padding(16)
            }
        }
        .background(Tema.fondo.ignoresSafeArea())
        .navigationTitle(reserva?.codigo ?? "Reserva")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await cargar() }
        .task { await cargar() }
    }

    // MARK: - Subvistas

    private func cabecera(_ r: Reserva) -> some View {
        let estado = Etiquetas.estadoReserva(r.estado)

        return Tarjeta {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    EtiquetaEstado(texto: estado.texto, color: estado.color)
                    Spacer()
                    Text(Tema.soles(r.montoTotal))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Tema.azul)
                }

                Text(r.codigo)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))

                Text(r.huespedTitular.nombreCompleto)
                    .font(.system(size: 15, weight: .medium))

                if let telefono = r.huespedTitular.telefono {
                    Label(telefono, systemImage: "phone")
                        .font(.system(size: 11))
                        .foregroundStyle(Tema.textoSecundario)
                }

                Label("\(FechaAPI.formatear(FechaAPI.parsear(r.checkIn))) → \(FechaAPI.formatear(FechaAPI.parsear(r.checkOut))) · \(r.noches) noche(s)",
                      systemImage: "calendar")
                    .font(.system(size: 11))
                    .foregroundStyle(Tema.textoSecundario)
            }
        }
    }

    private func cuenta(_ folio: Folio) -> some View {
        Tarjeta {
            VStack(spacing: 8) {
                fila("Total cargos", Tema.soles(folio.totalCargos))
                fila("Pagado", Tema.soles(folio.totalPagado))
                HStack {
                    Text("Saldo").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(Tema.soles(folio.saldo))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(folio.saldo > 0 ? Tema.peligro : Tema.exito)
                }

                if !folio.pagosEnVerificacion.isEmpty {
                    Divider()
                    Aviso(tipo: .alerta,
                          titulo: "Pago por verificar",
                          mensaje: "Hay \(folio.pagosEnVerificacion.count) pago(s) esperando aprobación.")
                }
            }
        }
    }

    @ViewBuilder
    private func acciones(_ r: Reserva) -> some View {
        VStack(spacing: 10) {
            if let folio = r.folio, folio.saldo > 0 {
                BotonPrincipal(titulo: "Cobrar saldo (\(Tema.soles(folio.saldo)))",
                               icono: "banknote",
                               cargando: procesando) {
                    Task { await cobrarSaldo(r, folio: folio) }
                }
            }

            if r.estaConfirmada {
                BotonPrincipal(titulo: "Hacer check-in",
                               icono: "arrow.right.circle",
                               cargando: procesando) {
                    Task { await hacerCheckIn(r) }
                }
            }

            if r.enCurso, let estadia {
                Aviso(tipo: .info, titulo: "En habitación",
                      mensaje: "Hab. \(estadia.habitacionNumero) desde \(FechaAPI.formatearConHora(FechaAPI.parsear(estadia.checkInReal))).")

                BotonPrincipal(titulo: "Hacer check-out",
                               icono: "arrow.left.circle",
                               cargando: procesando) {
                    Task { await hacerCheckOut(estadia) }
                }
            }

            if r.estaPendiente {
                Aviso(tipo: .alerta, titulo: "Pendiente de depósito",
                      mensaje: "El huésped debe pagar el depósito antes del check-in.")
            }

            if r.cancelada {
                Aviso(tipo: .peligro, titulo: "Reserva cancelada",
                      mensaje: "No se puede operar sobre esta reserva.")
            }
        }
    }

    private func fila(_ etiqueta: String, _ valor: String) -> some View {
        HStack {
            Text(etiqueta)
                .font(.system(size: 12))
                .foregroundStyle(Tema.textoSecundario)
            Spacer()
            Text(valor).font(.system(size: 12, weight: .medium))
        }
    }

    // MARK: - Acciones

    private func cargar() async {
        cargando = true
        reserva = await reservas.obtener(id: reservaId)

        if let activas = try? await api.estadiasActivas() {
            estadia = activas.first { $0.reservaId == reservaId }
        }

        cargando = false
    }

    private func hacerCheckIn(_ r: Reserva) async {
        guard let linea = r.lineas.first else { return }
        procesando = true
        error = nil
        mensaje = nil

        do {
            _ = try await api.checkIn(reservaId: r.id, request: CheckInRequest(
                lineaId: linea.id,
                habitacionId: linea.habitacionId,
                observaciones: "Check-in desde iOS",
                acompanantes: nil))
            mensaje = "Check-in realizado."
            await cargar()
            await operacion.cargarDashboard(sedeId: r.sedeId)
        } catch let apiError as APIError {
            error = apiError.mensajeUsuario
        } catch {
            self.error = "No se pudo hacer check-in."
        }

        procesando = false
    }

    private func hacerCheckOut(_ e: Estadia) async {
        procesando = true
        error = nil
        mensaje = nil

        do {
            _ = try await api.checkOut(estadiaId: e.id,
                                       observaciones: "Check-out desde iOS",
                                       cerrarFolio: true)
            mensaje = "Check-out realizado. Habitación en limpieza."
            await cargar()
            await operacion.cargarDashboard(sedeId: reserva?.sedeId)
        } catch let apiError as APIError {
            error = apiError.mensajeUsuario
        } catch {
            self.error = "No se pudo hacer check-out."
        }

        procesando = false
    }

    private func cobrarSaldo(_ r: Reserva, folio: Folio) async {
        procesando = true
        error = nil
        mensaje = nil

        do {
            // La clave lleva el numero de intento leido del servidor: un doble
            // toque no cobra dos veces, pero tras un rechazo se puede reintentar.
            let intento = folio.pagos.filter { $0.tipo == "SALDO" }.count + 1

            let pago = try await api.registrarPago(
                reservaId: r.id,
                request: CrearPagoRequest(
                    tipo: "SALDO",
                    metodo: "EFECTIVO",
                    monto: folio.saldo,
                    idempotencyKey: "ios-saldo-\(r.id)-\(intento)",
                    codigoOperacion: nil))

            // En recepción el cobro se aprueba en el acto.
            _ = try await api.aprobarPago(id: pago.id, codigoOperacion: nil)
            mensaje = "Saldo cobrado."
            await cargar()
        } catch let apiError as APIError {
            error = apiError.mensajeUsuario
        } catch {
            self.error = "No se pudo cobrar el saldo."
        }

        procesando = false
    }
}
