import Combine
import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLogin: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var requiresApproval = false
    @Published private(set) var statusMessage = "Inicialização automática disponível ao executar o aplicativo Clipp."

    private let defaults: UserDefaults
    private let readStatus: (() -> SMAppService.Status)?
    private let register: () throws -> Void
    private let unregister: () throws -> Void
    private var status: SMAppService.Status = .notRegistered
    private let configuredKey = "launchAtLoginConfigured"

    convenience init(defaults: UserDefaults = .standard, enabled: Bool = true) {
        guard enabled, Bundle.main.bundleIdentifier == "br.com.clipp.app" else {
            self.init(defaults: defaults, readStatus: nil, register: {}, unregister: {})
            return
        }
        let service = SMAppService.mainApp
        self.init(defaults: defaults, readStatus: { service.status },
                  register: { try service.register() }, unregister: { try service.unregister() })
    }

    init(defaults: UserDefaults, readStatus: (() -> SMAppService.Status)?,
         register: @escaping () throws -> Void, unregister: @escaping () throws -> Void) {
        self.defaults = defaults
        self.readStatus = readStatus
        self.register = register
        self.unregister = unregister
        refreshStatus()
    }

    func configureOnFirstLaunch() {
        guard readStatus != nil else { return }
        refreshStatus()
        if isEnabled {
            defaults.set(true, forKey: configuredKey)
        }
        // Respect later changes made either here or in System Settings.
        guard !defaults.bool(forKey: configuredKey) else { return }
        setEnabled(true)
    }

    func refreshStatus() {
        guard let readStatus else { return }
        status = readStatus()
        requiresApproval = status == .requiresApproval
        isEnabled = status == .enabled || requiresApproval
        switch status {
        case .enabled:
            statusMessage = "O Clipp abrirá na barra de menus ao iniciar sua sessão no Mac."
        case .requiresApproval:
            statusMessage = "Aguardando autorização do macOS. Ative o Clipp em Ajustes do Sistema → Geral → Itens de Início."
        case .notRegistered:
            statusMessage = "A inicialização automática está desativada."
        case .notFound:
            statusMessage = "O macOS não encontrou o aplicativo. Instale o Clipp na pasta Aplicativos e tente novamente."
        @unknown default:
            statusMessage = "Não foi possível identificar a configuração de inicialização do macOS."
        }
    }

    func setEnabled(_ value: Bool) {
        guard readStatus != nil else { return }
        refreshStatus()
        do {
            if value, !isEnabled {
                try register()
            } else if !value, status != .notRegistered {
                try unregister()
            }
            refreshStatus()
            guard value ? isEnabled : status == .notRegistered else {
                statusMessage = "O macOS não confirmou a alteração. \(statusMessage)"
                return
            }
            defaults.set(true, forKey: configuredKey)
        } catch {
            refreshStatus()
            statusMessage = "Não foi possível alterar a inicialização automática: \(error.localizedDescription)"
        }
    }

    func openSystemSettings() {
        guard readStatus != nil else { return }
        SMAppService.openSystemSettingsLoginItems()
    }
}
