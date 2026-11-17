import SwiftUI
import UIKit

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

                seccion("Datos de la cuenta") {
                    filasCuenta
                }

                seccion("Seguridad") {
                    seguridad
                }

                if sesion.esAdmin {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Administración")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Tema.textoSecundario)
                            .padding(.leading, 4)

                        NavigationLink {
                            UsuariosAdminView()
                        } label: {
                            filaAdministracion(icono: "person.2.fill",
                                               color: Tema.azul,
                                               titulo: "Usuarios y accesos",
                                               subtitulo: "Crea cuentas, resetea contraseñas y desbloquea")
                        }
                        .buttonStyle(EstiloPresionable())
                        .accessibilityLabel("Usuarios y accesos. Crea cuentas, resetea contraseñas y desbloquea")

                        NavigationLink {
                            SedesAdminView()
                        } label: {
                            filaAdministracion(icono: "building.2.fill",
                                               color: Tema.dorado,
                                               titulo: "Sedes y fotos",
                                               subtitulo: "Gestiona fotos y datos de cada sede")
                        }
                        .buttonStyle(EstiloPresionable())
                        .accessibilityLabel("Sedes y fotos. Gestiona fotos y datos de cada sede")
                    }
                }

                Text("Hotel PMS · v2.0 · Piura, Perú")
                    .font(.caption2)
                    .foregroundStyle(Tema.textoSecundario)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        // El botón queda fijo sobre la tab bar: nunca se pierde al hacer scroll.
        .safeAreaInset(edge: .bottom) {
            botonSalir
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 10)
                .background(.ultraThinMaterial)
                .overlay(alignment: .top) {
                    Divider().overlay(Tema.borde)
                }
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
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(colors: [Tema.azul, Tema.azulOscuro],
                                       startPoint: .topLeading,
                                       endPoint: .bottomTrailing))
                    .frame(width: 78, height: 78)
                    .shadow(color: Tema.azulOscuro.opacity(0.18),
                            radius: 10, x: 0, y: 5)

                Text(inicialesUsuario)
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 4) {
                Text(usuario.nombre)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Tema.texto)
                    .multilineTextAlignment(.center)

                Text(usuario.email)
                    .font(.subheadline)
                    .foregroundStyle(Tema.textoSecundario)
                    .multilineTextAlignment(.center)
            }

            EtiquetaEstado(texto: rolPrincipal,
                           color: Tema.azul,
                           icono: "person.badge.key.fill")
        }
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [Tema.azul.opacity(0.16),
                                    Tema.superficie],
                           startPoint: .top,
                           endPoint: .bottom))
        .clipShape(RoundedRectangle(cornerRadius: Tema.radio, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Tema.radio, style: .continuous)
                .stroke(Tema.borde, lineWidth: 1))
        .shadow(color: Tema.colorSombra, radius: 12, x: 0, y: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(usuario.nombre), \(usuario.email), rol \(rolPrincipal)")
    }

    /// Datos de la cuenta como filas con icono y separadores finos.
    private var filasCuenta: some View {
        VStack(spacing: 0) {
            ForEach(filas) { fila in
                if fila.id != filas.first?.id {
                    Divider().overlay(Tema.borde).padding(.leading, 34)
                }
                HStack(spacing: 12) {
                    Image(systemName: fila.icono)
                        .font(.subheadline)
                        .foregroundStyle(Tema.azul)
                        .frame(width: 22, alignment: .center)

                    Text(fila.etiqueta)
                        .font(.subheadline)
                        .foregroundStyle(Tema.textoSecundario)

                    Spacer(minLength: 12)

                    Text(fila.valor)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Tema.texto)
                        .multilineTextAlignment(.trailing)
                }
                .padding(.vertical, 10)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(fila.etiqueta): \(fila.valor)")
            }
        }
    }

    /// Fila de dato con su icono SF Symbol.
    private struct DatoCuenta: Identifiable {
        let etiqueta: String
        let valor: String
        let icono: String

        var id: String { etiqueta }
    }

    private var seguridad: some View {
        VStack(spacing: 0) {
            indicador(icono: "lock.shield.fill",
                      color: Tema.exito,
                      titulo: "Token en el Keychain",
                      detalle: "Almacenado de forma segura en iOS")

            Divider().overlay(Tema.borde).padding(.leading, 34)

            indicador(icono: "faceid",
                      color: biometriaDisponible ? Tema.azul : Tema.textoSecundario,
                      titulo: biometriaDisponible ? "Face ID disponible" : "Face ID no configurado",
                      detalle: biometriaDisponible
                        ? "Se pide antes de acciones sensibles"
                        : "Puedes activarlo en Ajustes")

            Button {
                Task { await abrirCambioPassword() }
            } label: {
                Label("Cambiar contraseña", systemImage: "key.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .background(Tema.azul.opacity(0.10))
                    .foregroundStyle(Tema.azul)
                    .clipShape(RoundedRectangle(cornerRadius: Tema.radioPequeno,
                                                style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
            .accessibilityLabel("Cambiar contraseña")
        }
    }

    /// Fila grande tipo tarjeta para cada destino de administración.
    private func filaAdministracion(icono: String, color: Color,
                                    titulo: String, subtitulo: String) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: Tema.radioPequeno, style: .continuous)
                .fill(color.opacity(0.15))
                .frame(width: 46, height: 46)
                .overlay(
                    Image(systemName: icono)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(color))

            VStack(alignment: .leading, spacing: 3) {
                Text(titulo)
                    .font(.headline)
                    .foregroundStyle(Tema.texto)

                Text(subtitulo)
                    .font(.caption)
                    .foregroundStyle(Tema.textoSecundario)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Tema.textoSecundario.opacity(0.6))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.superficie)
        .clipShape(RoundedRectangle(cornerRadius: Tema.radio, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Tema.radio, style: .continuous)
                .stroke(Tema.borde, lineWidth: 1))
        .shadow(color: Tema.colorSombra, radius: 12, x: 0, y: 4)
    }

    private var botonSalir: some View {
        Button(role: .destructive) {
            confirmarSalida = true
        } label: {
            Label("Cerrar sesión", systemImage: "rectangle.portrait.and.arrow.right")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
                .background(Tema.peligro.opacity(0.08))
                .foregroundStyle(Tema.peligro)
                .clipShape(RoundedRectangle(cornerRadius: Tema.radioPequeno,
                                            style: .continuous))
        }
        .buttonStyle(EstiloPresionable())
        .padding(.top, 4)
        .accessibilityLabel("Cerrar sesión")
    }

    private func seccion<Contenido: View>(
        _ titulo: String,
        @ViewBuilder contenido: () -> Contenido
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titulo)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Tema.textoSecundario)
                .padding(.leading, 4)

            Tarjeta {
                contenido()
            }
        }
    }

    private func indicador(icono: String, color: Color,
                           titulo: String, detalle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icono)
                .font(.subheadline)
                .foregroundStyle(color)
                .frame(width: 22, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(titulo)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Tema.texto)
                Text(detalle)
                    .font(.caption)
                    .foregroundStyle(Tema.textoSecundario)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(titulo). \(detalle)")
    }

    // MARK: - Datos derivados

    private var inicialesUsuario: String {
        let limpias = usuario.iniciales.trimmingCharacters(in: .whitespacesAndNewlines)
        if !limpias.isEmpty { return limpias }
        let primera = usuario.nombre
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(1)
        return String(primera).uppercased()
    }

    private var rolPrincipal: String {
        let rol = usuario.nombresRol.first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return rol.isEmpty ? "USUARIO" : rol
    }

    private var filas: [DatoCuenta] {
        var resultado: [DatoCuenta] = [
            DatoCuenta(etiqueta: "Nombre", valor: usuario.nombre, icono: "person.fill"),
            DatoCuenta(etiqueta: "Correo", valor: usuario.email, icono: "envelope.fill"),
        ]

        let roles = usuario.nombresRol.joined(separator: ", ")
        if !roles.isEmpty {
            resultado.append(DatoCuenta(etiqueta: "Roles", valor: roles,
                                        icono: "shield.lefthalf.filled"))
        }

        if let sede = usuario.sedePrincipal {
            resultado.append(DatoCuenta(etiqueta: "Sede", valor: sede.nombre,
                                        icono: "building.2.fill"))
        }

        if let telefono = usuario.telefono,
           !telefono.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            resultado.append(DatoCuenta(etiqueta: "Teléfono", valor: telefono,
                                        icono: "phone.fill"))
        }

        if let ultimo = usuario.ultimoLogin {
            resultado.append(DatoCuenta(
                etiqueta: "Último acceso",
                valor: FechaAPI.formatearConHora(FechaAPI.parsear(ultimo)),
                icono: "clock.fill"))
        }

        return resultado
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

    private var actualLimpia: String {
        actual.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var nuevaLimpia: String {
        nueva.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var confirmarLimpia: String {
        confirmar.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var valido: Bool {
        actualLimpia.count >= 8 && nuevaLimpia.count >= 8
            && nuevaLimpia == confirmarLimpia
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    campo("Contraseña actual", texto: $actual, tipo: .password)
                    campo("Nueva contraseña", texto: $nueva, tipo: .newPassword)
                    campo("Confirmar nueva contraseña", texto: $confirmar,
                          tipo: .newPassword)

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

    private func campo(_ etiqueta: String, texto: Binding<String>,
                       tipo: UITextContentType) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(etiqueta)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Tema.texto)
            SecureField("Mínimo 8 caracteres", text: texto)
                .textContentType(tipo)
                .font(.body)
                .padding(11)
                .background(Tema.fondo)
                .clipShape(RoundedRectangle(cornerRadius: Tema.radioPequeno,
                                            style: .continuous))
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