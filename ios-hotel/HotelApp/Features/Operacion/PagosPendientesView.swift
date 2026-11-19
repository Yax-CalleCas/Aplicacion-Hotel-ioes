import SwiftUI

/// Verificación de pagos pendientes (recepción / admin).
///
/// El cliente registra el pago y este queda en `PENDIENTE`; aquí se aprueba
/// o rechaza. Aprobar dispara el ajuste de saldo en el backend.
struct PagosPendientesView: View {

    @Environment(OperacionStore.self) private var operacion
    @Environment(SesionStore.self) private var sesion

    @State private var procesando: Int?
    @State private var codigoOperacion = ""
    @State private var error: String?
    @State private var mensaje: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let error = error ?? operacion.errorPagos {
                    Aviso(tipo: .peligro, titulo: "Error", mensaje: error)
                }
                if let mensaje {
                    Aviso(tipo: .exito, titulo: "Listo", mensaje: mensaje)
                }

                if operacion.pagosPendientes.isEmpty {
                    // Si la carga falló no se muestra "todo verificado":
                    // antes un 403 se leía como "0 pagos" y recepción creía
                    // que no había nada por cobrar.
                    if error == nil && operacion.errorPagos == nil {
                        EstadoVacio(icono: "checkmark.seal",
                                    titulo: "Sin pagos pendientes",
                                    mensaje: "Todos los pagos están verificados.")
                    }
                } else {
                    ForEach(operacion.pagosPendientes) { pago in
                        tarjeta(pago)
                    }
                }
            }
            .padding(16)
        }
        .background(Tema.fondo.ignoresSafeArea())
        .navigationTitle("Verificar pagos")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await operacion.cargarPagosPendientes() }
        .task { await operacion.cargarPagosPendientes() }
    }

    private func tarjeta(_ pago: Pago) -> some View {
        let estado = Etiquetas.estadoPago(pago.estado)

        return Tarjeta {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Pago #\(pago.id)")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    Spacer()
                    EtiquetaEstado(texto: estado.texto, color: estado.color)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pago.tipo)
                            .font(.system(size: 11, weight: .medium))
                        Text(pago.metodo)
                            .font(.system(size: 10))
                            .foregroundStyle(Tema.textoSecundario)
                        if let fecha = pago.creadoEn {
                            Text(FechaAPI.formatearConHora(FechaAPI.parsear(fecha)))
                                .font(.system(size: 9))
                                .foregroundStyle(Tema.textoSecundario)
                        }
                    }
                    Spacer()
                    Text(Tema.soles(pago.monto))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Tema.azul)
                }

                if sesion.esAdmin || sesion.esRecepcionista {
                    TextField("Código de operación (opcional)", text: $codigoOperacion)
                        .font(.system(size: 12))
                        .padding(9)
                        .background(Tema.fondo)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    HStack(spacing: 8) {
                        Button {
                            Task { await aprobar(pago) }
                        } label: {
                            HStack(spacing: 5) {
                                if procesando == pago.id {
                                    ProgressView().tint(.white).scaleEffect(0.7)
                                } else {
                                    Image(systemName: "checkmark")
                                }
                                Text("Aprobar")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(Tema.exito)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .disabled(procesando != nil)

                        Button {
                            Task { await rechazar(pago) }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "xmark")
                                Text("Rechazar")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(Tema.peligro.opacity(0.12))
                            .foregroundStyle(Tema.peligro)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .disabled(procesando != nil)
                    }
                }
            }
        }
    }

    // MARK: - Acciones

    private func aprobar(_ pago: Pago) async {
        procesando = pago.id
        error = nil
        mensaje = nil

        do {
            try await operacion.aprobarPago(
                id: pago.id,
                codigoOperacion: codigoOperacion.isEmpty ? nil : codigoOperacion)
            mensaje = "Pago #\(pago.id) aprobado."
            codigoOperacion = ""
        } catch let apiError as APIError {
            error = apiError.mensajeUsuario
        } catch {
            self.error = "No se pudo aprobar el pago."
        }

        procesando = nil
    }

    private func rechazar(_ pago: Pago) async {
        procesando = pago.id
        error = nil
        mensaje = nil

        do {
            try await operacion.rechazarPago(id: pago.id,
                                             motivo: "Rechazado en recepción")
            mensaje = "Pago #\(pago.id) rechazado."
        } catch let apiError as APIError {
            error = apiError.mensajeUsuario
        } catch {
            self.error = "No se pudo rechazar el pago."
        }

        procesando = nil
    }
}
