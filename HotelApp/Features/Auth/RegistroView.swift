import UIKit
import SwiftUI

/// Registro de cliente.
struct RegistroView: View {

    @Environment(SesionStore.self) private var sesion
    @Environment(\.dismiss) private var dismiss

    @State private var nombre = ""
    @State private var email = ""
    @State private var telefono = ""
    @State private var password = ""
    @State private var confirmar = ""
    @State private var error: String?

    private var valido: Bool {
        nombre.trimmingCharacters(in: .whitespaces).count >= 3
            && email.contains("@") && email.contains(".")
            && password.count >= 8
            && password == confirmar
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    campo("Nombre completo", texto: $nombre, contenido: .name)
                    campo("Correo electrónico", texto: $email, contenido: .emailAddress,
                          teclado: .emailAddress)
                    campo("Teléfono (opcional)", texto: $telefono, contenido: .telephoneNumber,
                          teclado: .phonePad)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Contraseña")
                            .font(.system(size: 12, weight: .semibold))
                        SecureField("Mínimo 8 caracteres", text: $password)
                            .textContentType(.newPassword)
                            .padding(11)
                            .background(Tema.fondo)
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Confirmar contraseña")
                            .font(.system(size: 12, weight: .semibold))
                        SecureField("Repite la contraseña", text: $confirmar)
                            .textContentType(.newPassword)
                            .padding(11)
                            .background(Tema.fondo)
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                    }

                    if !confirmar.isEmpty && password != confirmar {
                        Aviso(tipo: .peligro, titulo: nil,
                              mensaje: "Las contraseñas no coinciden.")
                    }

                    if let error {
                        Aviso(tipo: .peligro, titulo: "No se pudo registrar", mensaje: error)
                    }

                    BotonPrincipal(titulo: "Crear cuenta", icono: "person.badge.plus",
                                   cargando: sesion.cargando,
                                   deshabilitado: !valido) {
                        Task { await registrar() }
                    }
                }
                .padding(16)
            }
            .background(Tema.fondo.ignoresSafeArea())
            .navigationTitle("Crear cuenta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
    }

    private func campo(_ etiqueta: String, texto: Binding<String>,
                       contenido: UITextContentType?,
                       teclado: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(etiqueta).font(.system(size: 12, weight: .semibold))
            TextField("", text: texto)
                .textContentType(contenido)
                .keyboardType(teclado)
                .textInputAutocapitalization(teclado == .emailAddress ? .never : .words)
                .autocorrectionDisabled(teclado == .emailAddress)
                .padding(11)
                .background(Tema.fondo)
                .clipShape(RoundedRectangle(cornerRadius: 9))
        }
    }

    private func registrar() async {
        error = nil
        let resultado = await sesion.registrar(
            nombre: nombre, email: email, password: password,
            telefono: telefono.isEmpty ? nil : telefono)

        switch resultado {
        case .exito:
            dismiss()
        case .fallo(let mensaje, _, _):
            error = mensaje
        case .bloqueado(_, let mensaje):
            error = mensaje
        }
    }
}
