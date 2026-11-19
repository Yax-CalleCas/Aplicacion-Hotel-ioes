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
                    ForEach(servicio.misSolicitudes) { solicitud in
                        tarjeta(solicitud)
                    }
                }
            }
            .padding(16)
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
        Tarjeta {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(solicitud.codigo)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Tema.textoSecundario)
                        if let creado = solicitud.creadoEn {
                            Text(FechaAPI.formatearConHora(FechaAPI.parsear(creado)))
                                .font(.system(size: 10))
                                .foregroundStyle(Tema.textoSecundario)
                        }
                    }
                    Spacer()
                    EtiquetaEstado(texto: etiquetaEstado(solicitud.estado).texto,
                                   color: etiquetaEstado(solicitud.estado).color)
                }

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(solicitud.items) { item in
                        HStack {
                            Text("\(item.cantidad)× \(item.productoNombre)")
                                .font(.system(size: 12))
                            Spacer()
                            Text(Tema.soles(item.subtotal))
                                .font(.system(size: 12))
                                .foregroundStyle(Tema.textoSecundario)
                        }
                    }
                }

                HStack {
                    Text("Total")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text(Tema.soles(solicitud.total))
                        .font(.system(size: 15, weight: .bold))
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
                        Text("Anular pedido")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(Tema.peligro.opacity(0.1))
                            .foregroundStyle(Tema.peligro)
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
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
