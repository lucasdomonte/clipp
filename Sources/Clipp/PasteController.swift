import AppKit
import Carbon.HIToolbox

@MainActor
enum PasteController {
    static var isAllowed: Bool { CGPreflightPostEventAccess() }

    static func requestAccess() {
        if !CGRequestPostEventAccess() {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }

    static func paste(into application: NSRunningApplication, expectedChangeCount: Int,
                      pasteboard: NSPasteboard = .general) async -> String? {
        guard application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              !application.isTerminated else {
            return "O aplicativo de destino não está disponível. O item foi copiado; use ⌘V para colar."
        }
        guard !Task.isCancelled else { return "Colagem cancelada. O item permanece no clipboard." }
        guard isAllowed else {
            return "O item foi copiado. Para colar automaticamente, autorize o Clipp em Acessibilidade nas configurações."
        }
        guard pasteboard.changeCount == expectedChangeCount else {
            return "O clipboard mudou. Selecione o item novamente para colar."
        }
        guard application.activate(options: [.activateIgnoringOtherApps]) else {
            return "Não foi possível ativar o aplicativo de destino. O item foi copiado; use ⌘V para colar."
        }
        do {
            for _ in 0..<25 {
                if application.isActive || application.isTerminated { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            // Let the receiving app restore its key window before sending the shortcut.
            try await Task.sleep(for: .milliseconds(100))
        } catch {
            return "Colagem cancelada. O item permanece no clipboard."
        }
        guard !Task.isCancelled, !application.isTerminated, application.isActive,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier else {
            return "O aplicativo de destino perdeu o foco. O item foi copiado; use ⌘V para colar."
        }
        guard pasteboard.changeCount == expectedChangeCount else {
            return "O clipboard mudou. Selecione o item novamente para colar."
        }
        guard isAllowed, let events = makePasteEvents() else {
            return "Não foi possível enviar ⌘V. Confira a permissão de Acessibilidade; o item permanece no clipboard."
        }
        for event in events {
            event.postToPid(application.processIdentifier)
        }
        return nil
    }

    static func makePasteEvents() -> [CGEvent]? {
        guard let source = CGEventSource(stateID: .privateState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else { return nil }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        return [keyDown, keyUp]
    }
}
