import AppKit
import Combine
import UserNotifications

@MainActor
final class CopyFeedback: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var authorizationDescription = "Verificando permissão de notificações…"
    @Published private(set) var notificationsAllowed = false
    @Published private(set) var needsSystemSettings = false

    private let center: UNUserNotificationCenter?
    private var authorizationStatus: UNAuthorizationStatus = .notDetermined

    init(enabled: Bool = true) {
        // UserNotifications requires an actual app bundle; command-line tests must stay inert.
        if enabled, Bundle.main.bundleIdentifier == "br.com.clipp.app" {
            center = UNUserNotificationCenter.current()
        } else {
            center = nil
        }
        super.init()
        center?.delegate = self
        if center == nil {
            authorizationDescription = "Notificações disponíveis ao executar o aplicativo Clipp."
        }
    }

    func refreshAuthorization() async {
        guard let center else { return }
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
        notificationsAllowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        needsSystemSettings = settings.authorizationStatus == .denied
            || settings.authorizationStatus == .provisional
            || (notificationsAllowed && settings.alertSetting != .enabled)
        switch settings.authorizationStatus {
        case .notDetermined:
            authorizationDescription = "O macOS ainda não recebeu sua permissão para notificações."
        case .denied:
            authorizationDescription = "Bloqueadas no macOS. Habilite o Clipp em Ajustes do Sistema → Notificações."
        case .authorized:
            authorizationDescription = settings.alertSetting == .enabled
                ? "Notificações permitidas pelo macOS."
                : "Permissão concedida; habilite os banners em Ajustes do Sistema → Notificações → Clipp."
        case .provisional:
            authorizationDescription = "Entrega silenciosa autorizada. Habilite os banners em Ajustes do Sistema → Notificações → Clipp."
        @unknown default:
            authorizationDescription = "Não foi possível identificar a permissão de notificações do macOS."
        }
    }

    func requestAuthorization() async {
        guard let center else { return }
        await refreshAuthorization()
        guard Self.shouldRequestAuthorization(for: authorizationStatus) else { return }
        do {
            _ = try await center.requestAuthorization(options: [.alert])
            await refreshAuthorization()
        } catch {
            await refreshAuthorization()
            if authorizationStatus != .denied {
                authorizationDescription = "Não foi possível solicitar notificações: \(error.localizedDescription)"
            }
        }
    }

    static func shouldRequestAuthorization(for status: UNAuthorizationStatus) -> Bool {
        status == .notDetermined
    }

    func openSystemSettings() {
        let notificationsURL = URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!
        if !NSWorkspace.shared.open(notificationsURL),
           !NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app")) {
            authorizationDescription = "Abra Ajustes do Sistema → Notificações → Clipp para habilitar as notificações."
        }
    }

    static func notificationBody(kind: ClipboardKind, text: String?, showCopiedText: Bool) -> String {
        guard showCopiedText, kind == .text, let text, !text.isEmpty else { return "Disponível para colar." }
        let preview = text.prefix(301)
        return preview.count > 300 ? String(preview.prefix(300)) + "…" : String(preview)
    }

    func notify(kind: ClipboardKind, text: String?, showCopiedText: Bool, notifications: Bool, sound: Bool) async {
        guard let center else { return }
        var errors: [String] = []
        defer {
            if !errors.isEmpty { authorizationDescription = errors.joined(separator: " ") }
        }
        if sound {
            let tone = NSSound(named: NSSound.Name("Tink"))
            tone?.stop()
            if tone?.play() != true {
                errors.append("Não foi possível reproduzir o som de cópia.")
            }
        }
        guard notifications else { return }
        await refreshAuthorization()
        guard notificationsAllowed else { return }
        let content = UNMutableNotificationContent()
        content.title = kind == .text ? "Texto copiado" : "Imagem copiada"
        content.body = Self.notificationBody(kind: kind, text: text, showCopiedText: showCopiedText)
        // Sound is independent of notification permission and is played only once above.
        content.sound = nil
        do {
            try await center.add(UNNotificationRequest(identifier: "clipp-copy", content: content, trigger: nil))
        } catch {
            errors.append("Não foi possível mostrar a notificação: \(error.localizedDescription)")
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }
}
