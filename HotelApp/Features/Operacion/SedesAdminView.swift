import SwiftUI

/// Gestión de sedes y sus fotos (solo ADMIN).
///
/// Las fotos se guardan como ruta relativa (`/img/sedes/piura.jpg`) y las sirve
/// el frontend web; `AppConfig.imagenURL` las resuelve.
struct SedesAdminView: View {

    @State private var sedes: [Sede] = []
    @State private var cargando = true
    @State private var error: String?
    @State private var seleccionada: Sede?

    private let api = HotelAPI.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let error {
                    Aviso(tipo: .peligro, titulo: "Error", mensaje: error)
                }

                if cargando && sedes.isEmpty {
                    ProgressView().padding(.top, 40)
                } else if sedes.isEmpty {
                    EstadoVacio(icono: "building.2",
                                titulo: "Sin sedes",
                                mensaje: "No se encontraron sedes activas.")
                } else {
                    ForEach(sedes) { sede in
                        Button {
                            seleccionada = sede
                        } label: {
                            tarjeta(sede)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
        }
        .background(Tema.fondo.ignoresSafeArea())
        .navigationTitle("Sedes")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await cargar() }
        .task { await cargar() }
        .sheet(item: $seleccionada) { sede in
            EditarSedeSheet(sede: sede) { await cargar() }
        }
    }

    private func tarjeta(_ sede: Sede) -> some View {
        Tarjeta(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                ImagenRemota(ruta: sede.imagenUrl, iconoRespaldo: "building.2", alto: 130)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(sede.nombre)
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                        EtiquetaEstado(texto: sede.codigo, color: Tema.azul)
                    }

                    if let direccion = sede.direccion {
                        Label("\(direccion)\(sede.ciudad.map { ", \($0)" } ?? "")",
                              systemImage: "mappin.and.ellipse")
                            .font(.system(size: 11))
                            .foregroundStyle(Tema.textoSecundario)
                    }

                    Text("Check-in \(sede.checkInCorto) · Check-out \(sede.checkOutCorto)")
                        .font(.system(size: 10))
                        .foregroundStyle(Tema.textoSecundario)

                    HStack {
                        if let telefono = sede.telefono {
                            Label(telefono, systemImage: "phone")
                                .font(.system(size: 10))
                                .foregroundStyle(Tema.textoSecundario)
                        }
                        Spacer()
                        Text("Editar foto →")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Tema.azul)
                    }
                }
                .padding(14)
            }
        }
    }

    private func cargar() async {
        cargando = true
        error = nil

        do {
            sedes = try await api.sedesAdmin()
        } catch let apiError as APIError {
            error = apiError.mensajeUsuario
        } catch {
            self.error = "No se pudieron cargar las sedes."
        }

        cargando = false
    }
}

/// Edición de datos y foto de una sede.
struct EditarSedeSheet: View {

    let sede: Sede
    let alGuardar: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var nombre: String
    @State private var direccion: String
    @State private var ciudad: String
    @State private var telefono: String
    @State private var imagenUrl: String

    @State private var guardando = false
    @State private var error: String?
    @State private var mensaje: String?

    private let api = HotelAPI.shared

    /// Fotos incluidas en el proyecto web.
    private let fotosSugeridas = [
        ("Piura", "/img/sedes/piura.jpg"),
        ("Trujillo", "/img/sedes/trujillo.jpg"),
        ("Lima", "/img/sedes/lima.jpg"),
    ]

    init(sede: Sede, alGuardar: @escaping () async -> Void) {
        self.sede = sede
        self.alGuardar = alGuardar

        _nombre = State(initialValue: sede.nombre)
        _direccion = State(initialValue: sede.direccion ?? "")
        _ciudad = State(initialValue: sede.ciudad ?? "")
        _telefono = State(initialValue: sede.telefono ?? "")
        _imagenUrl = State(initialValue: sede.imagenUrl ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Tarjeta(padding: 0) {
                        ImagenRemota(ruta: imagenUrl.isEmpty ? nil : imagenUrl,
                                     iconoRespaldo: "building.2",
                                     alto: 170)
                    }

                    Tarjeta {
                        VStack(spacing: 12) {
                            campo("Nombre", $nombre)
                            campo("Dirección", $direccion)
                            campo("Ciudad", $ciudad)
                            campo("Teléfono", $telefono, teclado: .phonePad)

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Foto de la sede")
                                    .font(.system(size: 12, weight: .semibold))

                                // Subida directa desde la galería del iPhone.
                                SelectorFoto(urlActual: imagenUrl.isEmpty ? nil : imagenUrl) { nueva in
                                    imagenUrl = nueva
                                }

                                Text("O usa una de las fotos del catálogo:")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Tema.textoSecundario)

                                HStack(spacing: 6) {
                                    ForEach(fotosSugeridas, id: \.0) { foto in
                                        Button(foto.0) {
                                            imagenUrl = foto.1
                                        }
                                        .font(.system(size: 10, weight: .semibold))
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 5)
                                        .background(Tema.azulClaro)
                                        .foregroundStyle(Tema.azul)
                                        .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                    }

                    if let error {
                        Aviso(tipo: .peligro, titulo: "No se pudo guardar", mensaje: error)
                    }
                    if let mensaje {
                        Aviso(tipo: .exito, titulo: "Listo", mensaje: mensaje)
                    }

                    BotonPrincipal(titulo: "Guardar cambios", icono: "checkmark",
                                   cargando: guardando,
                                   deshabilitado: nombre.trimmingCharacters(in: .whitespaces).isEmpty) {
                        Task { await guardar() }
                    }
                }
                .padding(16)
            }
            .background(Tema.fondo.ignoresSafeArea())
            .navigationTitle("Editar sede")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
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
                .padding(10)
                .background(Tema.fondo)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func guardar() async {
        guard !guardando else { return }
        guardando = true
        error = nil
        mensaje = nil

        do {
            _ = try await api.actualizarSede(id: sede.id, request: CrearSedeRequest(
                nombre: nombre.trimmingCharacters(in: .whitespaces),
                codigo: sede.codigo,
                direccion: direccion.isEmpty ? nil : direccion,
                ciudad: ciudad.isEmpty ? nil : ciudad,
                telefono: telefono.isEmpty ? nil : telefono,
                email: sede.email,
                horaCheckIn: sede.horaCheckIn,
                horaCheckOut: sede.horaCheckOut,
                imagenUrl: imagenUrl.isEmpty ? nil : imagenUrl))

            mensaje = "Sede actualizada."
            await alGuardar()
        } catch let apiError as APIError {
            error = apiError.mensajeUsuario
        } catch {
            self.error = "No se pudo guardar la sede."
        }

        guardando = false
    }
}
