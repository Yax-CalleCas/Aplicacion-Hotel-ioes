import SwiftUI

/// Registro walk-in: huésped que llega sin reserva.
///
/// Diseñado para uso rápido en mostrador: pocos campos, textos grandes,
/// y el resultado muestra las credenciales para entregar en papel.
struct WalkInView: View {

    @Environment(CatalogoStore.self) private var catalogo
    @Environment(\.dismiss) private var dismiss

    let sedeId: Int

    // Datos del huésped
    @State private var tipoDocumento = "DNI"
    @State private var numeroDocumento = ""
    @State private var nombres = ""
    @State private var apellidos = ""
    @State private var email = ""
    @State private var telefono = ""

    // Estadía
    @State private var categoriaId: Int?
    @State private var habitacionId: Int?
    @State private var habitacionesLibres: [Habitacion] = []
    @State private var noches = 1
    @State private var adultos = 1
    @State private var ninos = 0
    @State private var observaciones = ""

    // Estado
    @State private var buscando = false
    @State private var enviando = false
    @State private var error: String?
    @State private var resultado: WalkInResponse?
    @State private var huespedExistente: Huesped?

    private let api = HotelAPI.shared

    private var checkIn: String { FechaAPI.soloFecha(Date()) }
    private var checkOut: String {
        FechaAPI.soloFecha(Calendar.current.date(byAdding: .day, value: noches, to: Date()) ?? Date())
    }

    private var formularioValido: Bool {
        !numeroDocumento.trimmingCharacters(in: .whitespaces).isEmpty
        && !nombres.trimmingCharacters(in: .whitespaces).isEmpty
        && !apellidos.trimmingCharacters(in: .whitespaces).isEmpty
        && categoriaId != nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if let resultado {
                    PantallaCredenciales(resultado: resultado) {
                        dismiss()
                    }
                } else {
                    formulario
                }
            }
            .background(Tema.fondo.ignoresSafeArea())
            .navigationTitle(resultado == nil ? "Nuevo huésped" : "Listo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if resultado == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancelar") { dismiss() }
                    }
                }
            }
        }
        .task {
            if catalogo.categorias.isEmpty { await catalogo.cargarCategorias(sedeId: sedeId) }
            if categoriaId == nil { categoriaId = catalogo.categorias.first?.id }
            await cargarHabitacionesLibres()
        }
    }

    // MARK: - Carga

    /// Habitaciones libres de la categoría elegida, para asignar una concreta.
    private func cargarHabitacionesLibres() async {
        guard let categoriaId else {
            habitacionesLibres = []
            return
        }

        do {
            let lista = try await api.habitaciones(sedeId: sedeId, estado: "DISPONIBLE")
            habitacionesLibres = lista.habitaciones.filter { $0.categoriaId == categoriaId }
        } catch {
            habitacionesLibres = []
        }
    }

    // MARK: - Formulario

    private var formulario: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let error {
                    Aviso(tipo: .peligro, titulo: "No se pudo registrar", mensaje: error)
                }

                aviso

                seccionDatos
                seccionHabitacion
                seccionResumen

                BotonPrincipal(titulo: "Registrar y dar habitación",
                               icono: "key.fill",
                               cargando: enviando,
                               deshabilitado: !formularioValido) {
                    Task { await registrar() }
                }

                Text("El huésped queda registrado con su cuenta y podrá usar la app. Si no tiene celular, no pasa nada: recepción gestiona todo.")
                    .font(.system(size: 11))
                    .foregroundStyle(Tema.textoSecundario)
                    .multilineTextAlignment(.center)
            }
            .padding(16)
        }
    }

    private var aviso: some View {
        Aviso(tipo: .info,
              titulo: "Sin reserva previa",
              mensaje: "Se crea la reserva y, si es nuevo, su cuenta. Al final verás la contraseña temporal para entregársela.")
    }

    private var seccionDatos: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Datos del huésped")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Tema.textoSecundario)

            Tarjeta {
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Picker("", selection: $tipoDocumento) {
                            Text("DNI").tag("DNI")
                            Text("CE").tag("CE")
                            Text("Pasaporte").tag("PASAPORTE")
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 110)

                        campo("N° documento", texto: $numeroDocumento, teclado: .default)
                    }

                    campo("Nombres", texto: $nombres)
                    campo("Apellidos", texto: $apellidos)
                    campo("Teléfono", texto: $telefono, teclado: .phonePad)
                    campo("Email (opcional)", texto: $email, teclado: .emailAddress)
                }
            }

            if let huespedExistente {
                Aviso(tipo: .exito,
                      titulo: "Huésped ya registrado",
                      mensaje: "\(huespedExistente.nombreCompleto) ya tiene ficha. Se reutilizará su cuenta.")
            }
        }
    }

    private var seccionHabitacion: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Habitación")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Tema.textoSecundario)

            Tarjeta {
                VStack(spacing: 12) {
                    if catalogo.categorias.isEmpty {
                        Text("Sin categorías disponibles")
                            .font(.system(size: 12))
                            .foregroundStyle(Tema.textoSecundario)
                    } else {
                        HStack {
                            Text("Tipo")
                                .font(.system(size: 13))
                                .foregroundStyle(Tema.textoSecundario)
                            Spacer()
                            Picker("", selection: Binding(
                                get: { categoriaId },
                                set: { nueva in
                                    categoriaId = nueva
                                    habitacionId = nil
                                    Task { await cargarHabitacionesLibres() }
                                }
                            )) {
                                ForEach(catalogo.categorias) { categoria in
                                    Text("\(categoria.nombre) · \(Tema.soles(categoria.precioBase ?? 0))")
                                        .tag(Optional(categoria.id))
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }

                        if !habitacionesLibres.isEmpty {
                            Divider()
                            HStack {
                                Text("Habitación")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Tema.textoSecundario)
                                Spacer()
                                Picker("", selection: $habitacionId) {
                                    Text("Cualquiera libre").tag(Optional<Int>.none)
                                    ForEach(habitacionesLibres) { habitacion in
                                        Text(habitacion.numero).tag(Optional(habitacion.id))
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                            }
                        }

                        Divider()
                    }

                    contador("Noches", valor: $noches, minimo: 1, maximo: 30)
                    Divider()
                    contador("Adultos", valor: $adultos, minimo: 1, maximo: 6)
                    Divider()
                    contador("Niños", valor: $ninos, minimo: 0, maximo: 6)
                }
            }
        }
    }

    private var seccionResumen: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Estadía")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Tema.textoSecundario)

            Tarjeta {
                VStack(spacing: 8) {
                    fila("Entrada", FechaAPI.formatear(FechaAPI.parsear(checkIn)))
                    fila("Salida", FechaAPI.formatear(FechaAPI.parsear(checkOut)))
                    fila("Noches", "\(noches)")
                    if let categoria = categoriaSeleccionada {
                        Divider()
                        HStack {
                            Text("Total estimado")
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Text(Tema.soles((categoria.precioBase ?? 0) * Decimal(noches)))
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Tema.azul)
                        }
                    }
                }
            }
        }
    }

    private var categoriaSeleccionada: CategoriaHabitacion? {
        guard let categoriaId else { return nil }
        return catalogo.categorias.first { $0.id == categoriaId }
    }

    // MARK: - Componentes

    private func campo(_ etiqueta: String, texto: Binding<String>,
                       teclado: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(etiqueta)
                .font(.system(size: 11))
                .foregroundStyle(Tema.textoSecundario)
            TextField(etiqueta, text: texto)
                .font(.system(size: 15))
                .keyboardType(teclado)
                .textInputAutocapitalization(teclado == .emailAddress ? .never : .words)
                .autocorrectionDisabled(teclado == .emailAddress)
                .padding(10)
                .background(Tema.fondo)
                .clipShape(RoundedRectangle(cornerRadius: 9))
        }
    }

    private func contador(_ etiqueta: String, valor: Binding<Int>,
                          minimo: Int, maximo: Int) -> some View {
        HStack {
            Text(etiqueta)
                .font(.system(size: 13))
                .foregroundStyle(Tema.textoSecundario)

            Spacer()

            HStack(spacing: 14) {
                botonContador("minus") {
                    if valor.wrappedValue > minimo { valor.wrappedValue -= 1 }
                }
                .disabled(valor.wrappedValue <= minimo)

                Text("\(valor.wrappedValue)")
                    .font(.system(size: 16, weight: .bold))
                    .frame(minWidth: 24)

                botonContador("plus") {
                    if valor.wrappedValue < maximo { valor.wrappedValue += 1 }
                }
                .disabled(valor.wrappedValue >= maximo)
            }
        }
    }

    private func botonContador(_ icono: String, accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            Image(systemName: icono)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Tema.azul)
                .frame(width: 30, height: 30)
                .background(Tema.azulClaro)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func fila(_ etiqueta: String, _ valor: String) -> some View {
        HStack {
            Text(etiqueta)
                .font(.system(size: 12))
                .foregroundStyle(Tema.textoSecundario)
            Spacer()
            Text(valor)
                .font(.system(size: 13, weight: .medium))
        }
    }

    // MARK: - Lógica

    private func registrar() async {
        guard let categoriaId else { return }

        enviando = true
        error = nil
        defer { enviando = false }

        let textoEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let textoTelefono = telefono.trimmingCharacters(in: .whitespacesAndNewlines)
        let textoObservaciones = observaciones.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            resultado = try await api.walkIn(WalkInRequest(
                tipoDocumento: tipoDocumento,
                numeroDocumento: numeroDocumento.trimmingCharacters(in: .whitespaces),
                nombres: nombres.trimmingCharacters(in: .whitespaces),
                apellidos: apellidos.trimmingCharacters(in: .whitespaces),
                email: textoEmail.isEmpty ? nil : textoEmail,
                telefono: textoTelefono.isEmpty ? nil : textoTelefono,
                sedeId: sedeId,
                categoriaId: categoriaId,
                habitacionId: habitacionId,
                checkIn: checkIn,
                checkOut: checkOut,
                adultos: adultos,
                ninos: ninos,
                observaciones: textoObservaciones.isEmpty ? nil : textoObservaciones))
        } catch let apiError as APIError {
            self.error = apiError.mensajeUsuario
        } catch {
            self.error = "No se pudo registrar al huésped."
        }
    }
}

// MARK: - Pantalla de resultado

/// Muestra las credenciales para entregar al huésped.
struct PantallaCredenciales: View {

    let resultado: WalkInResponse
    let alCerrar: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 46))
                    .foregroundStyle(Tema.exito)

                VStack(spacing: 4) {
                    Text("Huésped registrado")
                        .font(.system(size: 19, weight: .bold))
                    Text(resultado.reservaCodigo)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Tema.textoSecundario)
                }

                Tarjeta {
                    VStack(spacing: 9) {
                        fila("Huésped", resultado.huespedNombre)
                        fila("Habitación", resultado.habitacionNumero ?? "Por asignar")
                        fila("Tipo", resultado.categoriaNombre ?? "—")
                        fila("Entrada", FechaAPI.formatear(FechaAPI.parsear(resultado.checkIn)))
                        fila("Salida", FechaAPI.formatear(FechaAPI.parsear(resultado.checkOut)))
                        fila("Noches", "\(resultado.noches)")

                        Divider()

                        HStack {
                            Text("Total").font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Text(Tema.soles(resultado.montoTotal))
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(Tema.azul)
                        }
                        HStack {
                            Text("Depósito").font(.system(size: 12))
                                .foregroundStyle(Tema.textoSecundario)
                            Spacer()
                            Text(Tema.soles(resultado.depositoRequerido))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Tema.alerta)
                        }
                    }
                }

                if resultado.cuentaCreada, let password = resultado.passwordTemporal {
                    Tarjeta {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Credenciales de la app", systemImage: "person.badge.key")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Tema.azul)

                            VStack(alignment: .leading, spacing: 5) {
                                Text("Usuario")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Tema.textoSecundario)
                                Text(resultado.email ?? "—")
                                    .font(.system(size: 14, design: .monospaced))
                                    .textSelection(.enabled)

                                Text("Contraseña temporal")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Tema.textoSecundario)
                                    .padding(.top, 4)
                                Text(password)
                                    .font(.system(size: 19, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Tema.azul)
                                    .textSelection(.enabled)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Tema.azulClaro)
                            .clipShape(RoundedRectangle(cornerRadius: 9))

                            Text("Anótala o entrega esta pantalla. No se vuelve a mostrar.")
                                .font(.system(size: 10))
                                .foregroundStyle(Tema.peligro)
                        }
                    }
                } else {
                    Aviso(tipo: .info,
                          titulo: "Cliente ya registrado",
                          mensaje: "Usa su cuenta de siempre. No se generó contraseña nueva.")
                }

                BotonPrincipal(titulo: "Hecho", icono: "checkmark", accion: alCerrar)
            }
            .padding(16)
        }
    }

    private func fila(_ etiqueta: String, _ valor: String) -> some View {
        HStack {
            Text(etiqueta)
                .font(.system(size: 12))
                .foregroundStyle(Tema.textoSecundario)
            Spacer()
            Text(valor)
                .font(.system(size: 13, weight: .medium))
        }
    }
}
