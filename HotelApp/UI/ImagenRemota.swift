import SwiftUI

/// Imagen remota del catálogo (fotos de sedes y habitaciones).
///
/// Se usa `AsyncImage` con tres estados:
///  - cargando: placeholder gris con progress
///  - error o sin URL: ícono del tipo (hotel/cama)
///  - éxito: la foto recortada a la tarjeta
///
/// La URL se resuelve en `AppConfig.imagenURL` porque el backend guarda rutas
/// relativas (`/img/...`) y las sirve el frontend web, no la API.
struct ImagenRemota: View {

    let ruta: String?
    var iconoRespaldo: String = "bed.double"
    var alto: CGFloat = 150

    private var url: URL? { AppConfig.imagenURL(ruta) }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Tema.azulClaro, Tema.azulClaro.opacity(0.45)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)

            if let url {
                AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { fase in
                    switch fase {
                    case .success(let imagen):
                        imagen
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        respaldo
                    case .empty:
                        ProgressView().tint(Tema.azul)
                    @unknown default:
                        respaldo
                    }
                }
            } else {
                respaldo
            }
        }
        .frame(height: alto)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var respaldo: some View {
        Image(systemName: iconoRespaldo)
            .font(.system(size: 34))
            .foregroundStyle(Tema.azul.opacity(0.45))
    }
}
