import SwiftUI

/// Perfil del usuario.
///
/// Incluye datos de cuenta, cambio de contraseña con Face ID y cierre de sesión.
struct PerfilView: View {

    let usuario: Usuario

    @Environment(SesionStore.self) private var sesion

    @State private var confirmarSalida = false
    @State private var mostrarCambioPassword = false
    @State private var biometriaDisponible = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                cabecera

                Tarjeta {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Datos de la cuenta")
                            .font(.system(size: 13, weight: .semibold))

                        fila("Nombre", usuario.nombre)
                        fila("Correo", usuario.email)
                        fila("Roles", usuario.nombresRol.joined(separator: ", "))
                        if let sede = usuario.sedePrincipal {
                            fila("Sede", sede.nombre)
                        }
                        if let telefono = usuario.telefono {
                            fila("Teléfono", telefono)
                        }
                        if let ultimo = usuario.ultimoLogin {
                            fila("Último acceso",
                                 FechaAPI.formatearConHora(FechaAPI.parsear(ultimo)))
                        }
                    }
                }

                Tarjeta {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Seguridad")
                            .font(.system(size: 13, weight: .semibold))

                        Label("Token guardado en el Keychain de iOS",
                              systemImage: "lock.shield")
                            .font(.system(size: 11))
                            .foregroundStyle(Tema.textoSecundario)

                        Label(biometriaDisponible
                              ? "Face ID disponible"
                              : "Face ID no configurado",
                              systemImage: biometriaDisponible
                              ? "faceid" : "faceid")
                            .font(.system(size: 11))
                            .foregroundStyle(biometriaDisponible
                                             ? Tema.exito : Tema.textoSecundario)

                        Button {
                            Task { await abrirCambioPassword() }
                        } label: {
                            Label("Cambiar contraseña", systemImage: "key")
                                .font(.system(size: 12, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Tema.azulClaro)
                                .foregroundStyle(Tema.azul)
                                .clipShape(RoundedRectangle(cornerRadius: 9))
                        }
                    }
                }

                if sesion.esAdmin {
                    Tarjeta {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Administración")
                                .font(.system(size: 13, weight: .semibold))

                            NavigationLink {
                                UsuariosAdminView()
                            } label: {
                                Label("Gestionar usuarios", systemImage: "person.2.badge.gearshape")
                                    .font(.system(size: 12, weight: .medium))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 12)
                                    .background(Tema.fondo)
                                    .clipShape(RoundedRectangle(cornerRadius: 9))
                            }
                            .buttonStyle(.plain)

                            NavigationLink {
                                SedesAdminView()
                            } label: {
                                Label("Sedes y fotos", systemImage: "building.2")
                                    .font(.system(size: 12, weight: .medium))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 12)
                                    .background(Tema.fondo)
                                    .clipShape(RoundedRectangle(cornerRadius: 9))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Button(role: .destructive) {
                    confirmarSalida = true
                } label: {
                    Label("Cerrar sesión", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 14, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Tema.peligro.opacity(0.08))
                        .foregroundStyle(Tema.peligro)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Text("Hotel PMS · v2.0 · Piura, Perú")
                    .font(.system(size: 10))
                    .foregroundStyle(Tema.textoSecundario)
            }
            .padding(16)
        }
        .background(Tema.fondo.ignoresSafeArea())
        .navigationTitle("Perfil")
        .navigationBarTitleDisplayMode(.inline)
        .task { biometriaDisponible = BiometriaService.disponible }
        .sheet(isPresented: $mostrarCambioPassword) {
            CambiarPasswordSheet()
        }
        .confirmationDialog("¿Cerrar sesión?", isPresented: $confirmarSalida,
                            titleVisibility: .visible) {
            Button("Cerrar sesión", role: .destructive) {
                Task { await sesion.cerrarSesion() }
            }
            Button("Cancelar", role: .cancel) {}
        }
    }

    // MARK: - Subvistas

    private var cabecera: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Tema.azulClaro)
                    .frame(width: 84, height: 84)

                Text(usuario.iniciales.isEmpty
                     ? String(usuario.nombre.prefix(1)).uppercased()
                     : usuario.iniciales)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Tema.azulOscuro)
            }

            Text(usuario.nombre)
                .font(.system(size: 20, weight: .bold, design: .rounded))

            Text(usuario.email)
                .font(.system(size: 12))
                .foregroundStyle(Tema.textoSecundario)

            EtiquetaEstado(texto: usuario.roles.first?.nombre ?? "—",
                           color: Tema.azul,
                           icono: "person.badge.key")
        }
        .padding(.vertical, 20)
    }

    private func fila(_ etiqueta: String, _ valor: String) -> some View {
        HStack {
            Text(etiqueta)
                .font(.system(size: 12))
                .foregroundStyle(Tema.textoSecundario)
            Spacer()
            Text(valor)
                .font(.system(size: 12, weight: .medium))
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Acciones

    /// Face ID antes de abrir el cambio de contraseña.
    private func abrirCambioPassword() async {
        if BiometriaService.disponible {
            let ok = await sesion.verificarIdentidad(
                motivo: "Confirma tu identidad para cambiar la contraseña")
            guard ok else { return }
        }
        mostrarCambioPassword = true
    }
}

/// Cambio de contraseña del propio usuario.
///
/// El backend, al cambiarla, incrementa `credencialesVersion`: el token que
/// está usando la app deja de valer inmediatamente (el filtro JWT lo rechaza
/// con `401 NO_AUTENTICADO`). Por eso, tras un cambio exitoso, se cierra la
/// sesión y se vuelve al login en lugar de dejarle con un token muerto.
struct CambiarPasswordSheet: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(SesionStore.self) private var sesion

    @State private var actual = ""
    @State private var nueva = ""
    @State private var confirmar = ""
    @State private var guardando = false
    @State private var error: String?
    @State private var exito = false

    private let api = HotelAPI.shared

    private var valido: Bool {
        actual.count >= 8 && nueva.count >= 8 && nueva == confirmar
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    campo("Contraseña actual", texto: $actual)
                    campo("Nueva contraseña", texto: $nueva)
                    campo("Confirmar nueva contraseña", texto: $confirmar)

                    if !confirmar.isEmpty && nueva != confirmar {
                        Aviso(tipo: .peligro, titulo: nil,
                              mensaje: "Las contraseñas no coinciden.")
                    }

                    if let error {
                        Aviso(tipo: .peligro, titulo: "No se pudo cambiar", mensaje: error)
                    }

                    if exito {
                        Aviso(tipo: .exito, titulo: "Listo",
                              mensaje: "Contraseña actualizada.")
                    }

                    BotonPrincipal(titulo: "Guardar", icono: "checkmark",
                                   cargando: guardando, deshabilitado: !valido) {
                        Task { await guardar() }
                    }
                }
                .padding(16)
            }
            .background(Tema.fondo.ignoresSafeArea())
            .navigationTitle("Cambiar contraseña")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }

    private func campo(_ etiqueta: String, texto: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(etiqueta).font(.system(size: 12, weight: .semibold))
            SecureField("Mínimo 8 caracteres", text: texto)
                .textContentType(.newPassword)
                .padding(11)
                .background(Tema.fondo)
                .clipShape(RoundedRectangle(cornerRadius: 9))
        }
    }

    private func guardar() async {
        guard !guardando else { return }
        guardando = true
        error = nil
        exito = false

        do {
            // 204 sin cuerpo: si esto no lanza, el cambio se aplicó.
            try await api.cambiarPassword(actual: actual, nueva: nueva)
            exito = true
            actual = ""
            nueva = ""
            confirmar = ""

            // El token acaba de quedar inválido en el servidor. Se cierra
            // sesión local (sin volver a llamar a /auth/cerrar-sesiones, que
            // respondería 401) para que el usuario entre con la nueva.
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            dismiss()
            await sesion.cerrarSesionLocal()
        } catch let apiError as APIError {
            error = apiError.mensajeUsuario
        } catch {
            self.error = "No se pudo cambiar la contraseña."
        }

        guardando = false
    }
}
