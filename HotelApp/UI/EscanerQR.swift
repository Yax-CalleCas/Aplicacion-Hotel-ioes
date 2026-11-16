import AVFoundation
import AudioToolbox
import SwiftUI
import UIKit

/// Escaner de codigos QR con la camara del dispositivo (AVFoundation).
///
/// Se usa para dos cosas en la app del hotel:
///
///   1. **Pago**: el cliente escanea el QR de la pasarela y lo abre.
///   2. **Check-in**: recepcion escanea el QR de la reserva y abre el folio.
///
/// Por que AVFoundation y no una libreria externa: es el framework nativo de
/// captura de video de iOS, no anade dependencias y funciona sin red (la
/// decodificacion ocurre en el dispositivo).
///
/// Permiso requerido en Info.plist: `NSCameraUsageDescription`.
struct EscanerQR: UIViewControllerRepresentable {

    /// Se llama **una sola vez** con el primer codigo leido.
    let alDetectar: (String) -> Void

    func makeUIViewController(context: Context) -> EscanerViewController {
        let controlador = EscanerViewController()
        controlador.alDetectar = alDetectar
        return controlador
    }

    func updateUIViewController(_ controlador: EscanerViewController, context: Context) {
        // El callback se refresca sin recrear la sesion de captura.
        controlador.alDetectar = alDetectar
    }

    /// SwiftUI llama a este metodo al desmontar la vista: hay que parar la
    /// sesion o la camara sigue encendida consumiendo bateria.
    static func dismantleUIViewController(_ controlador: EscanerViewController,
                                          coordinator: Void) {
        controlador.detener()
    }
}

/// Controlador con la sesion de captura y la deteccion de metadatos.
final class EscanerViewController: UIViewController {

    var alDetectar: ((String) -> Void)?

    private let sesion = AVCaptureSession()
    private let cola = DispatchQueue(label: "pe.agrocorp.hotel.escaner")
    private var capaVideo: AVCaptureVideoPreviewLayer?

    /// Evita disparar el callback dos veces por el mismo codigo: el escaner
    /// entrega metadatos muchas veces por segundo mientras apunta al QR.
    private var yaDetectado = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configurarCamara()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        iniciar()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        detener()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        capaVideo?.frame = view.bounds
    }

    // MARK: - Camara

    private func configurarCamara() {
        guard let dispositivo = AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: .back) else {
            return
        }

        guard let entrada = try? AVCaptureDeviceInput(device: dispositivo),
              sesion.canAddInput(entrada) else {
            return
        }
        sesion.addInput(entrada)

        let salida = AVCaptureMetadataOutput()
        guard sesion.canAddOutput(salida) else { return }
        sesion.addOutput(salida)

        // La cola principal es lo correcto aqui: `metadataOutput` se invoca muy
        // a menudo y el callback (`alDetectar`) actualiza estado de SwiftUI,
        // que debe ejecutarse en el hilo principal. El analisis del fotograma
        // ya ocurre internamente fuera de ese hilo.
        salida.setMetadataObjectsDelegate(self, queue: .main)

        // Se restringe a QR: menos trabajo por fotograma y menos falsos positivos.
        if salida.availableMetadataObjectTypes.contains(.qr) {
            salida.metadataObjectTypes = [.qr]
        }

        let capa = AVCaptureVideoPreviewLayer(session: sesion)
        capa.videoGravity = .resizeAspectFill
        capa.frame = view.bounds
        view.layer.addSublayer(capa)
        capaVideo = capa
    }

    func iniciar() {
        // `startRunning` bloquea: nunca en el hilo principal.
        cola.async { [sesion] in
            guard !sesion.isRunning else { return }
            sesion.startRunning()
        }
    }

    func detener() {
        cola.async { [sesion] in
            guard sesion.isRunning else { return }
            sesion.stopRunning()
        }
    }
}

extension EscanerViewController: AVCaptureMetadataOutputObjectsDelegate {

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {

        // El primero gana: se ignora todo lo demas hasta que la vista se cierre.
        guard !yaDetectado,
              let objeto = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              objeto.type == .qr,
              let valor = objeto.stringValue,
              !valor.isEmpty else {
            return
        }

        yaDetectado = true

        // Confirmacion haptica: en un mostrador el usuario no siempre mira.
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
        alDetectar?(valor)
    }
}
