import SwiftUI

/// Gestión de usuarios (solo ADMIN).
///
/// Consume `/admin/usuarios`: listar, buscar, crear, resetear contraseña,
/// activar/desactivar y desbloquear cuentas.
///
/// El caso que motivó esta pantalla es de mostrador: un huésped se equivoca
/// varias veces con su contraseña, la cuenta queda bloqueada y está delante
/// del recepcionista esperando. Mandarlo a "abre la web" no es viable, por eso
/// el desbloqueo vive aquí y no solo en el back office.
struct UsuariosAdminView: View {

    @State private var usuarios: [Usuario] = []
    @State private var cargando = true
    @State private var error: String?
    @State private var busqueda = ""
    @State private var seleccionado: Usuario?
    @State private var mostrarCrear = false
    @State private var soloBloqueados = false

    private let api = HotelAPI.shared

    /// Filtro local por nombre, correo o rol. Con 300 cuartos y una plantilla
    /// grande, buscar en el servidor por cada tecla sería peor que filtrar
    /// los ~20 usuarios ya descargados.
    private var filtrados: [Usuario] {
        let termino = busqueda.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var lista = usuarios
        if !termino.isEmpty {
            lista = lista.filter {
                $0.nombre.lowercased().contains(termino)
                    || $0.email.lowercased().contains(termino)
                    || $0.nombresRol.joined(separator: " ").lowercased().contains(termino)
            }
        }
        if soloBloqueados {
            lista = lista.filter { !$0.activo }
        }
        return lista
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let error {
                    Aviso(tipo: .peligro, titulo: "Error", mensaje: error)
                }

                filtros

                if cargando && usuarios.isEmpty {
                    esqueleto
                } else if filtrados.isEmpty {
                    EstadoVacio(icono: "person.2",
                                titulo: busqueda.isEmpty ? "Sin usuarios" : "Sin resultados",
                                mensaje: busqueda.isEmpty
                                  ? "Crea el primer usuario con el botón +."
                                  : "No hay usuarios que coincidan con la búsqueda.")
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(filtrados) { u in
                            Button {
                                seleccionado = u
                            } label: {
                                tarjeta(u)
                            }
                            .buttonStyle(EstiloPresionable())
                            .accessibilityLabel("\(u.nombre), \(u.email), "
                                                + "\(u.nombresRol.joined(separator: ", ")), "
                                                + (u.activo ? "activo" : "inactivo"))
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
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
                .accessibilityLabel("Crear usuario")
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

    // MARK: - Filtros

    private var filtros: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.subheadline)
                    .foregroundStyle(Tema.textoSecundario)

                TextField("Buscar por nombre, correo o rol", text: $busqueda)
                    .font(.subheadline)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if !busqueda.isEmpty {
                    Button {
                        busqueda = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Tema.textoSecundario)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Borrar búsqueda")
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(Tema.superficie)
            .clipShape(RoundedRectangle(cornerRadius: Tema.radioPequeno,
                                        style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Tema.radioPequeno,
                                 style: .continuous)
                    .stroke(Tema.borde, lineWidth: 1))

            HStack(spacing: 8) {
                Text("\(filtrados.count) usuario(s)")
                    .font(.caption)
                    .foregroundStyle(Tema.textoSecundario)

                Spacer(minLength: 0)

                Toggle(isOn: $soloBloqueados) {
                    Text("Solo bloqueados")
                        .font(.caption.weight(.semibold))
                }
                .toggleStyle(.button)
                .tint(Tema.peligro)
            }
        }
    }

    // MARK: - Tarjeta

    private func tarjeta(_ u: Usuario) -> some View {
        Tarjeta(padding: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(u.activo ? Tema.azul.opacity(0.12)
                                       : Tema.textoSecundario.opacity(0.12))
                        .frame(width: 42, height: 42)

                    Text(iniciales(u))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(u.activo ? Tema.azul : Tema.textoSecundario)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(u.nombre)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Tema.texto)
                        .lineLimit(1)

                    Text(u.email)
                        .font(.caption)
                        .foregroundStyle(Tema.textoSecundario)
                        .lineLimit(1)

                    Text(u.nombresRol.joined(separator: " · "))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Tema.azul)
                        .lineLimit(1)

                    if let sede = u.sedePrincipal {
                        Label(sede.nombre, systemImage: "building.2")
                            .font(.caption2)
                            .foregroundStyle(Tema.textoSecundario)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                EtiquetaEstado(texto: u.activo ? "Activo" : "Inactivo",
                               color: u.activo ? Tema.exito : Tema.peligro)
            }
        }
    }

    private func iniciales(_ u: Usuario) -> String {
        let letras = u.iniciales.trimmingCharacters(in: .whitespacesAndNewlines)
        if !letras.isEmpty { return letras }
        return String(u.nombre.prefix(1)).uppercased()
    }

    private var esqueleto: some View {
        LazyVStack(spacing: 10) {
            ForEach(0..<5, id: \.self) { _ in
                Tarjeta(padding: 14) {
                    HStack(spacing: 12) {
                        Circle().fill(Tema.textoSecundario.opacity(0.15))
                            .frame(width: 42, height: 42)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Nombre Apellido").font(.subheadline)
                            Text("correo@hotel.com").font(.caption)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
    }

    // MARK: - Carga

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

// MARK: - Alta de usuario

/// Alta de usuario con rol y sedes.
struct CrearUsuarioSheet: View {

    let alCrear: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var nombre = ""
    @State private var email = ""
    @State private var password = ""
    @State private var telefono = ""
    @State private var rolSeleccionado = "RECEPCIONISTA"
    @State private var sedes: [Sede] = []
    @State private var sedesMarcadas: Set<Int> = []

    @State private var guardando = false
    @State private var error: String?

    private let api = HotelAPI.shared

    /// Roles que un admin puede asignar desde el móvil. "CLIENTE" se excluye:
    /// los clientes se registran solos y no deben crearse a mano.
    private let roles = ["RECEPCIONISTA", "HOUSEKEEPING", "GERENTE", "ADMIN"]

    private var nombreLimpio: String {
        nombre.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var emailLimpio: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var valido: Bool {
        nombreLimpio.count >= 3
            && emailLimpio.contains("@") && emailLimpio.contains(".")
            && password.count >= 8
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Tarjeta {
                        VStack(spacing: 14) {
                            campo("Nombre completo", $nombre)
                            campo("Correo", $email, teclado: .emailAddress)
                            campo("Teléfono (opcional)", $telefono, teclado: .phonePad)

                            VStack(alignment: .leading, spacing: 5) {
                                Text("Contraseña")
                                    .font(.subheadline.weight(.semibold))
                                SecureField("Mínimo 8 caracteres", text: $password)
                                    .textContentType(.newPassword)
                                    .font(.body)
                                    .padding(11)
                                    .background(Tema.fondo)
                                    .clipShape(RoundedRectangle(
                                        cornerRadius: Tema.radioPequeno,
                                        style: .continuous))
                            }
                        }
                    }

                    Tarjeta {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Rol")
                                .font(.subheadline.weight(.semibold))

                            Picker("Rol", selection: $rolSeleccionado) {
                                ForEach(roles, id: \.self) { Text($0).tag($0) }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(Tema.fondo)
                            .clipShape(RoundedRectangle(cornerRadius: Tema.radioPequeno,
                                                        style: .continuous))
                        }
                    }

                    if !sedes.isEmpty {
                        Tarjeta {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Sedes asignadas")
                                    .font(.subheadline.weight(.semibold))

                                Text("Sin marcar ninguna, el usuario no podrá operar "
                                     + "en ninguna sede.")
                                    .font(.caption)
                                    .foregroundStyle(Tema.textoSecundario)

                                ForEach(sedes) { sede in
                                    Toggle(sede.nombre, isOn: Binding(
                                        get: { sedesMarcadas.contains(sede.id) },
                                        set: { marcado in
                                            if marcado { sedesMarcadas.insert(sede.id) }
                                            else { sedesMarcadas.remove(sede.id) }
                                        }))
                                        .font(.subheadline)
                                }
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
            Text(etiqueta)
                .font(.subheadline.weight(.semibold))
            TextField("", text: texto)
                .keyboardType(teclado)
                .textInputAutocapitalization(teclado == .emailAddress ? .never : .words)
                .autocorrectionDisabled(teclado == .emailAddress)
                .font(.body)
                .padding(11)
                .background(Tema.fondo)
                .clipShape(RoundedRectangle(cornerRadius: Tema.radioPequeno,
                                            style: .continuous))
        }
    }

    private func crear() async {
        guard !guardando else { return }
        guardando = true
        error = nil

        do {
            _ = try await api.crearUsuario(CrearUsuarioRequest(
                nombre: nombreLimpio,
                email: emailLimpio,
                password: password,
                telefono: telefono.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil : telefono,
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

// MARK: - Detalle de usuario

/// Acciones sobre un usuario: desbloquear, resetear contraseña y
/// activar/desactivar la cuenta.
struct DetalleUsuarioSheet: View {

    let usuario: Usuario
    let alActualizar: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var nuevaPassword = ""
    @State private var procesando = false
    @State private var error: String?
    @State private var mensaje: String?
    @State private var bloqueo: BloqueoCuenta?
    @State private var mostrarBloqueo = false

    private let api = HotelAPI.shared

    private var passwordLimpia: String {
        nuevaPassword.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    cabecera

                    if let bloqueo, bloqueo.bloqueado {
                        Tarjeta {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Cuenta bloqueada", systemImage: "lock.fill")
                                    .font(.headline)
                                    .foregroundStyle(Tema.peligro)

                                Text("\(bloqueo.intentosFallidos) intento(s) fallido(s) · "
                                     + "nivel \(bloqueo.nivelBloqueo)")
                                    .font(.caption)
                                    .foregroundStyle(Tema.textoSecundario)

                                if let reintentar = bloqueo.reintentarEnSegundos,
                                   reintentar > 0 {
                                    Text("Se desbloquea sola en \(reintentar) s.")
                                        .font(.caption)
                                        .foregroundStyle(Tema.textoSecundario)
                                }

                                BotonPrincipal(titulo: "Desbloquear cuenta",
                                               icono: "lock.open",
                                               cargando: procesando) {
                                    Task { await desbloquear() }
                                }
                            }
                        }
                    }

                    Tarjeta {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Resetear contraseña")
                                .font(.headline)

                            Text("El usuario tendrá que iniciar sesión de nuevo.")
                                .font(.caption)
                                .foregroundStyle(Tema.textoSecundario)

                            SecureField("Nueva contraseña (mín. 8)", text: $nuevaPassword)
                                .textContentType(.newPassword)
                                .font(.body)
                                .padding(10)
                                .background(Tema.fondo)
                                .clipShape(RoundedRectangle(cornerRadius: Tema.radioPequeno,
                                                            style: .continuous))

                            BotonPrincipal(titulo: "Aplicar",
                                           icono: "key.fill",
                                           cargando: procesando,
                                           deshabilitado: passwordLimpia.count < 8) {
                                Task { await resetPassword() }
                            }
                        }
                    }

                    Tarjeta {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Bloqueo de acceso")
                                .font(.headline)

                            if usuario.activo {
                                Text("Suspende la cuenta para que no pueda iniciar sesión. "
                                     + "Se cierran sus sesiones abiertas y se guarda el motivo.")
                                    .font(.caption)
                                    .foregroundStyle(Tema.textoSecundario)

                                Button(role: .destructive) {
                                    mostrarBloqueo = true
                                } label: {
                                    Label("Bloquear el acceso", systemImage: "hand.raised.fill")
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                        .frame(minHeight: 44)
                                        .background(Tema.peligro.opacity(0.10))
                                        .foregroundStyle(Tema.peligro)
                                        .clipShape(RoundedRectangle(
                                            cornerRadius: Tema.radioPequeno,
                                            style: .continuous))
                                }
                                .buttonStyle(EstiloPresionable())
                                .disabled(procesando)
                                .accessibilityLabel("Bloquear el acceso de \(usuario.nombre)")
                            } else {
                                Text("Esta cuenta está bloqueada: no puede iniciar sesión.")
                                    .font(.caption)
                                    .foregroundStyle(Tema.textoSecundario)

                                if let motivo = usuario.motivoDesactivacion,
                                   !motivo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text("Motivo: \(motivo)")
                                        .font(.caption)
                                        .foregroundStyle(Tema.alerta)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                BotonPrincipal(titulo: "Restablecer el acceso",
                                               icono: "lock.open",
                                               cargando: procesando) {
                                    Task { await cambiarEstado(motivo: nil) }
                                }
                            }
                        }
                    }

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
            .sheet(isPresented: $mostrarBloqueo) {
                BloquearAccesoSheet(nombre: usuario.nombre) { motivo in
                    await cambiarEstado(motivo: motivo)
                }
            }
        }
    }

    private var cabecera: some View {
        Tarjeta {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Tema.azul.opacity(0.12))
                            .frame(width: 48, height: 48)
                        Text(usuario.iniciales.isEmpty
                             ? String(usuario.nombre.prefix(1)).uppercased()
                             : usuario.iniciales)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(Tema.azul)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(usuario.nombre)
                            .font(.headline)
                            .foregroundStyle(Tema.texto)
                        Text(usuario.email)
                            .font(.caption)
                            .foregroundStyle(Tema.textoSecundario)
                    }

                    Spacer(minLength: 0)

                    EtiquetaEstado(texto: usuario.activo ? "Activo" : "Inactivo",
                                   color: usuario.activo ? Tema.exito : Tema.peligro)
                }

                Text(usuario.nombresRol.joined(separator: " · "))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Tema.azul)

                if usuario.sedes.isEmpty {
                    Label("Sin sedes asignadas", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Tema.alerta)
                } else {
                    Label(usuario.sedes.map(\.nombre).joined(separator: ", "),
                          systemImage: "building.2")
                        .font(.caption)
                        .foregroundStyle(Tema.textoSecundario)
                }
            }
        }
    }

    // MARK: - Acciones

    private func resetPassword() async {
        guard !procesando else { return }
        procesando = true
        error = nil
        mensaje = nil

        do {
            _ = try await api.resetPassword(id: usuario.id, password: passwordLimpia)
            mensaje = "Contraseña actualizada. El usuario debe volver a entrar."
            nuevaPassword = ""
        } catch let apiError as APIError {
            error = apiError.mensajeUsuario
        } catch {
            self.error = "No se pudo resetear la contraseña."
        }

        procesando = false
    }

    private func cambiarEstado(motivo: String?) async {
        guard !procesando else { return }
        procesando = true
        error = nil
        mensaje = nil

        do {
            _ = try await api.cambiarEstadoUsuario(
                id: usuario.id,
                activo: !usuario.activo,
                motivo: usuario.activo ? motivo : nil)
            mensaje = usuario.activo ? "Acceso bloqueado." : "Acceso restablecido."
            await alActualizar()
        } catch let apiError as APIError {
            error = apiError.mensajeUsuario
        } catch {
            self.error = "No se pudo cambiar el estado."
        }

        procesando = false
    }

    private func desbloquear() async {
        guard !procesando else { return }
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

// MARK: - Bloqueo de acceso

/// Motivo del bloqueo.
///
/// El backend rechaza la desactivación sin motivo (`MOTIVO_REQUERIDO`), así
/// que se pide aquí en lugar de escribir un texto genérico: el motivo queda
/// guardado en la cuenta y es lo que después explica por qué se le cerró el
/// acceso a esa persona.
struct BloquearAccesoSheet: View {

    let nombre: String
    let alConfirmar: (String) async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var motivo = ""
    @State private var enviando = false

    /// Motivos frecuentes en recepción. Rellenan el campo y el admin puede
    /// editarlos antes de confirmar.
    private let sugerencias = [
        "Conducta inapropiada con el personal",
        "Daños a las instalaciones",
        "Impago pendiente",
        "Uso indebido de la cuenta",
        "Solicitud del propio huésped",
    ]

    private var motivoLimpio: String {
        motivo.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var valido: Bool { motivoLimpio.count >= 5 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Aviso(tipo: .alerta, titulo: "Vas a bloquear el acceso",
                          mensaje: "\(nombre) no podrá iniciar sesión y se cerrarán "
                                 + "sus sesiones abiertas hasta que lo restablezcas.")

                    Tarjeta {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Motivo")
                                .font(.subheadline.weight(.semibold))

                            TextField("Explica brevemente por qué se bloquea",
                                      text: $motivo, axis: .vertical)
                                .lineLimit(2...4)
                                .font(.body)
                                .padding(10)
                                .background(Tema.fondo)
                                .clipShape(RoundedRectangle(
                                    cornerRadius: Tema.radioPequeno,
                                    style: .continuous))

                            Text("\(motivoLimpio.count)/255")
                                .font(.caption2)
                                .foregroundStyle(Tema.textoSecundario)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Motivos frecuentes")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Tema.textoSecundario)
                            .padding(.leading, 4)

                        ForEach(sugerencias, id: \.self) { sugerencia in
                            Button {
                                motivo = sugerencia
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: motivo == sugerencia
                                          ? "checkmark.circle.fill"
                                          : "circle")
                                        .font(.subheadline)
                                        .foregroundStyle(motivo == sugerencia
                                                         ? Tema.azul : Tema.textoSecundario)

                                    Text(sugerencia)
                                        .font(.subheadline)
                                        .foregroundStyle(Tema.texto)
                                        .multilineTextAlignment(.leading)

                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 14)
                                .frame(minHeight: 44)
                                .background(Tema.superficie)
                                .clipShape(RoundedRectangle(
                                    cornerRadius: Tema.radioPequeno,
                                    style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Tema.radioPequeno,
                                                     style: .continuous)
                                        .stroke(Tema.borde, lineWidth: 1))
                            }
                            .buttonStyle(EstiloPresionable())
                        }
                    }

                    BotonPrincipal(titulo: "Bloquear acceso",
                                   icono: "hand.raised.fill",
                                   cargando: enviando,
                                   deshabilitado: !valido) {
                        Task {
                            enviando = true
                            await alConfirmar(motivoLimpio)
                            enviando = false
                            dismiss()
                        }
                    }
                }
                .padding(16)
            }
            .background(Tema.fondo.ignoresSafeArea())
            .navigationTitle("Bloquear acceso")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
