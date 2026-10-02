import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: ClipboardModel
    @ObservedObject var feedback: CopyFeedback
    @ObservedObject var launchAtLogin: LaunchAtLogin
    @ObservedObject var shortcut: GlobalShortcut
    @State private var unlimited = true
    @State private var limitText = "1000"
    @State private var confirmation: Confirmation?
    @State private var pasteAllowed = PasteController.isAllowed

    private enum Confirmation {
        case clear
        case limit(Int)
    }

    private var requestedLimit: Int? {
        unlimited ? 0 : Int(limitText.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0 > 0 ? $0 : nil }
    }

    var body: some View {
        Form {
            Section {
                Toggle("Iniciar com o Mac", isOn: Binding(get: { launchAtLogin.isEnabled }, set: { launchAtLogin.setEnabled($0) }))
                Text(launchAtLogin.statusMessage)
                    .font(.caption).foregroundStyle(.secondary)
                if launchAtLogin.requiresApproval {
                    Button("Abrir itens de início do macOS", action: launchAtLogin.openSystemSettings)
                }
            } header: {
                Label("Inicialização", systemImage: "power")
            }

            Section {
                HStack {
                    Text("Abrir histórico")
                    Spacer()
                    Button(shortcut.isRecording ? "Pressione o atalho…" : shortcut.displayName) {
                        shortcut.beginRecording()
                    }
                    .accessibilityLabel("Configurar atalho para abrir o histórico")
                    if shortcut.isRecording {
                        Button("Cancelar", action: shortcut.cancelRecording)
                    } else {
                        Button("Remover", action: shortcut.clear)
                    }
                }
                Text("Use ⌘ ou ⌃ com outra tecla. O histórico abre na posição do mouse. Clique em um item para colar no aplicativo anterior. Esc fecha a janela.")
                    .font(.caption).foregroundStyle(.secondary)
                if let error = shortcut.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
                if !pasteAllowed {
                    Text("Para colar automaticamente com ⌘V, o macOS exige Acessibilidade. Sem essa permissão, o item fica copiado para colar manualmente.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Autorizar colagem automática", action: PasteController.requestAccess)
                }
            } header: {
                Label("Atalho de teclado", systemImage: "keyboard")
            }

            Section {
                Toggle("Mostrar notificação ao copiar", isOn: $model.notificationsEnabled)
                    .onChange(of: model.notificationsEnabled) { enabled in
                        if enabled { Task { await feedback.requestAuthorization() } }
                    }
                if model.notificationsEnabled {
                    Toggle("Mostrar texto copiado na notificação", isOn: $model.showCopiedTextInNotifications)
                }
                Text(feedback.authorizationDescription)
                    .font(.caption).foregroundStyle(.secondary)
                if model.notificationsEnabled {
                    if feedback.needsSystemSettings {
                        Button("Abrir ajustes de notificações", action: feedback.openSystemSettings)
                    } else if !feedback.notificationsAllowed {
                        Button("Autorizar notificações") { Task { await feedback.requestAuthorization() } }
                    }
                }
                Toggle("Reproduzir som ao copiar", isOn: $model.soundEnabled)
                Text("Som padrão do Mac (Tink). Funciona independentemente da notificação, ao capturar uma cópia ou copiar pelo histórico.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Label("Notificações e som", systemImage: "bell")
            }

            Section {
                Toggle("Sem limite de itens", isOn: $unlimited)
                if !unlimited {
                    HStack {
                        Text("Manter os últimos")
                        TextField("1000", text: $limitText)
                            .textFieldStyle(.roundedBorder).frame(width: 120)
                            .accessibilityLabel("Quantidade de itens no histórico")
                        Text("itens")
                    }
                }
                Text("Quanto mais itens e imagens, maior o uso do disco. Com limite, os itens mais antigos são excluídos automaticamente.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text(model.historyLimit == 0 ? "Atual: sem limite" : "Atual: \(model.historyLimit) itens")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Aplicar limite") {
                        guard let limit = requestedLimit else { return }
                        if limit > 0 && model.total > limit {
                            confirmation = .limit(limit)
                        } else {
                            Task { await model.applyHistoryLimit(limit) }
                        }
                    }
                    .disabled(requestedLimit == nil || requestedLimit == model.historyLimit || model.isMaintaining || model.store == nil)
                }
            } header: {
                Label("Histórico", systemImage: "clock.arrow.circlepath")
            }

            Section {
                LabeledContent("Histórico (\(model.total) itens)", value: bytes(model.diskUsage))
                Text("Inclui banco de dados, miniaturas e arquivos auxiliares do SQLite.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Abrir pasta de dados") { NSWorkspace.shared.open(model.directory) }
            } header: {
                Label("Armazenamento local", systemImage: "internaldrive")
            }

            Section {
                Button("Limpar todo o histórico…", role: .destructive) { confirmation = .clear }
                    .disabled(model.total == 0 || model.isMaintaining || model.store == nil)
                Text("Após confirmar, os itens são excluídos imediatamente, sem backup ou possibilidade de desfazer.")
                    .font(.caption).foregroundStyle(.secondary)
                if model.isMaintaining {
                    HStack { ProgressView().controlSize(.small); Text("Processando…").font(.caption) }
                }
                if let message = model.settingsMessage {
                    Text(message).font(.caption).textSelection(.enabled)
                }
            } header: {
                Label("Limpeza", systemImage: "trash")
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 650)
        .onAppear {
            pasteAllowed = PasteController.isAllowed
            unlimited = model.historyLimit == 0
            limitText = String(model.historyLimit == 0 ? 1000 : model.historyLimit)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            pasteAllowed = PasteController.isAllowed
        }
        .onDisappear { shortcut.cancelRecording() }
        .alert(confirmationTitle, isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }), presenting: confirmation) { action in
            Button("Cancelar", role: .cancel) { }
            switch action {
            case .clear:
                Button("Excluir tudo", role: .destructive) { Task { await model.clearHistory() } }
            case .limit(let limit):
                Button("Manter \(limit) itens", role: .destructive) { Task { await model.applyHistoryLimit(limit) } }
            }
        } message: { action in
            switch action {
            case .clear:
                Text("Todos os itens do histórico serão excluídos imediatamente. Nenhum backup será criado e não será possível desfazer.")
            case .limit(let limit):
                Text("Os itens mais antigos que excedem \(limit) serão excluídos agora e nas próximas cópias, sem backup automático. Não é possível desfazer essa exclusão.")
            }
        }
    }

    private var confirmationTitle: String {
        if case .limit = confirmation { return "Reduzir o histórico?" }
        return "Limpar todo o histórico?"
    }

    private func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}
