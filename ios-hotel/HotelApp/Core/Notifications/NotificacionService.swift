import Foundation
import UserNotifications

/// Notificaciones locales de la app.
enum NotificacionService {

    static func solicitarPermiso() async {
        let centro = UNUserNotificationCenter.current()
        _ = try? await centro.requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Avisa cuando una reserva pendiente está por expirar.
    static func programarAvisoExpiracion(codigo: String, expiraEn: Date) async {
        let centro = UNUserNotificationCenter.current()
        centro.removePendingNotificationRequests(withIdentifiers: ["reserva.expira"])

        let aviso = expiraEn.addingTimeInterval(-300)
        guard aviso > Date() else { return }

        let contenido = UNMutableNotificationContent()
        contenido.title = "Tu reserva está por expirar"
        contenido.body = "La reserva \(codigo) se cancelará si no pagas el depósito."
        contenido.sound = .default

        let componentes = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: aviso)
        let disparador = UNCalendarNotificationTrigger(dateMatching: componentes, repeats: false)

        try? await centro.add(UNNotificationRequest(
            identifier: "reserva.expira", content: contenido, trigger: disparador))
    }

    /// Cancela el aviso de expiración (cuando ya se pagó o se canceló).
    static func cancelarAvisoExpiracion() {
        let centro = UNUserNotificationCenter.current()
        centro.removePendingNotificationRequests(withIdentifiers: ["reserva.expira"])
    }

    /// Aviso inmediato de cambio de estado.
    static func notificarEstado(reservaId: Int, estado: String) async {
        let centro = UNUserNotificationCenter.current()

        let contenido = UNMutableNotificationContent()
        contenido.sound = .default

        switch estado {
        case "CONFIRMADA":
            contenido.title = "Reserva confirmada"
            contenido.body = "Tu reserva #\(reservaId) está confirmada. ¡Te esperamos!"
        case "CANCELADA":
            contenido.title = "Reserva cancelada"
            contenido.body = "La reserva #\(reservaId) fue cancelada."
        case "COMPLETADA":
            contenido.title = "Check-out realizado"
            contenido.body = "Gracias por tu estadía. Esperamos verte pronto."
        default:
            return
        }

        try? await centro.add(UNNotificationRequest(
            identifier: "reserva.\(reservaId)",
            content: contenido,
            trigger: nil))
    }

    static func cancelarAvisos() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
