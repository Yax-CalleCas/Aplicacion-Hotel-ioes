import SwiftUI
import PhotosUI

/// Subida de una foto desde la galería del iPhone (PhotosPicker).
///
/// Se usa en recepción para cambiar la foto de una habitación sin pasar por
/// el navegador. `PhotosPicker` es nativo (iOS 16+) y no requiere el permiso
/// completo de la fototeca: el usuario elige una imagen concreta y solo se
/// entrega esa.
struct SelectorFoto: View {

    /// Ruta actual (`/api/imagenes/12`) o nil si no hay foto.
    let urlActual: String?

    /// Recibe la nueva ruta ya subida.
    let alSubir: (String) -> Void

    @State private var seleccion: PhotosPickerItem?
    @State private var subiendo = false
    @State private var progreso = 0
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let urlActual, let imagen = AppConfig.imagenURL(urlActual) {
                AsyncImage(url: imagen) { fase in
                    if let foto = fase.image {
                        foto.resizable().scaledToFill()
                    } else {
                        marcador
                    }
                }
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                marcador
                    .frame(height: 110)
                    .frame(maxWidth: .infinity)
                    .background(Tema.fondo)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            PhotosPicker(selection: $seleccion,
                         matching: .images,
                         photoLibrary: .shared()) {
                HStack(spacing: 7) {
                    if subiendo {
                        ProgressView().tint(Tema.azul)
                    } else {
                        Image(systemName: urlActual == nil ? "photo.badge.plus" : "arrow.triangle.2.circlepath")
                    }
                    Text(subiendo
                         ? "Subiendo \(progreso)%"
                         : (urlActual == nil ? "Elegir foto" : "Cambiar foto"))
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Tema.azul.opacity(0.10))
                .foregroundStyle(Tema.azul)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(subiendo)

            if let error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(Tema.peligro)
            }
        }
        .onChange(of: seleccion) { _, nueva in
            guard let nueva else { return }
            Task { await subir(nueva) }
        }
    }

    private var marcador: some View {
        ZStack {
            Tema.fondo
            Image(systemName: "photo")
                .font(.system(size: 26))
                .foregroundStyle(Tema.textoSecundario.opacity(0.5))
        }
    }

    // MARK: - Subida

    private func subir(_ item: PhotosPickerItem) async {
        subiendo = true
        error = nil
        progreso = 0

        defer {
            subiendo = false
            // Se limpia para poder elegir la misma foto otra vez.
            seleccion = nil
        }

        do {
            guard let datos = try await item.loadTransferable(type: Data.self) else {
                error = "No se pudo leer la imagen."
                return
            }

            // Se reescala antes de enviar: una foto de 48 MP pesa 10 MB y el
            // backend rechaza por encima de 8 MB.
            guard let reducida = ImagenLocal.reducir(datos, ladoMaximo: 2000) else {
                error = "Formato de imagen no admitido."
                return
            }

            progreso = 50

            let subida = try await HotelAPI.shared.subirImagen(
                datos: reducida, nombre: "foto.jpg")

            progreso = 100
            alSubir(subida.url)
        } catch let apiError as APIError {
            error = apiError.mensajeUsuario
        } catch {
            self.error = "No se pudo subir la foto."
        }
    }
}

/// Utilidades de imagen en el dispositivo.
enum ImagenLocal {

    /// Reduce a `ladoMaximo` y devuelve JPEG. Nil si no es una imagen.
    static func reducir(_ datos: Data, ladoMaximo: CGFloat) -> Data? {
        guard let imagen = UIImage(data: datos) else { return nil }

        let mayor = max(imagen.size.width, imagen.size.height)
        guard mayor > 0 else { return nil }

        let factor = min(1, ladoMaximo / mayor)
        let tamano = CGSize(width: imagen.size.width * factor,
                            height: imagen.size.height * factor)

        let formato = UIGraphicsImageRendererFormat.default()
        formato.scale = 1

        let render = UIGraphicsImageRenderer(size: tamano, format: formato)
        let escalada = render.image { _ in
            imagen.draw(in: CGRect(origin: .zero, size: tamano))
        }

        return escalada.jpegData(compressionQuality: 0.85)
    }
}
