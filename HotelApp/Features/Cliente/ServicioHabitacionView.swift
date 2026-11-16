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
        VStack(alignment: .leading, spacing: 12) {
            Aviso(tipo: .info,
                  titulo: "Necesitas estar alojado",
                  mensaje: "El servicio a la habitación está disponible cuando has hecho el check-in y estás en tu habitación.")

            VStack(alignment: .leading, spacing: 8) {
                Label("¿Cómo funciona?", systemImage: "questionmark.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Tema.textoSecundario)

                Text("1. Reserva tu habitación en la pestaña «Reservar».")
                Text("2. En recepción te dan la llave y registran tu llegada (check-in).")
                Text("3. Desde ese momento puedes pedir aquí.")
            }
            .font(.system(size: 12))
            .foregroundStyle(Tema.textoSecundario)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tema.superficie)
            .clipShape(RoundedRectangle(cornerRadius: Tema.radioPequeno))

            NavigationLink {
                MisReservasView()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                    Text("Ver mis reservas")
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Tema.azul)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 11))
            }
            .buttonStyle(.plain)
        }
    }

    private func seccion(categoria: String, productos: [Producto]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tituloCategoria(categoria))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Tema.textoSecundario)

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
                .font(.system(size: 16))
                .foregroundStyle(Tema.azul)
                .frame(width: 34, height: 34)
                .background(Tema.azulClaro)
                .clipShape(RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 2) {
                Text(producto.nombre)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Tema.texto)
                Text(Tema.soles(producto.precio))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Tema.azul)
            }

            Spacer()

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
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Tema.azul)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 10) {
                botonCantidad("minus") {
                    if cantidad <= 1 { carrito.removeValue(forKey: producto.id) }
                    else { carrito[producto.id] = cantidad - 1 }
                }

                Text("\(cantidad)")
                    .font(.system(size: 14, weight: .bold))
                    .frame(minWidth: 20)

                botonCantidad("plus") {
                    carrito[producto.id] = cantidad + 1
                }
            }
        }
    }

    private func botonCantidad(_ icono: String, accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            Image(systemName: icono)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Tema.azul)
                .frame(width: 26, height: 26)
                .background(Tema.azulClaro)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var campoObservaciones: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Observaciones (opcional)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Tema.textoSecundario)

            TextField("Ej. sin hielo, dejar en la puerta", text: $observaciones, axis: .vertical)
                .font(.system(size: 13))
                .lineLimit(2...4)
                .padding(10)
                .background(Tema.superficie)
                .clipShape(RoundedRectangle(cornerRadius: Tema.radioPequeno))
        }
    }

    private var barraEnviar: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(totalUnidades) \(totalUnidades == 1 ? "producto" : "productos")")
                        .font(.system(size: 11))
                        .foregroundStyle(Tema.textoSecundario)
                    Text(Tema.soles(total))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Tema.azul)
                }

                Spacer()

                Button {
                    Task { await enviar() }
                } label: {
                    HStack(spacing: 6) {
                        if servicio.procesando {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                        Text(servicio.procesando ? "Enviando..." : "Pedir")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(Tema.azul)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
                .disabled(servicio.procesando)
            }
        }
        .padding(14)
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
