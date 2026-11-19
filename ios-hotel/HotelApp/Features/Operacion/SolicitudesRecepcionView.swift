import SwiftUI

/// Cola de servicio a la habitación — vista de recepción.
///
/// Aprobar carga al folio; rechazar exige motivo.
struct SolicitudesRecepcionView: View {

    @Environment(ServicioStore.self) private var servicio
    @Environment(\.dismiss) private var dismiss

    @State private var seleccionada: SolicitudConsumo?
    @State private var rechazando: SolicitudConsumo?
    @State private var motivo = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let error = servicio.error {
                    Aviso(tipo: .peligro, titulo: "Error", mensaje: error)
                }

                if servicio.pendientes.isEmpty {
                    EstadoVacio(icono: "checkmark.circle",
                                titulo: "Sin solicitudes",
                                mensaje: "No hay pedidos pendientes de atender.")
                        .padding(.top, 30)
                } else {
                    Text("\(servicio.pendientes.count) \(servicio.pendientes.count == 1 ? "pedido pendiente" : "pedidos pendientes")")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Tema.textoSecundario)

                    ForEach(servicio.pendientes) { solicitud in
                        tarjeta(solicitud)
                    }
                }
            }
            .padding(16)
        }
        .background(Tema.fondo.ignoresSafeArea())
        .navigationTitle("Servicio a habitación")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await servicio.cargarPendientes() }
        .task { await servicio.cargarPendientes() }
        .alert("Rechazar solicitud", isPresented: Binding(
            get: { rechazando != nil },
            set: { if !$0 { rechazando = nil; motivo = "" } }
        )) {
            TextField("Motivo", text: $motivo)
            Button("Cancelar", role: .cancel) { rechazando = nil; motivo = "" }
            Button("Rechazar", role: .destructive) {
                if let solicitud = rechazando {
                    Task {
                        _ = await servicio.rechazar(id: solicitud.id, motivo: motivo)
                        rechazando = nil
                        motivo = ""
                    }
                }
            }
            .disabled(motivo.trimmingCharacters(in: .whitespaces).isEmpty)
        } message: {
            Text("Indica por qué no se puede atender el pedido.")
        }
    }

    // MARK: - Tarjeta

    private func tarjeta(_ solicitud: SolicitudConsumo) -> some View {
        Tarjeta {
            VStack(alignment: .leading, spacing: 12) {
                encabezado(solicitud)

                Divider()

                VStack(alignment: .leading, spacing: 5) {
                    ForEach(solicitud.items) { item in
                        HStack {
                            Text("\(item.cantidad)×")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Tema.azul)
                                .frame(width: 24, alignment: .leading)
                            Text(item.productoNombre)
                                .font(.system(size: 12))
                            Spacer()
                            Text(Tema.soles(item.subtotal))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Tema.textoSecundario)
                        }
                    }
                }

                if let observaciones = solicitud.observaciones, !observaciones.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "text.bubble")
                            .font(.system(size: 11))
                            .foregroundStyle(Tema.alerta)
                        Text(observaciones)
                            .font(.system(size: 11))
                            .foregroundStyle(Tema.textoSecundario)
                            .italic()
                    }
                }

                HStack {
                    Text("Total")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text(Tema.soles(solicitud.total))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Tema.azul)
                }

                acciones(solicitud)
            }
        }
    }

    private func encabezado(_ solicitud: SolicitudConsumo) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(Tema.azulClaro).frame(width: 42, height: 42)
                Text(solicitud.habitacionNumero ?? "—")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Tema.azul)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(solicitud.huespedNombre ?? "Huésped")
                    .font(.system(size: 13, weight: .semibold))
                Text("Hab. \(solicitud.habitacionNumero ?? "—") · \(solicitud.codigo)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Tema.textoSecundario)
                if let creado = solicitud.creadoEn {
                    Text(hace(creado))
                        .font(.system(size: 10))
                        .foregroundStyle(Tema.alerta)
                }
            }

            Spacer()

            EtiquetaEstado(texto: "\(solicitud.totalUnidades) u.",
                           color: Tema.azul,
                           icono: "shippingbox")
        }
    }

    private func acciones(_ solicitud: SolicitudConsumo) -> some View {
        HStack(spacing: 8) {
            Button {
                Task { _ = await servicio.aprobar(id: solicitud.id) }
            } label: {
                Label("Aprobar y cargar", systemImage: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Tema.exito)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .disabled(servicio.procesando)

            Button {
                rechazando = solicitud
                motivo = ""
            } label: {
                Label("Rechazar", systemImage: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Tema.peligro.opacity(0.12))
                    .foregroundStyle(Tema.peligro)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .disabled(servicio.procesando)
        }
    }

    /// Texto relativo: "hace 3 min".
    private func hace(_ iso: String) -> String {
        guard let fecha = FechaAPI.parsear(iso) else { return "" }
        let minutos = Int(Date().timeIntervalSince(fecha) / 60)
        if minutos < 1 { return "Ahora mismo" }
        if minutos < 60 { return "Hace \(minutos) min" }
        let horas = minutos / 60
        return "Hace \(horas) h"
    }
}
