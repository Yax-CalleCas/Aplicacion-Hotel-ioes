import SwiftUI
import UIKit

/// Paleta y componentes del hotel.
enum Tema {

    // Colores de marca (azul profundo + dorado)
    static let azul = Color(red: 0.04, green: 0.28, blue: 0.47)
    static let azulOscuro = Color(red: 0.02, green: 0.16, blue: 0.29)
    static let azulClaro = adaptable(claro: UIColor(red: 0.89, green: 0.94, blue: 0.98, alpha: 1),
                                     oscuro: UIColor(red: 0.10, green: 0.19, blue: 0.27, alpha: 1))

    static let dorado = Color(red: 0.79, green: 0.60, blue: 0.18)

    // Neutros adaptables: en modo claro se ven igual que antes y en modo
    // oscuro no hay tarjetas blancas sobre fondo blanco.
    static let fondo = adaptable(claro: UIColor(white: 0.97, alpha: 1),
                                 oscuro: UIColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 1))
    static let superficie = adaptable(claro: .white,
                                      oscuro: UIColor(red: 0.12, green: 0.13, blue: 0.16, alpha: 1))

    static let texto = adaptable(claro: UIColor(red: 0.09, green: 0.11, blue: 0.13, alpha: 1),
                                 oscuro: UIColor(white: 0.95, alpha: 1))
    static let textoSecundario = adaptable(claro: UIColor(white: 0.44, alpha: 1),
                                           oscuro: UIColor(white: 0.66, alpha: 1))
    /// Borde fino de tarjetas y separadores.
    static let borde = adaptable(claro: UIColor(white: 0, alpha: 0.06),
                                 oscuro: UIColor(white: 1, alpha: 0.12))

    private static func adaptable(claro: UIColor, oscuro: UIColor) -> Color {
        Color(uiColor: UIColor(dynamicProvider: { trazo in
            trazo.userInterfaceStyle == .dark ? oscuro : claro
        }))
    }

    // Paleta clara del login (estilo neumórfico).
    static let tinta = Color(red: 0.07, green: 0.10, blue: 0.20)
    static let tintaSuave = Color(red: 0.42, green: 0.47, blue: 0.58)
    static let tintaFondo = Color(red: 0.93, green: 0.96, blue: 0.99)
    /// Azul de acento del login (más luminoso que el de marca).
    static let azulSuave = Color(red: 0.20, green: 0.42, blue: 0.95)

    static let exito = Color(red: 0.02, green: 0.47, blue: 0.34)
    static let alerta = Color(red: 0.78, green: 0.45, blue: 0.03)
    static let peligro = Color(red: 0.72, green: 0.14, blue: 0.14)
    static let info = Color(red: 0.11, green: 0.36, blue: 0.60)

    static let radio: CGFloat = 20
    static let radioPequeno: CGFloat = 12
    /// Sombra suave común a tarjetas.
    static let colorSombra = Color.black.opacity(0.06)

    static func soles(_ valor: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "PEN"
        formatter.currencySymbol = "S/"
        formatter.locale = Locale(identifier: "es_PE")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: valor)) ?? "S/ 0.00"
    }
}

// MARK: - Componentes

struct Tarjeta<Contenido: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var contenido: Contenido

    var body: some View {
        contenido
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tema.superficie)
            .clipShape(RoundedRectangle(cornerRadius: Tema.radio, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Tema.radio, style: .continuous)
                    .stroke(Tema.borde, lineWidth: 1))
            .shadow(color: Tema.colorSombra, radius: 12, x: 0, y: 4)
    }
}

struct EtiquetaEstado: View {
    let texto: String
    let color: Color
    var icono: String?

    var body: some View {
        HStack(spacing: 4) {
            if let icono {
                Image(systemName: icono).font(.caption2.weight(.bold))
            }
            Text(texto).font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(color.opacity(0.12))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }
}

struct Aviso: View {
    enum Tipo {
        case info, exito, alerta, peligro

        var color: Color {
            switch self {
            case .info: return Tema.info
            case .exito: return Tema.exito
            case .alerta: return Tema.alerta
            case .peligro: return Tema.peligro
            }
        }

        var icono: String {
            switch self {
            case .info: return "info.circle.fill"
            case .exito: return "checkmark.seal.fill"
            case .alerta: return "exclamationmark.triangle.fill"
            case .peligro: return "xmark.octagon.fill"
            }
        }
    }

    let tipo: Tipo
    var titulo: String?
    let mensaje: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: tipo.icono)
                .foregroundStyle(tipo.color)
                .font(.system(size: 16))

            VStack(alignment: .leading, spacing: 3) {
                if let titulo {
                    Text(titulo).font(.subheadline.weight(.semibold))
                }
                Text(mensaje)
                    .font(.footnote)
                    .foregroundStyle(Tema.textoSecundario)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(tipo.color.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: Tema.radioPequeno)
                .stroke(tipo.color.opacity(0.25), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Tema.radioPequeno))
    }
}

struct BotonPrincipal: View {
    let titulo: String
    var icono: String?
    var cargando = false
    var deshabilitado = false
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            HStack(spacing: 8) {
                if cargando {
                    ProgressView().tint(.white)
                } else if let icono {
                    Image(systemName: icono)
                }
                Text(cargando ? "Procesando..." : titulo)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(deshabilitado || cargando ? Tema.azul.opacity(0.45) : Tema.azul)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: Tema.radioPequeno, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(deshabilitado || cargando)
    }
}

struct EstadoVacio: View {
    let icono: String
    let titulo: String
    let mensaje: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icono)
                .font(.largeTitle)
                .foregroundStyle(Tema.azul.opacity(0.5))
            Text(titulo).font(.headline)
            Text(mensaje)
                .font(.subheadline)
                .foregroundStyle(Tema.textoSecundario)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(Tema.superficie)
        .clipShape(RoundedRectangle(cornerRadius: Tema.radio))
        .overlay(
            RoundedRectangle(cornerRadius: Tema.radio)
                .stroke(Tema.borde, lineWidth: 1))
        .shadow(color: Tema.colorSombra, radius: 12, x: 0, y: 4)
    }
}

// MARK: - Etiquetas de negocio

enum Etiquetas {

    static func estadoReserva(_ estado: String) -> (texto: String, color: Color) {
        switch estado {
        case "PENDIENTE": return ("Esperando depósito", Tema.alerta)
        case "CONFIRMADA": return ("Confirmada", Tema.exito)
        case "EN_CURSO": return ("En curso", Tema.azul)
        case "COMPLETADA": return ("Completada", Tema.textoSecundario)
        case "CANCELADA": return ("Cancelada", Tema.peligro)
        case "NO_SHOW": return ("No se presentó", Tema.textoSecundario)
        default: return (estado, Tema.textoSecundario)
        }
    }

    static func estadoHabitacion(_ estado: String) -> (texto: String, color: Color) {
        switch estado {
        case "DISPONIBLE": return ("Disponible", Tema.exito)
        case "OCUPADA": return ("Ocupada", Tema.azul)
        case "LIMPIEZA": return ("En limpieza", Tema.info)
        case "MANTENIMIENTO": return ("Mantenimiento", Tema.alerta)
        case "FUERA_SERVICIO": return ("Fuera de servicio", Tema.peligro)
        default: return (estado, Tema.textoSecundario)
        }
    }

    static func estadoPago(_ estado: String) -> (texto: String, color: Color) {
        switch estado {
        case "COMPLETADO": return ("Pagado", Tema.exito)
        case "PENDIENTE": return ("Por validar", Tema.alerta)
        case "EN_VERIFICACION": return ("En verificación", Tema.info)
        case "RECHAZADO": return ("Rechazado", Tema.peligro)
        case "REEMBOLSADO": return ("Reembolsado", Tema.textoSecundario)
        default: return (estado, Tema.textoSecundario)
        }
    }

    static func prioridad(_ valor: String) -> (texto: String, color: Color) {
        switch valor {
        case "URGENTE", "CRITICA": return ("Urgente", Tema.peligro)
        case "ALTA": return ("Alta", Tema.alerta)
        default: return ("Normal", Tema.textoSecundario)
        }
    }

    static func estadoTarea(_ estado: String) -> (texto: String, color: Color) {
        switch estado {
        case "PENDIENTE": return ("Pendiente", Tema.alerta)
        case "EN_PROCESO": return ("En proceso", Tema.info)
        case "COMPLETADA": return ("Completada", Tema.exito)
        case "VERIFICADA": return ("Verificada", Tema.textoSecundario)
        default: return (estado, Tema.textoSecundario)
        }
    }
}

// MARK: - Estilos

/// Feedback táctil sutil: escala 0.97 al presionar.
struct EstiloPresionable: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}