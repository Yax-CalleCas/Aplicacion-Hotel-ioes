import SwiftUI

/// Check-in por QR: recepcion escanea el codigo de la reserva del huésped y
/// entra directo al detalle para hacer el check-in.
///
/// Antes habia que buscar la reserva a mano por código o por nombre; en un
/// mostrador con cola, escanear el QR del movil del huésped ahorra el error
/// de teclear un código mal.
struct CheckInQrView: View {

    @Environment(\.dismiss) private var dismiss

    @State private var escaneando = false
    @State private var reserva: Reserva?
    /// Evita reabrir la camara automaticamente al volver del detalle.
    @State private var yaAbrioCamara = false

    var body: some View {
        NavigationStack {
            Group {
                if let reserva {
                    DetalleReservaOperacionView(reservaId: reserva.id)
                        .navigationBarBackButtonHidden(true)
                } else {
                    contenidoEscaneo
                }
            }
            .navigationTitle(reserva == nil ? "Check-in por QR" : "Reserva")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if reserva == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cerrar") { dismiss() }
                    }
                } else {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Escanear otro") {
                            self.reserva = nil
                            escaneando = true
                        }
                    }
                }
            }
        }
        // La camara se abre sola la primera vez; despues manda el boton.
        .task {
            guard !yaAbrioCamara, reserva == nil else { return }
            yaAbrioCamara = true
            escaneando = true
        }
        .sheet(isPresented: $escaneando) {
            EscanerQrView(modo: .checkIn) { encontrada in
                reserva = encontrada
            }
        }
    }

    private var contenidoEscaneo: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 56))
                .foregroundStyle(Tema.azul)

            Text("Escanea el QR de la reserva")
                .font(.system(size: 16, weight: .semibold))

            Text("Abre la cámara y apunta al código que muestra el huésped en su aplicación.")
                .font(.system(size: 12))
                .foregroundStyle(Tema.textoSecundario)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)

            BotonPrincipal(titulo: "Abrir cámara", icono: "camera.fill") {
                escaneando = true
            }
            .padding(.horizontal, 24)
            .padding(.top, 6)

            Spacer()
        }
        .background(Tema.fondo.ignoresSafeArea())
    }
}
