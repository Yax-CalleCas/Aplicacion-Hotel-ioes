import SwiftUI

/// Bandeja de notificaciones del usuario.
///
/// El backend genera avisos en cada evento de reserva, pago y housekeeping.
/// Al tocar una notificación se marca como leída y se navega al origen cuando
/// hay una referencia disponible.
struct NotificacionesView: View {

    @State private var notificaciones: [Notificacion] = []
    @State private var cargando = true
    @State private var error: String?

    private let api = HotelAPI.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if cargando && notificaciones.isEmpty {
                    ProgressView().padding(.top, 40)
                } else if notificaciones.isEmpty {
                    EstadoVacio(icono: "bell.slash",
                                titulo: "Sin notificaciones",
                                mensaje: "Aquí verás los avisos de tus reservas y pagos.")
                } else {
                    ForEach(notificaciones) { n in
                        tarjeta(n)
                    }
                }

                if let error {
                    Aviso(tipo: .peligro, titulo: "Error", mensaje: error)
                }
            }
            .padding(16)
        }
        .background(Tema.fondo.ignoresSafeArea())
        .navigationTitle("Notificaciones")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await cargar() }
        .task { await cargar() }
    }

    private func tarjeta(_ n: Notificacion) -> some View {
        Button {
            Task { await marcarLeida(n) }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icono(tipo: n.tipo))
                    .font(.system(size: 16))
                    .foregroundStyle(color(tipo: n.tipo))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(n.titulo)
                            .font(.system(size: 13, weight: n.leida ? .regular : .semibold))
                            .foregroundStyle(Tema.texto)
                        if !n.leida {
                            Circle().fill(Tema.azul).frame(width: 6, height: 6)
                        }
                    }

                    Text(n.mensaje)
                        .font(.system(size: 11))
                        .foregroundStyle(Tema.textoSecundario)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(FechaAPI.formatearConHora(FechaAPI.parsear(n.creadoEn)))
                        .font(.system(size: 9))
                        .foregroundStyle(Tema.textoSecundario)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .background(n.leida ? Tema.superficie : Tema.azulClaro.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: Tema.radioPequeno))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Utilidades

    private func icono(tipo: String) -> String {
        switch tipo {
        case "RESERVA_CREADA": return "calendar.badge.plus"
        case "CANCELACION": return "calendar.badge.minus"
        case "PAGO": return "creditcard"
        case "CHECK_IN": return "arrow.down.right.circle"
        case "CHECK_OUT": return "arrow.up.right.circle"
        case "HOUSEKEEPING": return "sparkles"
        default: return "bell"
        }
    }

    private func color(tipo: String) -> Color {
        switch tipo {
        case "CANCELACION": return Tema.peligro
        case "PAGO": return Tema.exito
        case "CHECK_IN": return Tema.info
        case "CHECK_OUT": return Tema.alerta
        default: return Tema.azul
        }
    }

    // MARK: - Acciones

    private func cargar() async {
        cargando = true
        error = nil

        do {
            notificaciones = try await api.notificaciones()
        } catch let apiError as APIError {
            error = apiError.mensajeUsuario
        } catch {
            self.error = "No se pudieron cargar las notificaciones."
        }

        cargando = false
    }

    private func marcarLeida(_ n: Notificacion) async {
        guard !n.leida else { return }

        try? await api.marcarLeida(id: n.id)

        if let indice = notificaciones.firstIndex(where: { $0.id == n.id }) {
            notificaciones[indice] = Notificacion(
                id: n.id, tipo: n.tipo, titulo: n.titulo, mensaje: n.mensaje,
                referenciaId: n.referenciaId, referenciaTipo: n.referenciaTipo,
                leida: true, creadoEn: n.creadoEn)
        }
    }
}
