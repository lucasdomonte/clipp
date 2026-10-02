import AppKit
import Carbon
import Combine

@MainActor
final class GlobalShortcut: ObservableObject {
    var displayName: String { shortcut?.displayName ?? "Não definido" }
    @Published private(set) var isRecording = false
    @Published private(set) var errorMessage: String?
    var onTrigger: (() -> Void)?

    private struct Shortcut {
        let keyCode: UInt32
        let modifiers: UInt32
        let key: String

        var displayName: String {
            [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")]
                .filter { modifiers & UInt32($0.0) != 0 }.map(\.1).joined() + key
        }
    }

    private let defaults: UserDefaults
    private let enabled: Bool
    @Published private var shortcut: Shortcut?
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var recordingMonitor: Any?
    private static let preferenceKey = "historyShortcut"

    init(defaults: UserDefaults = .standard, enabled: Bool = true) {
        self.defaults = defaults
        self.enabled = enabled
        let saved = defaults.dictionary(forKey: Self.preferenceKey)
        if saved?["enabled"] as? Bool == false {
            shortcut = nil
        } else if let code = saved?["keyCode"] as? Int, let keyCode = UInt32(exactly: code),
                  let flags = saved?["modifiers"] as? Int, let modifiers = UInt32(exactly: flags),
                  let key = saved?["key"] as? String, !key.isEmpty,
                  Self.validationMessage(keyCode: keyCode, modifiers: modifiers) == nil {
            shortcut = Shortcut(keyCode: keyCode, modifiers: modifiers, key: key)
        } else {
            shortcut = Shortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey), key: "V")
        }
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        if let recordingMonitor { NSEvent.removeMonitor(recordingMonitor) }
    }

    func start() {
        guard enabled, !isRecording, hotKey == nil, let shortcut else { return }
        errorMessage = register(shortcut) == noErr ? nil
            : "O macOS não aceitou o atalho. Ele pode estar em uso; escolha outra combinação."
    }

    func stop() {
        finishRecording()
        unregisterShortcut()
        if let eventHandler { RemoveEventHandler(eventHandler) }
        eventHandler = nil
    }

    func beginRecording() {
        guard enabled, !isRecording else { return }
        unregisterShortcut()
        isRecording = true
        errorMessage = nil
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            self.record(event)
            return nil
        }
    }

    func cancelRecording() {
        guard isRecording else { return }
        finishRecording()
        errorMessage = nil
        start()
    }

    func clear() {
        stop()
        shortcut = nil
        errorMessage = nil
        defaults.set(["enabled": false], forKey: Self.preferenceKey)
    }

    static func validationMessage(keyCode: UInt32, modifiers: UInt32) -> String? {
        let allowed = UInt32(cmdKey | controlKey | optionKey | shiftKey)
        guard keyCode < 128, modifiers & ~allowed == 0 else { return "Combinação de teclas inválida." }
        guard modifiers & UInt32(cmdKey | controlKey) != 0 else {
            return "Use ⌘ Command ou ⌃ Control junto de outra tecla. Esc cancela."
        }
        let commonCommandKeys = [kVK_ANSI_A, kVK_ANSI_C, kVK_ANSI_V, kVK_ANSI_X, kVK_ANSI_Z,
                                 kVK_ANSI_W, kVK_ANSI_H, kVK_ANSI_M, kVK_ANSI_Comma]
        if (modifiers == UInt32(cmdKey) && commonCommandKeys.contains(Int(keyCode)))
            || (modifiers & UInt32(cmdKey) != 0 && [kVK_ANSI_Q, kVK_Tab, kVK_Space, kVK_Escape].contains(Int(keyCode))) {
            return "Esse atalho é usado pelo Mac ou para edição. Escolha outra combinação."
        }
        return nil
    }

    private func record(_ event: NSEvent) {
        guard !event.isARepeat else { return }
        if event.keyCode == kVK_Escape {
            cancelRecording()
            return
        }
        let flags: [(NSEvent.ModifierFlags, Int)] = [(.command, cmdKey), (.control, controlKey),
                                                   (.option, optionKey), (.shift, shiftKey)]
        let modifiers = flags.reduce(UInt32(0)) { result, pair in
            result | (event.modifierFlags.contains(pair.0) ? UInt32(pair.1) : 0)
        }
        if let message = Self.validationMessage(keyCode: UInt32(event.keyCode), modifiers: modifiers) {
            errorMessage = message
            return
        }
        let specialKeys = [kVK_Space: "Espaço", kVK_Return: "↩", kVK_ANSI_KeypadEnter: "⌤",
                           kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
                           kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
                           kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟"]
        let functionKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                            kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
        let key = specialKeys[Int(event.keyCode)]
            ?? functionKeys.firstIndex(of: Int(event.keyCode)).map { "F\($0 + 1)" }
            ?? event.charactersIgnoringModifiers?.uppercased() ?? ""
        guard !key.isEmpty, key.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            errorMessage = "Escolha uma letra, número ou tecla de navegação com ⌘ ou ⌃."
            return
        }
        let candidate = Shortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers, key: key)
        guard register(candidate) == noErr else {
            finishRecording()
            start() // Restore the previous shortcut without changing the saved preference.
            errorMessage = "Esse atalho já está em uso ou não foi aceito pelo macOS. Escolha outro."
            return
        }
        shortcut = candidate
        defaults.set(["enabled": true, "keyCode": Int(candidate.keyCode),
                      "modifiers": Int(candidate.modifiers), "key": candidate.key], forKey: Self.preferenceKey)
        finishRecording()
        errorMessage = nil
    }

    private func finishRecording() {
        if let recordingMonitor { NSEvent.removeMonitor(recordingMonitor) }
        recordingMonitor = nil
        isRecording = false
    }

    private func unregisterShortcut() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }

    private func register(_ shortcut: Shortcut) -> OSStatus {
        if eventHandler == nil {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var identifier = EventHotKeyID()
                let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                               EventParamType(typeEventHotKeyID), nil,
                                               .init(MemoryLayout<EventHotKeyID>.size), nil, &identifier)
                guard result == noErr, identifier.signature == 0x434C4950, identifier.id == 1 else {
                    return OSStatus(eventNotHandledErr)
                }
                // Application Carbon events are delivered on the main event loop.
                MainActor.assumeIsolated {
                    let owner = Unmanaged<GlobalShortcut>.fromOpaque(userData).takeUnretainedValue()
                    if !owner.isRecording { owner.onTrigger?() }
                }
                return noErr
            }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
            guard status == noErr else { return status }
        }
        return RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers,
                                   EventHotKeyID(signature: 0x434C4950, id: 1),
                                   GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &hotKey)
    }
}
