import SwiftUI
import Combine
import FirebaseCore

/// Punto de entrada de la app del hotel.
@main
struct HotelAppMain: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var sesion = SesionStore()
    @State private var catalogo = CatalogoStore()
    @State private var reservas = ReservaStore()
    @State private var operacion = OperacionStore()
    @State private var servicio = ServicioStore()
    @State private var sedeActiva = SedeActivaStore()

    init() {
        // Firebase se inicializa una sola vez por proceso.
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        Task { await NotificacionService.solicitarPermiso() }
    }

    var body: some Scene {
        WindowGroup {
            RaizView()
                .environment(sesion)
                .environment(catalogo)
                .environment(reservas)
                .environment(operacion)
                .environment(servicio)
                .environment(sedeActiva)
                .task { await sesion.restaurarSesion() }
                // Los stores son propiedad de la App: aquí se limpian al
                // pasar a "sin sesión" (logout manual o token revocado).
                .onChange(of: sesion.estado) { _, nuevo in
                    guard nuevo == .sinSesion else { return }
                    limpiarStores()
                }
                .tint(Tema.azul)
        }
    }

    /// Vacía los stores en memoria al cerrar sesión.
    ///
    /// Sin esto, las reservas/pedidos de una cuenta seguían visibles para la
    /// siguiente persona que usara el dispositivo. La purga de Core Data la
    /// hace `SesionStore.cerrarSesionLocal()`.
    private func limpiarStores() {
        reservas.limpiar()
        operacion.limpiar()
        servicio.limpiar()
        catalogo.limpiar()
        sedeActiva.limpiar()
    }
}

/// Necesario para el flujo de Facebook (abrir el retorno por URL scheme)
/// y para que Crashlytics capture los crashes nativos.
final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions:
                     [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        true
    }

    func application(_ app: UIApplication, open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        SocialAuthManager.manejarURL(url)
    }
}

struct RaizView: View {

    @Environment(SesionStore.self) private var sesion

    var body: some View {
        Group {
            switch sesion.estado {
            case .desconocido:
                SplashView()

            case .sinSesion:
                // El login es neumórfico (blancos y sombras claras): se queda
                // en claro aunque el resto de la app siga el modo del sistema.
                LoginView()
                    .preferredColorScheme(.light)

            case .autenticado(let usuario):
                if usuario.puedeOperar || usuario.esHousekeeping {
                    TabViewOperacion(usuario: usuario)
                } else {
                    TabViewCliente(usuario: usuario)
                }
            }
        }
        // APIClient es un actor y no puede tocar @MainActor: publica el 401
        // global por NotificationCenter y aquí se cierra la sesión local.
        .onReceive(NotificationCenter.default
            .publisher(for: SesionEventos.sesionExpirada)) { _ in
                Task { await sesion.cerrarSesionLocal() }
            }
    }
}

struct SplashView: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Tema.azulOscuro, Tema.azul],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "building.2.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.white)

                Text("Hotel PMS")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                ProgressView().tint(.white).padding(.top, 8)
            }
        }
    }
}

/// Navegación del cliente.
///
/// «Servicio» y «Mis pedidos» solo existen con una estancia en curso: antes
/// ocupaban dos de las cinco pestañas aunque el cliente no estuviera alojado
/// y no pudiera pedir nada.
struct TabViewCliente: View {

    let usuario: Usuario

    @Environment(ServicioStore.self) private var servicio
    @Environment(\.scenePhase) private var escena

    var body: some View {
        TabView {
            NavigationStack { BuscarView() }
                .tabItem { Label("Reservar", systemImage: "magnifyingglass") }

            NavigationStack { MisReservasView() }
                .tabItem { Label("Mis reservas", systemImage: "calendar") }

            if servicio.puedePedir {
                NavigationStack { ServicioHabitacionView() }
                    .tabItem { Label("Servicio", systemImage: "bell.badge.fill") }

                NavigationStack { MisSolicitudesView() }
                    .tabItem { Label("Mis pedidos", systemImage: "list.bullet.rectangle") }
            }

            NavigationStack { PerfilView(usuario: usuario) }
                .tabItem { Label("Perfil", systemImage: "person.crop.circle") }
        }
        .task { await servicio.cargarEstadiaActiva() }
        // Recepción hace el check-in mientras el cliente espera: al volver a
        // la app se refresca para que aparezcan «Servicio» y «Mis pedidos».
        .onChange(of: escena) { _, nueva in
            guard nueva == .active else { return }
            Task { await servicio.cargarEstadiaActiva() }
        }
    }
}

/// Navegación de recepción / admin / housekeeping.
///
/// Cuatro pestañas, no cinco: "Servicio a habitación", "Verificar pagos" y los
/// reportes ya están en los accesos rápidos del home. Con cinco pestañas las
/// etiquetas se truncaban en pantallas de iPhone de 6.1".
struct TabViewOperacion: View {

    let usuario: Usuario

    var body: some View {
        TabView {
            NavigationStack { OperacionHomeView(usuario: usuario) }
                .tabItem { Label("Panel", systemImage: "square.grid.2x2.fill") }

            NavigationStack { HabitacionesView() }
                .tabItem { Label("Habitaciones", systemImage: "bed.double.fill") }

            NavigationStack { TareasView() }
                .tabItem { Label("Tareas", systemImage: "sparkles") }

            NavigationStack { PerfilView(usuario: usuario) }
                .tabItem { Label("Perfil", systemImage: "person.crop.circle.fill") }
        }
    }
}
