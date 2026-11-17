import SwiftUI

/// Historial de pedidos del cliente.
///
/// Ve el estado de cada solicitud y puede anularla mientras recepción no la
/// haya gestionado.
struct MisSolicitudesView: View {

    @Environment(ServicioStore.self) private var servicio

    @State private var confirmandoCancelacion: SolicitudConsumo?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let error = servicio.error {
                    Aviso(tipo: .peligro, titulo: "Error", mensaje: error)
                }

                if servicio.misSolicitudes.isEmpty {
                    EstadoVacio(icono: "list.bullet.rectangle",
                                titulo: "Sin pedidos",
                                mensaje: "Cuando pidas servicio a la habitación aparecerá aquí.")
                        .padding(.top, 30)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(servicio.misSolicitudes) { solicitud in
                            tarjeta(solicitud)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Tema.fondo.ignoresSafeArea())
        .navigationTitle("Mis pedidos")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await servicio.cargarMisSolicitudes() }
        .task { await servicio.cargarMisSolicitudes() }
        .alert("Anular pedido", isPresented: Binding(
            get: { confirmandoCancelacion != nil },
            set: { if !$0 { confirmandoCancelacion = nil } }
        )) {
            Button("No", role: .cancel) { confirmandoCancelacion = nil }
            Button("Anular", role: .destructive) {
                if let solicitud = confirmandoCancelacion {
                    Task {
                        _ = await servicio.cancelarSolicitud(id: solicitud.id)
                        confirmandoCancelacion = nil
                    }
                }
            }
        } message: {
            Text("¿Seguro que quieres anular este pedido?")
        }
    }

    private func tarjeta(_ solicitud: SolicitudConsumo) -> some View {
        let estado = etiquetaEstado(solicitud.estado)

        return HStack(spacing: 0) {
            Rectangle()
                .fill(estado.color)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(solicitud.codigo)
                            .font(.caption.weight(.semibold).monospaced())
                            .foregroundStyle(Tema.textoSecundario)
                        if let creado = solicitud.creadoEn {
                            Text(FechaAPI.formatearConHora(FechaAPI.parsear(creado)))
                                .font(.caption2)
                                .foregroundStyle(Tema.textoSecundario)
                        }
                    }

                    Spacer(minLength: 8)

                    EtiquetaEstado(texto: estado.texto, color: estado.color)
                }

                VStack(spacing: 6) {
                    ForEach(solicitud.items) { item in
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(item.cantidad)×")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Tema.azul)
                                .frame(minWidth: 20, alignment: .leading)

                            Text(item.productoNombre)
                                .font(.subheadline)
                                .foregroundStyle(Tema.texto)
                                .lineLimit(1)

                            Spacer(minLength: 8)

                            Text(Tema.soles(item.subtotal))
                                .font(.subheadline)
                                .foregroundStyle(Tema.textoSecundario)
                        }
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(Tema.fondo)
                .clipShape(RoundedRectangle(cornerRadius: Tema.radioPequeno,
                                            style: .continuous))

                HStack(alignment: .firstTextBaseline) {
                    Text("Total")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(Tema.soles(solicitud.total))
                        .font(.headline)
                        .foregroundStyle(Tema.azul)
                }

                if let motivo = solicitud.motivoRechazo, !motivo.isEmpty {
                    Aviso(tipo: .peligro, titulo: "Rechazado", mensaje: motivo)
                }

                if solicitud.estaAprobada || solicitud.estaEntregada {
                    Aviso(tipo: .exito,
                          titulo: "Cargado a tu cuenta",
                          mensaje: "Se cobrará junto con el saldo al hacer el check-out.")
                }

                if solicitud.sePuedeCancelar {
                    Button {
                        confirmandoCancelacion = solicitud
                    } label: {
                        Label("Anular pedido", systemImage: "xmark.circle")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                            .background(Tema.peligro.opacity(0.10))
                            .foregroundStyle(Tema.peligro)
                            .clipShape(RoundedRectangle(cornerRadius: Tema.radioPequeno,
                                                        style: .continuous))
                    }
                    .buttonStyle(EstiloPresionable())
                    .accessibilityLabel("Anular pedido \(solicitud.codigo)")
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

    private func etiquetaEstado(_ estado: String) -> (texto: String, color: Color) {
        switch estado {
        case "PENDIENTE": return ("Esperando a recepción", Tema.alerta)
        case "APROBADA": return ("Aprobado", Tema.exito)
        case "ENTREGADA": return ("Entregado", Tema.azul)
        case "RECHAZADA": return ("Rechazado", Tema.peligro)
        case "CANCELADA": return ("Anulado", Tema.textoSecundario)
        default: return (estado, Tema.textoSecundario)
        }
    }
}
