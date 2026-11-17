import SwiftUI

/// Servicio a la habitación — vista del cliente.
///
/// El cliente pide; no paga aquí. Recepción valida y el importe se carga
/// al folio, que se liquida en el check-out.
struct ServicioHabitacionView: View {

    @Environment(ServicioStore.self) private var servicio
    @Environment(\.dismiss) private var dismiss

    @State private var carrito: [Int: Int] = [:]
    @State private var observaciones = ""
    @State private var enviada: SolicitudConsumo?
    @State private var mostrandoConfirmacion = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if servicio.sinEstadiaActiva {
                    avisoSinEstadia
                } else if let error = servicio.error {
                    Aviso(tipo: .peligro, titulo: "No se pudo enviar", mensaje: error)
                }

                if !servicio.sinEstadiaActiva {
                    avisoRecepcion
                }

                if servicio.cargandoCatalogo {
                    ProgressView("Cargando catálogo...")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if servicio.productos.isEmpty {
                    EstadoVacio(icono: "shippingbox",
                                titulo: "Sin productos",
                                mensaje: "Recepción aún no ha publicado el catálogo de servicio a la habitación.")
                } else {
                    ForEach(servicio.catalogoPorCategoria) { grupo in
                        seccion(categoria: grupo.categoria, productos: grupo.productos)
                    }

                    campoObservaciones
                }
            }
            .padding(16)
            .padding(.bottom, carrito.isEmpty ? 0 : 90)
        }
        .background(Tema.fondo.ignoresSafeArea())
        .navigationTitle("Servicio a la habitación")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if !carrito.isEmpty && !servicio.sinEstadiaActiva { barraEnviar }
        }
        .task {
            await servicio.cargarCatalogo()
            servicio.limpiarError()
        }
        .alert("Solicitud enviada", isPresented: $mostrandoConfirmacion) {
            Button("Entendido") {
                carrito = [:]
                observaciones = ""
                dismiss()
            }
        } message: {
            if let enviada {
                Text("Código \(enviada.codigo) por \(Tema.soles(enviada.total)).\n\nRecepción lo revisará y lo cargará a tu cuenta.")
            }
        }
    }

    // MARK: - Subvistas

    private var avisoRecepcion: some View {
        Aviso(tipo: .info,
              titulo: "Lo atiende recepción",
              mensaje: "No se cobra ahora. El importe se suma a tu cuenta y se paga al hacer el check-out.")
    }

    /// El servicio a la habitación exige estar alojado. Sin check-in no aplica.
    private var avisoSinEstadia: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Tema.azul.opacity(0.10))
                        .frame(width: 64, height: 64)
                    Image(systemName: "door.left.hand.open")
                        .font(.title2)
                        .foregroundStyle(Tema.azul)
                }

                Text("Necesitas estar alojado")
                    .font(.headline)
                    .foregroundStyle(Tema.texto)

                Text("El servicio a la habitación está disponible cuando has hecho "
                     + "el check-in y estás en tu habitación.")
                    .font(.subheadline)
                    .foregroundStyle(Tema.textoSecundario)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)

            Tarjeta {
                VStack(alignment: .leading, spacing: 12) {
                    Label("¿Cómo funciona?", systemImage: "questionmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Tema.azul)

                    paso(1, "Reserva tu habitación en la pestaña «Reservar».")
                    paso(2, "En recepción te dan la llave y registran tu llegada.")
                    paso(3, "Desde ese momento puedes pedir aquí.")
                }
            }

            NavigationLink {
                MisReservasView()
            } label: {
                Label("Ver mis reservas", systemImage: "calendar")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
                    .background(Tema.azul)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: Tema.radioPequeno,
                                                style: .continuous))
            }
            .buttonStyle(EstiloPresionable())
        }
    }

    private func paso(_ numero: Int, _ texto: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(numero)")
                .font(.caption.weight(.bold))
                .foregroundStyle(Tema.azul)
                .frame(width: 22, height: 22)
                .background(Tema.azul.opacity(0.12))
                .clipShape(Circle())

            Text(texto)
                .font(.subheadline)
                .foregroundStyle(Tema.textoSecundario)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func seccion(categoria: String, productos: [Producto]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tituloCategoria(categoria))
                .font(.headline)
                .foregroundStyle(Tema.texto)

            Tarjeta(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(productos.enumerated()), id: \.element.id) { indice, producto in
                        filaProducto(producto)

                        if indice < productos.count - 1 {
                            Divider().padding(.leading, 58)
                        }
                    }
                }
            }
        }
    }

    private func filaProducto(_ producto: Producto) -> some View {
        HStack(spacing: 12) {
            Image(systemName: producto.icono)
                .font(.subheadline)
                .foregroundStyle(Tema.azul)
                .frame(width: 38, height: 38)
                .background(Tema.azul.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(producto.nombre)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Tema.texto)
                Text(Tema.soles(producto.precio))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Tema.azul)
            }

            Spacer(minLength: 8)

            selectorCantidad(producto)
        }
        .padding(12)
    }

    @ViewBuilder
    private func selectorCantidad(_ producto: Producto) -> some View {
        let cantidad = carrito[producto.id] ?? 0

        if cantidad == 0 {
            Button {
                carrito[producto.id] = 1
            } label: {
                Image(systemName: "plus")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Tema.azul)
                    .clipShape(Circle())
            }
            .buttonStyle(EstiloPresionable())
            .accessibilityLabel("Añadir \(producto.nombre)")
        } else {
            HStack(spacing: 10) {
                botonCantidad("minus", etiqueta: "Quitar uno de \(producto.nombre)") {
                    if cantidad <= 1 { carrito.removeValue(forKey: producto.id) }
                    else { carrito[producto.id] = cantidad - 1 }
                }

                Text("\(cantidad)")
                    .font(.subheadline.weight(.bold))
                    .frame(minWidth: 20)
                    .contentTransition(.numericText())

                botonCantidad("plus", etiqueta: "Añadir uno de \(producto.nombre)") {
                    carrito[producto.id] = cantidad + 1
                }
            }
        }
    }

    private func botonCantidad(_ icono: String, etiqueta: String,
                              accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            Image(systemName: icono)
                .font(.caption.weight(.bold))
                .foregroundStyle(Tema.azul)
                .frame(width: 30, height: 30)
                .background(Tema.azul.opacity(0.10))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(etiqueta)
    }

    private var campoObservaciones: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Observaciones (opcional)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Tema.textoSecundario)

            TextField("Ej. sin hielo, dejar en la puerta", text: $observaciones, axis: .vertical)
                .font(.body)
                .lineLimit(2...4)
                .padding(11)
                .background(Tema.superficie)
                .clipShape(RoundedRectangle(cornerRadius: Tema.radioPequeno,
                                            style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Tema.radioPequeno,
                                     style: .continuous)
                        .stroke(Tema.borde, lineWidth: 1))
        }
    }

    private var barraEnviar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(totalUnidades) \(totalUnidades == 1 ? "producto" : "productos")")
                    .font(.caption)
                    .foregroundStyle(Tema.textoSecundario)
                Text(Tema.soles(total))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Tema.azul)
                    .contentTransition(.numericText())
            }

            Spacer(minLength: 0)

            Button {
                Task { await enviar() }
            } label: {
                HStack(spacing: 7) {
                    if servicio.procesando {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                    Text(servicio.procesando ? "Enviando..." : "Pedir")
                        .font(.headline)
                }
                .padding(.horizontal, 24)
                .frame(minHeight: 46)
                .background(servicio.procesando ? Tema.azul.opacity(0.6) : Tema.azul)
                .foregroundStyle(.white)
                .clipShape(Capsule())
            }
            .buttonStyle(EstiloPresionable())
            .disabled(servicio.procesando)
            .accessibilityLabel("Enviar pedido por \(Tema.soles(total))")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    // MARK: - Lógica

    private var total: Decimal {
        carrito.reduce(Decimal.zero) { acumulado, entrada in
            guard let producto = servicio.productos.first(where: { $0.id == entrada.key })
            else { return acumulado }
            return acumulado + producto.precio * Decimal(entrada.value)
        }
    }

    private var totalUnidades: Int {
        carrito.values.reduce(0, +)
    }

    private func enviar() async {
        let items = carrito.map { ItemSolicitudRequest(productoId: $0.key, cantidad: $0.value) }
        let texto = observaciones.trimmingCharacters(in: .whitespacesAndNewlines)

        if let creada = await servicio.crearSolicitud(
            items: items,
            observaciones: texto.isEmpty ? nil : texto) {
            enviada = creada
            mostrandoConfirmacion = true
        }
    }

    private func tituloCategoria(_ categoria: String) -> String {
        switch categoria {
        case "BEBIDA": return "Bebidas"
        case "COMIDA": return "Comidas"
        case "SNACK": return "Snacks"
        case "HIGIENE": return "Higiene personal"
        default: return "Otros"
        }
    }
}
