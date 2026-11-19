import AVFoundation
import SwiftUI
import UIKit

/// Pantalla completa del escaner de QR.
///
/// Distingue dos modos, porque el significado del codigo es distinto segun
/// quien escanee:
///
///   - **cliente**: el QR contiene la URL de la pasarela de pago. Se abre.
///   - **recepcion**: el QR contiene la reserva (URL o codigo `RES-...`) y se
///     navega al detalle para hacer el check-in.
struct EscanerQrView: View {

    enum Modo {
        case pagoCliente
        case checkIn
    }

    let modo: Modo

    /// Devuelve la reserva reconocida (solo en modo check-in).
    var alReconocerReserva: ((Reserva) -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var estado: Estado = .comprobando
    @State private var mensaje: String?
    @State private var resolviendo = false
    /// Fuerza a recrear el controlador de camara para reintentar la lectura.
    @State private var generacion = 0

    private enum Estado {
        case comprobando
        case listo
        case sinPermiso
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch estado {
            case .comprobando:
                ProgressView().tint(.white)

            case .sinPermiso:
                sinPermiso

            case .listo:
                EscanerQR(alDetectar: procesar)
                    // Al reintentar cambia la generacion: SwiftUI recrea el
                    // controlador y el escaner vuelve a aceptar lecturas
                    // (sin esto, un solo error dejaba la camara bloqueada).
                    .id(generacion)
                    .ignoresSafeArea()

                marco
                instruccion
            }

            // Cabecera flotante con cierre y mensajes.
            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(.black.opacity(0.45))
                            .clipShape(Circle())
                    }
                    Spacer()
                    Text(modo == .pagoCliente ? "Escanear QR de pago" : "Escanear reserva")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Color.clear.frame(width: 38, height: 38)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                if let mensaje {
                    Text(mensaje)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Tema.peligro.opacity(0.92))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }

                if resolviendo {
                    ProgressView().tint(.white).padding(.top, 10)
                }

                Spacer()
            }
        }
        .task { await comprobarPermiso() }
    }

    // MARK: - Subvistas

    private var marco: some View {
        GeometryReader { geo in
            let lado = min(geo.size.width, geo.size.height) * 0.62
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(.white.opacity(0.9), style: StrokeStyle(lineWidth: 3, dash: [26, 14]))
                .frame(width: lado, height: lado)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
    }

    private var instruccion: some View {
        VStack {
            Spacer()
            Text(modo == .pagoCliente
                 ? "Apunta al código QR del depósito"
                 : "Apunta al QR de la reserva del huésped")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.black.opacity(0.45))
                .clipShape(Capsule())
                .padding(.bottom, 44)
        }
        .allowsHitTesting(false)
    }

    private var sinPermiso: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.fill")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.7))

            Text("Sin acceso a la cámara")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)

            Text("Activa la cámara en Ajustes para escanear el código QR.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Abrir Ajustes")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 11)
                    .background(.white)
                    .foregroundStyle(Tema.azul)
                    .clipShape(Capsule())
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Logica

    private func comprobarPermiso() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            estado = .listo

        case .notDetermined:
            let concedido = await AVCaptureDevice.requestAccess(for: .video)
            estado = concedido ? .listo : .sinPermiso

        default:
            estado = .sinPermiso
        }
    }

    private func procesar(_ texto: String) {
        guard !resolviendo else { return }
        mensaje = nil

        switch modo {
        case .pagoCliente:
            abrirPago(texto)

        case .checkIn:
            Task { await resolverReserva(texto) }
        }
    }

    /// El QR de pago es una URL del backend: se abre en el navegador.
    private func abrirPago(_ texto: String) {
        guard let url = URL(string: texto),
              let esquema = url.scheme,
              esquema == "https" || esquema == "http" else {
            mostrarError("Ese código no es un enlace de pago.")
            return
        }

        UIApplication.shared.open(url)
        dismiss()
    }

    /// Muestra el error y habilita la camara para intentarlo otra vez.
    private func mostrarError(_ texto: String) {
        mensaje = texto
        generacion += 1
    }

    /// Acepta tanto una URL con el código dentro como el código en crudo.
    private func resolverReserva(_ texto: String) async {
        guard let codigo = extraerCodigo(texto) else {
            mostrarError("Ese QR no corresponde a una reserva.")
            return
        }

        guard !resolviendo else { return }
        resolviendo = true

        do {
            let encontrada = try await HotelAPI.shared.reserva(codigo: codigo)
            resolviendo = false
            alReconocerReserva?(encontrada)
            dismiss()
        } catch let error as APIError {
            resolviendo = false
            mostrarError(error.status == 404
                ? "No existe la reserva \(codigo)."
                : error.mensajeUsuario)
        } catch {
            resolviendo = false
            mostrarError("No se pudo consultar la reserva.")
        }
    }

    /// Acepta `RES-2026-00001` en crudo o dentro de una URL.
    private func extraerCodigo(_ texto: String) -> String? {
        let limpio = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        let patron = "RES-[0-9]{4}-[0-9]+"

        if let rango = limpio.range(of: patron, options: .regularExpression) {
            return String(limpio[rango])
        }
        return nil
    }
}
