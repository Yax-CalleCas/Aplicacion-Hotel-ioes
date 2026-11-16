import SwiftUI
import UIKit

/// Login de la app.
///
/// Diseño claro con relieve suave: fondo degradado, plato del logo con
/// sombras y campos tipo tarjeta flotante.
///
/// - Acceso social real (Facebook) y Apple visual.
/// - "Recordarme" guarda solo el correo; la contraseña nunca se almacena.
/// - Face ID desbloquea el JWT del Keychain.
struct LoginView: View {

    @Environment(SesionStore.self) private var sesion

    @State private var email = ""
    @State private var password = ""
    @State private var mostrarPassword = false
    @State private var recordarme = CredencialesRecordadas.activo
    @State private var error: String?
    @State private var errorEmail: String?
    @State private var errorPassword: String?
    @State private var intentosRestantes: Int?
    @State private var segundosBloqueo = 0
    @State private var temporizador: Timer?
    @State private var mostrarRegistro = false

    @State private var proveedorActivo: String?
    @State private var mostrandoSelector = false
    @State private var avisoVinculacion: String?

    @FocusState private var foco: Campo?

    private enum Campo { case email, password }

    private var formularioValido: Bool {
        email.contains("@") && email.contains(".") && password.count >= 6
    }

    private var bloqueado: Bool { segundosBloqueo > 0 }

    var body: some View {
        ZStack {
            fondo

            ScrollView {
                VStack(spacing: 0) {
                    logo

                    Text("Bienvenido de nuevo")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(Tema.tinta)
                        .padding(.top, 22)

                    Text("INICIA SESIÓN PARA CONTINUAR")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(2.2)
                        .foregroundStyle(Tema.tintaSuave)
                        .padding(.top, 5)

                    formulario
                        .padding(.top, 26)

                    divisor
                        .padding(.top, 24)

                    filaSocial
                        .padding(.top, 16)

                    enlaces
                        .padding(.top, 22)

                    if let avisoVinculacion {
                        Aviso(tipo: .alerta,
                              titulo: "Vinculación requerida",
                              mensaje: avisoVinculacion)
                            .padding(.top, 16)
                    }

                    pie
                        .padding(.top, 26)
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Tema.tintaFondo.ignoresSafeArea())
        .onAppear {
            if let guardado = CredencialesRecordadas.email, email.isEmpty {
                email = guardado
            }
        }
        .sheet(isPresented: $mostrarRegistro) { RegistroView() }
        .sheet(isPresented: $mostrandoSelector) {
            SelectorCuentaSocial { cuenta in
                mostrandoSelector = false
                Task { await entrarSocial(cuenta) }
            }
        }
        .onDisappear { detenerTemporizador() }
    }

    // MARK: - Fondo

    /// Degradado claro con círculos difusos: la base del estilo neumórfico.
    private var fondo: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.95, green: 0.97, blue: 0.99),
                         Color(red: 0.89, green: 0.93, blue: 0.98)],
                startPoint: .top,
                endPoint: .bottom)

            Circle()
                .fill(Color(red: 0.72, green: 0.82, blue: 0.98).opacity(0.55))
                .frame(width: 300, height: 300)
                .blur(radius: 70)
                .offset(x: -150, y: -330)

            Circle()
                .fill(Color(red: 0.78, green: 0.86, blue: 1.0).opacity(0.6))
                .frame(width: 260, height: 260)
                .blur(radius: 60)
                .offset(x: 160, y: -60)

            Circle()
                .fill(Color.white.opacity(0.85))
                .frame(width: 340, height: 340)
                .blur(radius: 70)
                .offset(x: 120, y: 380)
        }
        .ignoresSafeArea()
    }

    // MARK: - Logo

    private var logo: some View {
        ZStack {
            // Plato exterior con brillo: da la sensación de relieve.
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(.white)
                .frame(width: 128, height: 128)
                .shadow(color: Color(red: 0.55, green: 0.66, blue: 0.85).opacity(0.35),
                        radius: 18, x: 0, y: 10)
                .shadow(color: Color.white.opacity(0.9), radius: 6, x: -4, y: -4)

            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.98, green: 0.99, blue: 1.0),
                                 Color(red: 0.88, green: 0.93, blue: 0.99)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing))
                .frame(width: 108, height: 108)

            Image(systemName: "building.2.fill")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Tema.azul, Color(red: 0.22, green: 0.45, blue: 0.95)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing))
        }
        .padding(.top, 12)
    }

    // MARK: - Formulario

    private var formulario: some View {
        VStack(spacing: 14) {
            campoEmail
            campoPassword

            HStack {
                Button {
                    recordarme.toggle()
                    CredencialesRecordadas.activo = recordarme
                } label: {
                    HStack(spacing: 9) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(recordarme
                                      ? AnyShapeStyle(LinearGradient(
                                            colors: [Color(red: 0.20, green: 0.42, blue: 0.95),
                                                     Color(red: 0.36, green: 0.33, blue: 0.92)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing))
                                      : AnyShapeStyle(Color.white))
                                .frame(width: 24, height: 24)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .stroke(Color(red: 0.80, green: 0.86, blue: 0.95),
                                                lineWidth: 1))

                            if recordarme {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .heavy))
                                    .foregroundStyle(.white)
                            }
                        }

                        Text("Recordarme")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Tema.tinta)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    entrarConBiometria()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "faceid").font(.system(size: 14))
                        Text("Face ID").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(Color(red: 0.20, green: 0.42, blue: 0.95))
                }
                .buttonStyle(.plain)
                .disabled(sesion.cargando || bloqueado)
            }
            .padding(.top, 2)

            if let error {
                textoError(error)
            }

            botonEntrar
                .padding(.top, 4)
        }
    }

    /// Contenedor con relieve: sombra exterior + brillo interior.
    private func campoRelieve<Contenido: View>(@ViewBuilder _ contenido: () -> Contenido) -> some View {
        contenido()
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: Color(red: 0.60, green: 0.70, blue: 0.86).opacity(0.30),
                            radius: 10, x: 0, y: 6)
                    .shadow(color: .white, radius: 4, x: -3, y: -3))
    }

    private var botonEntrar: some View {
        Button {
            foco = nil
            Task { await entrar() }
        } label: {
            HStack(spacing: 8) {
                if sesion.cargando {
                    ProgressView().tint(.white)
                } else if bloqueado {
                    Image(systemName: "lock.fill").font(.system(size: 14))
                }

                Text(tituloBoton)
                    .font(.system(size: 17, weight: .semibold))

                Spacer()

                if !sesion.cargando && !bloqueado {
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.18))
                            .frame(width: 32, height: 32)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .bold))
                    }
                }
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.13, green: 0.35, blue: 0.96),
                             Color(red: 0.30, green: 0.30, blue: 0.93)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color(red: 0.20, green: 0.35, blue: 0.90).opacity(0.38),
                    radius: 14, y: 8)
            .opacity((!formularioValido || bloqueado) ? 0.55 : 1)
        }
        .disabled(!formularioValido || bloqueado || sesion.cargando)
    }

    // MARK: - Social y enlaces

    private var divisor: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color(red: 0.78, green: 0.85, blue: 0.94))
                .frame(height: 1)

            Text("O CONTINÚA CON")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(Tema.tintaSuave)
                .fixedSize()

            Rectangle()
                .fill(Color(red: 0.78, green: 0.85, blue: 0.94))
                .frame(height: 1)
        }
    }

    private var filaSocial: some View {
        HStack(spacing: 14) {
            botonIconoSocial(sistema: "apple.logo",
                             proveedor: "APPLE",
                             disponible: false,
                             color: Color(red: 0.10, green: 0.11, blue: 0.13))

            botonIconoSocial(sistema: "f.circle.fill",
                             proveedor: "FACEBOOK",
                             disponible: true,
                             color: Color(red: 0.10, green: 0.47, blue: 0.95))
        }
    }

    private func botonIconoSocial(sistema: String, proveedor: String,
                                  disponible: Bool, color: Color) -> some View {
        Button {
            guard disponible else {
                error = "El acceso con Apple estará disponible próximamente."
                return
            }
            avisoVinculacion = nil
            error = nil

            // Sin App ID real el SDK de Facebook aborta el proceso, así que se
            // avisa al usuario en lugar de abrir el flujo.
            if proveedor == "FACEBOOK" {
                guard SocialAuthManager.facebookConfigurado else {
                    error = "El acceso con Facebook aún no está configurado."
                    return
                }
                Task { await entrarFacebookReal() }
            } else {
                proveedorActivo = proveedor
                mostrandoSelector = true
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 76, height: 62)
                    .shadow(color: Color(red: 0.60, green: 0.70, blue: 0.86).opacity(0.30),
                            radius: 10, x: 0, y: 6)
                    .shadow(color: .white, radius: 4, x: -3, y: -3)

                if proveedorActivo == proveedor && sesion.cargando {
                    ProgressView().tint(color)
                } else {
                    Image(systemName: sistema)
                        .font(.system(size: 26))
                        .foregroundStyle(color)
                }
            }
            .opacity(disponible ? 1 : 0.45)
        }
        .disabled(sesion.cargando || bloqueado)
    }

    private var enlaces: some View {
        HStack {
            Button {
                mostrarRegistro = true
            } label: {
                Text("Crear cuenta")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Tema.tintaSuave)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("¿Olvidaste tu contraseña?")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Tema.azulSuave)
        }
    }

    private var pie: some View {
        VStack(spacing: 6) {
            Text("RECEPCIÓN · HOUSEKEEPING · ADMINISTRACIÓN")
                .font(.system(size: 8, weight: .medium))
                .tracking(1.1)
                .foregroundStyle(Tema.tintaSuave.opacity(0.7))
                .multilineTextAlignment(.center)

            Text("Hotel PMS · \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                .font(.system(size: 9))
                .foregroundStyle(Tema.tintaSuave.opacity(0.55))
        }
    }

    private var tituloBoton: String {
        if bloqueado { return "Bloqueado · \(formatear(segundosBloqueo))" }
        return sesion.cargando ? "Entrando..." : "Iniciar sesión"
    }

    // MARK: - Campos

    private var campoEmail: some View {
        VStack(alignment: .leading, spacing: 5) {
            campoRelieve {
                HStack(spacing: 12) {
                    Image(systemName: "person")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(Tema.tintaSuave)

                    TextField("Correo o usuario", text: $email)
                        .font(.system(size: 15))
                        .foregroundStyle(Tema.tinta)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($foco, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { foco = .password }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(errorEmail == nil
                            ? Color(red: 0.82, green: 0.88, blue: 0.96)
                            : Tema.peligro,
                            lineWidth: errorEmail == nil ? 1 : 1.5))
            .contentShape(Rectangle())
            .onTapGesture { foco = .email }

            if let errorEmail { textoError(errorEmail) }
        }
    }

    private var campoPassword: some View {
        VStack(alignment: .leading, spacing: 5) {
            campoRelieve {
                HStack(spacing: 12) {
                    Image(systemName: "lock")
                        .font(.system(size: 16))
                        .foregroundStyle(Tema.tintaSuave)

                    Group {
                        if mostrarPassword {
                            TextField("Contraseña", text: $password)
                                .textContentType(.password)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($foco, equals: .password)
                        } else {
                            SecureField("Contraseña", text: $password)
                                .textContentType(.password)
                                .focused($foco, equals: .password)
                        }
                    }
                    .font(.system(size: 15))
                    .foregroundStyle(Tema.tinta)

                    Button {
                        mostrarPassword.toggle()
                    } label: {
                        Image(systemName: mostrarPassword ? "eye" : "eye.slash")
                            .font(.system(size: 15))
                            .foregroundStyle(Tema.tintaSuave)
                    }
                    .buttonStyle(.plain)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(errorPassword == nil
                            ? Color(red: 0.82, green: 0.88, blue: 0.96)
                            : Tema.peligro,
                            lineWidth: errorPassword == nil ? 1 : 1.5))

            if let errorPassword { textoError(errorPassword) }
        }
    }

    private func textoError(_ mensaje: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 11))
                Text(mensaje)
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Tema.peligro)
            .frame(maxWidth: .infinity, alignment: .leading)

            if let intentosRestantes, intentosRestantes > 0 {
                Text("Te \(intentosRestantes == 1 ? "queda" : "quedan") \(intentosRestantes) intento\(intentosRestantes == 1 ? "" : "s") antes del bloqueo.")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Tema.peligro)
            }

            if bloqueado {
                Text("Podrás reintentar en \(formatear(segundosBloqueo)).")
                    .font(.system(size: 11))
                    .foregroundStyle(Tema.peligro)
            }
        }
        .padding(.horizontal, 2)
    }

    // MARK: - Acciones

    private func entrar() async {
        error = nil
        errorEmail = nil
        errorPassword = nil
        avisoVinculacion = nil
        intentosRestantes = nil

        let correo = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let resultado = await sesion.iniciarSesion(email: correo, password: password)

        switch resultado {
        case .exito:
            if recordarme {
                CredencialesRecordadas.guardar(email: correo.lowercased())
            } else {
                CredencialesRecordadas.olvidar()
            }
            email = ""
            password = ""

        case .fallo(let mensaje, let restantes, _):
            aplicarError(mensaje, restantes: restantes)

        case .bloqueado(let segundos, let mensaje):
            error = mensaje
            iniciarCountdown(segundos)
        }
    }

    private func entrarFacebookReal() async {
        error = nil
        avisoVinculacion = nil
        proveedorActivo = "FACEBOOK"

        let resultado = await sesion.iniciarSesionFacebookReal()

        switch resultado {
        case .exito:
            email = ""
            password = ""

        case .fallo(let mensaje, _, let motivo):
            if motivo == "ACCOUNT_LINK_REQUIRED" {
                avisoVinculacion = mensaje
            } else if motivo != "SOCIAL_CANCELADO" {
                error = mensaje
            }

        case .bloqueado(_, let mensaje):
            error = mensaje
        }

        proveedorActivo = nil
    }

    private func entrarSocial(_ cuenta: CuentaSocial) async {
        guard let proveedor = proveedorActivo else { return }

        error = nil
        avisoVinculacion = nil

        let resultado = await sesion.iniciarSesionSocial(proveedor: proveedor, cuenta: cuenta)

        switch resultado {
        case .exito:
            email = ""
            password = ""

        case .fallo(let mensaje, _, let motivo):
            if motivo == "ACCOUNT_LINK_REQUIRED" {
                avisoVinculacion = mensaje
                email = cuenta.email
                error = nil
            } else if motivo == "PROVEEDOR_ID_MISMATCH" {
                avisoVinculacion = mensaje
            } else {
                error = mensaje
            }

        case .bloqueado(_, let mensaje):
            error = mensaje
        }

        proveedorActivo = nil
    }

    private func aplicarError(_ mensaje: String, restantes: Int?) {
        let minuscula = mensaje.lowercased()

        if minuscula.contains("correo") || minuscula.contains("email") {
            errorEmail = mensaje
        } else if minuscula.contains("contrase") {
            errorPassword = mensaje
        } else {
            error = mensaje
        }

        intentosRestantes = restantes
    }

    private func iniciarCountdown(_ segundos: Int) {
        detenerTemporizador()
        let deadline = Date().addingTimeInterval(TimeInterval(segundos))
        segundosBloqueo = segundos

        temporizador = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            Task { @MainActor in
                let restante = Int(deadline.timeIntervalSinceNow)
                if restante > 0 {
                    segundosBloqueo = restante
                } else {
                    timer.invalidate()
                    segundosBloqueo = 0
                    error = "Ya puedes intentar iniciar sesión nuevamente."
                }
            }
        }
    }

    private func detenerTemporizador() {
        temporizador?.invalidate()
        temporizador = nil
    }

    private func formatear(_ segundos: Int) -> String {
        String(format: "%d:%02d", segundos / 60, segundos % 60)
    }

    private func entrarConBiometria() {
        Task {
            let ok = await sesion.verificarIdentidad(
                motivo: "Confirma tu identidad para entrar a Hotel PMS")
            if !ok {
                error = "No se pudo verificar tu identidad."
            }
        }
    }
}

// MARK: - Selector de cuenta (mock del SDK de OAuth)

/// Imita la hoja que muestra Facebook al autorizar.
struct SelectorCuentaSocial: View {

    let alElegir: (CuentaSocial) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    VStack(spacing: 6) {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.system(size: 36))
                            .foregroundStyle(Tema.azul)
                        Text("Elige una cuenta")
                            .font(.system(size: 17, weight: .semibold))
                        Text("Se compartirán tu nombre y correo con Hotel PMS.")
                            .font(.system(size: 12))
                            .foregroundStyle(Tema.textoSecundario)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 10)
                    .padding(.bottom, 8)

                    ForEach(CuentaSocial.demo) { cuenta in
                        Button {
                            alElegir(cuenta)
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle().fill(Color(red: cuenta.avatarColor.0,
                                                        green: cuenta.avatarColor.1,
                                                        blue: cuenta.avatarColor.2))
                                        .frame(width: 42, height: 42)
                                    Text(cuenta.iniciales)
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(.white)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(cuenta.nombre) \(cuenta.apellido)")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(Tema.texto)
                                    Text(cuenta.email)
                                        .font(.system(size: 12))
                                        .foregroundStyle(Tema.textoSecundario)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Tema.textoSecundario)
                            }
                            .padding(13)
                            .background(Color(red: 0.96, green: 0.97, blue: 0.98))
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    Text("Simulación del proveedor. En producción esta pantalla la muestra Meta.")
                        .font(.system(size: 10))
                        .foregroundStyle(Tema.textoSecundario)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                }
                .padding(18)
            }
            .background(Color(red: 0.96, green: 0.97, blue: 0.98).ignoresSafeArea())
            .navigationTitle("Acceso con Facebook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
    }
}
