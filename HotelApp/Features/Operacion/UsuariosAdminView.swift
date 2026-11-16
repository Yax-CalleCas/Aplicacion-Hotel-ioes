import SwiftUI

/// Gestión de usuarios (solo ADMIN).
///
/// Consume `/admin/usuarios`: listar, crear, cambiar estado, resetear
/// contraseña y desbloquear cuentas.
struct UsuariosAdminView: View {

    @State private var usuarios: [Usuario] = []
    @State private var cargando = true
    @State private var error: String?
    @State private var mensaje: String?
    @State private var seleccionado: Usuario?
    @State private var mostrarCrear = false

    private let api = HotelAPI.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let error {
                    Aviso(tipo: .peligro, titulo: "Error", mensaje: error)
                }
                if let mensaje {
                    Aviso(tipo: .exito, titulo: "Listo", mensaje: mensaje)
                }

                if cargando && usuarios.isEmpty {
                    ProgressView().padding(.top, 40)
                } else if usuarios.isEmpty {
                    EstadoVacio(icono: "person.2",
                                titulo: "Sin usuarios",
                                mensaje: "Crea el primer usuario con el botón +.")
                } else {
                    ForEach(usuarios) { u in
                        Button {
                            seleccionado = u
                        } label: {
                            tarjeta(u)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
        }
        .background(Tema.fondo.ignoresSafeArea())
        .navigationTitle("Usuarios")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    mostrarCrear = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .refreshable { await cargar() }
        .task { await cargar() }
        .sheet(isPresented: $mostrarCrear) {
            CrearUsuarioSheet { await cargar() }
        }
        .sheet(item: $seleccionado) { u in
            DetalleUsuarioSheet(usuario: u) { await cargar() }
        }
    }

    private func tarjeta(_ u: Usuario) -> some View {
        Tarjeta {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle().fill(Tema.azulClaro).frame(width: 40, height: 40)
                    Text(u.iniciales.isEmpty
                         ? String(u.nombre.prefix(1)).uppercased()
                         : u.iniciales)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Tema.azulOscuro)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(u.nombre)
                        .font(.system(size: 13, weight: .semibold))
                    Text(u.email)
                        .font(.system(size: 11))
                        .foregroundStyle(Tema.textoSecundario)
                    Text(u.nombresRol.joined(separator: " · "))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Tema.azul)
                }

                Spacer()

                EtiquetaEstado(texto: u.activo ? "Activo" : "Inactivo",
                               color: u.activo ? Tema.exito : Tema.peligro)
            }
        }
    }

    private func cargar() async {
        cargando = true
        error = nil

        do {
            usuarios = try await api.usuarios()
        } catch let apiError as APIError {
            error = apiError.mensajeUsuario
        } catch {
            self.error = "No se pudieron cargar los usuarios."
        }

        cargando = false
    }
}

/// Alta de usuario con rol y sedes.
struct CrearUsuarioSheet: View {

    let alCrear: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var nombre = ""
    @State private var email = ""
    @State private var password = ""
    @State private var telefono = ""
    @State private var rolSeleccionado = "CLIENTE"
    @State private var sedes: [Sede] = []
    @State private var sedesMarcadas: Set<Int> = []

    @State private var guardando = false
    @State private var error: String?

    private let api = HotelAPI.shared
    private let roles = ["CLIENTE", "RECEPCIONISTA", "HOUSEKEEPING", "GERENTE", "ADMIN"]

    private var valido: Bool {
        nombre.trimmingCharacters(in: .whitespaces).count >= 3
            && email.contains("@") && password.count >= 8
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    campo("Nombre completo", $nombre)
                    campo("Correo", $email, teclado: .emailAddress)
                    campo("Teléfono (opcional)", $telefono, teclado: .phonePad)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Contraseña").font(.system(size: 12, weight: .semibold))
                        SecureField("Mínimo 8 caracteres", text: $password)
                            .textContentType(.newPassword)
                            .padding(11)
                            .background(Tema.fondo)
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Rol").font(.system(size: 12, weight: .semibold))
                        Picker("Rol", selection: $rolSeleccionado) {
                            ForEach(roles, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Tema.fondo)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                    }

                    if !sedes.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Sedes asignadas").font(.system(size: 12, weight: .semibold))
                            ForEach(sedes) { sede in
                                Toggle(sede.nombre, isOn: Binding(
                                    get: { sedesMarcadas.contains(sede.id) },
                                    set: { marcado in
                                        if marcado { sedesMarcadas.insert(sede.id) }
                                        else { sedesMarcadas.remove(sede.id) }
                                    }))
                                    .font(.system(size: 12))
                            }
                        }
                    }

                    if let error {
                        Aviso(tipo: .peligro, titulo: "No se pudo crear", mensaje: error)
                    }

                    BotonPrincipal(titulo: "Crear usuario", icono: "person.badge.plus",
                                   cargando: guardando, deshabilitado: !valido) {
                        Task { await crear() }
                    }
                }
                .padding(16)
            }
            .background(Tema.fondo.ignoresSafeArea())
            .navigationTitle("Nuevo usuario")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .task {
                if sedes.isEmpty {
                    sedes = (try? await api.sedesAdmin()) ?? []
                }
            }
        }
    }

    private func campo(_ etiqueta: String, _ texto: Binding<String>,
                       teclado: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(etiqueta).font(.system(size: 12, weight: .semibold))
            TextField("", text: texto)
                .keyboardType(teclado)
                .textInputAutocapitalization(teclado == .emailAddress ? .never : .words)
                .autocorrectionDisabled(teclado == .emailAddress)
                .padding(11)
                .background(Tema.fondo)
                .clipShape(RoundedRectangle(cornerRadius: 9))
        }
    }

    private func crear() async {
        guard !guardando else { return }
        guardando = true
        error = nil

        do {
            _ = try await api.crearUsuario(CrearUsuarioRequest(
                nombre: nombre.trimmingCharacters(in: .whitespaces),
                email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                password: password,
                telefono: telefono.isEmpty ? nil : telefono,
                roles: [rolSeleccionado],
                sedes: sedesMarcadas.isEmpty ? nil : Array(sedesMarcadas)))

            await alCrear()
            dismiss()
        } catch let apiError as APIError {
            error = apiError.mensajeUsuario
        } catch {
            self.error = "No se pudo crear el usuario."
        }

        guardando = false
    }
}

/// Acciones sobre un usuario: activar/desactivar, resetear y desbloquear.
struct DetalleUsuarioSheet: View {

    let usuario: Usuario
    let alActualizar: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var nuevaPassword = ""
    @State private var procesando = false
    @State private var error: String?
    @State private var mensaje: String?
    @State private var bloqueo: BloqueoCuenta?

    private let api = HotelAPI.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Tarjeta {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(usuario.nombre)
                                .font(.system(size: 17, weight: .semibold))
                            Text(usuario.email)
                                .font(.system(size: 12))
                                .foregroundStyle(Tema.textoSecundario)
                            Text(usuario.nombresRol.joined(separator: " · "))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Tema.azul)
                        }
                    }

                    if let bloqueo, bloqueo.bloqueado {
                        Aviso(tipo: .alerta, titulo: "Cuenta bloqueada",
                              mensaje: "\(bloqueo.intentosFallidos) intentos fallidos · nivel \(bloqueo.nivelBloqueo)")

                        BotonPrincipal(titulo: "Desbloquear cuenta",
                                       icono: "lock.open",
                                       cargando: procesando) {
                            Task { await desbloquear() }
                        }
                    }

                    Tarjeta {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Resetear contraseña")
                                .font(.system(size: 13, weight: .semibold))

                            SecureField("Nueva contraseña (mín. 8)", text: $nuevaPassword)
                                .textContentType(.newPassword)
                                .font(.system(size: 12))
                                .padding(10)
                                .background(Tema.fondo)
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            BotonPrincipal(titulo: "Aplicar",
                                           icono: "key",
                                           cargando: procesando,
                                           deshabilitado: nuevaPassword.count < 8) {
                                Task { await resetPassword() }
                            }
                        }
                    }

                    Button(role: usuario.activo ? .destructive : .none) {
                        Task { await cambiarEstado() }
                    } label: {
                        Label(usuario.activo ? "Desactivar cuenta" : "Activar cuenta",
                              systemImage: usuario.activo ? "person.crop.circle.badge.xmark"
                                                          : "person.crop.circle.badge.checkmark")
                            .font(.system(size: 13, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background((usuario.activo ? Tema.peligro : Tema.exito).opacity(0.1))
                            .foregroundStyle(usuario.activo ? Tema.peligro : Tema.exito)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(procesando)

                    if let error {
                        Aviso(tipo: .peligro, titulo: "Error", mensaje: error)
                    }
                    if let mensaje {
                        Aviso(tipo: .exito, titulo: "Listo", mensaje: mensaje)
                    }
                }
                .padding(16)
            }
            .background(Tema.fondo.ignoresSafeArea())
            .navigationTitle("Usuario")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .task {
                bloqueo = try? await api.estadoBloqueo(usuarioId: usuario.id)
            }
        }
    }

    private func resetPassword() async {
        procesando = true
        error = nil
        mensaje = nil

        do {
            _ = try await api.resetPassword(id: usuario.id, password: nuevaPassword)
            mensaje = "Contraseña actualizada."
            nuevaPassword = ""
        } catch let apiError as APIError {
            error = apiError.mensajeUsuario
        } catch {
            self.error = "No se pudo resetear la contraseña."
        }

        procesando = false
    }

    private func cambiarEstado() async {
        procesando = true
        error = nil
        mensaje = nil

        do {
            _ = try await api.cambiarEstadoUsuario(
                id: usuario.id,
                activo: !usuario.activo,
                motivo: usuario.activo ? "Desactivado desde iOS" : nil)
            mensaje = usuario.activo ? "Cuenta desactivada." : "Cuenta activada."
            await alActualizar()
        } catch let apiError as APIError {
            error = apiError.mensajeUsuario
        } catch {
            self.error = "No se pudo cambiar el estado."
        }

        procesando = false
    }

    private func desbloquear() async {
        procesando = true
        error = nil
        mensaje = nil

        do {
            try await api.desbloquear(usuarioId: usuario.id)
            bloqueo = try? await api.estadoBloqueo(usuarioId: usuario.id)
            mensaje = "Cuenta desbloqueada."
        } catch let apiError as APIError {
            error = apiError.mensajeUsuario
        } catch {
            self.error = "No se pudo desbloquear la cuenta."
        }

        procesando = false
    }
}
