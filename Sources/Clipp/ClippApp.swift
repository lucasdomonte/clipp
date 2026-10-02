import AppKit
import SwiftUI

@main
enum ClippApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private lazy var model = ClipboardModel()
    private var settingsWindow: NSWindow?
    private let launchAtLogin = LaunchAtLogin()
    private let shortcut = GlobalShortcut()
    private var historyPanel: HistoryPanel?
    private var outsideClickMonitor: Any?
    private var localClickMonitor: Any?
    private var pasteTarget: NSRunningApplication?
    private var pasteTask: Task<Void, Never>?
    private var pastesOnSelect = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(named: "MenuBarIconTemplate")
            ?? NSImage(systemSymbolName: "paperclip", accessibilityDescription: "Clipp — histórico do clipboard")
        item.button?.image?.isTemplate = true
        item.button?.image?.size = NSSize(width: 18, height: 18)
        item.button?.setAccessibilityLabel("Clipp — histórico do clipboard")
        item.button?.toolTip = "Clipp — histórico do clipboard"
        item.button?.target = self
        item.button?.action = #selector(toggleHistoryFromStatusItem)
        statusItem = item
        model.start()
        launchAtLogin.configureOnFirstLaunch()
        shortcut.onTrigger = { [weak self] in self?.toggleHistoryPanel() }
        shortcut.start()
    }

    private func showSettings() {
        closeHistoryPanel()
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 650),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Configurações do Clipp"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: SettingsView(model: model, feedback: model.feedback, launchAtLogin: launchAtLogin, shortcut: shortcut))
            window.delegate = self
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        model.isSettingsVisible = true
        launchAtLogin.refreshStatus()
        Task {
            await model.refreshStats()
            await model.feedback.refreshAuthorization()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        launchAtLogin.refreshStatus()
        Task { await model.feedback.refreshAuthorization() }
    }

    @objc private func toggleHistoryFromStatusItem() {
        guard let button = statusItem?.button, let window = button.window else { return }
        showHistory(at: window.convertToScreen(button.convert(button.bounds, to: nil)), paste: false)
    }

    private func toggleHistoryPanel() {
        showHistory(at: NSRect(origin: NSEvent.mouseLocation, size: NSSize(width: 1, height: 1)), paste: true)
    }

    private func showHistory(at anchor: NSRect, paste: Bool) {
        shortcut.cancelRecording()
        if historyPanel?.isVisible == true, pastesOnSelect == paste {
            closeHistoryPanel()
            return
        }
        closeHistoryPanel()
        pastesOnSelect = paste
        // Keep the app that owns the input before our search field takes keyboard focus.
        let previousApp = NSWorkspace.shared.frontmostApplication
        pasteTarget = paste && previousApp?.processIdentifier != ProcessInfo.processInfo.processIdentifier ? previousApp : nil
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor.origin) })
                ?? NSScreen.main else { return }
        let frame = HistoryAnchor.panelFrame(anchor: anchor, visibleFrame: screen.visibleFrame)
        if historyPanel == nil {
            let panel = HistoryPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 580),
                                     styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isFloatingPanel = true
            panel.level = .popUpMenu
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.onDismiss = { [weak self] in self?.closeHistoryPanel() }
            historyPanel = panel
        }
        guard let panel = historyPanel else { return }
        let onSelect: ((ClipboardEntry) -> Void)? = paste ? { [weak self] entry in self?.pasteHistoryEntry(entry) } : nil
        model.isHistoryVisible = true
        let hosting = NSHostingController(rootView:
            HistoryView(model: model, onSettings: { [weak self] in self?.showSettings() },
                        onSelect: onSelect, size: frame.size)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .onExitCommand { [weak self] in self?.closeHistoryPanel() })
        // Keep SwiftUI from resizing the window after its screen bounds were calculated.
        hosting.sizingOptions = []
        hosting.view.setFrameSize(frame.size)
        panel.contentViewController = hosting
        panel.setFrame(frame, display: false)
        hosting.view.layoutSubtreeIfNeeded()
        panel.makeKeyAndOrderFront(nil)
        panel.setFrame(frame, display: true)
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.closeHistoryPanel() }
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            if event.window !== self?.historyPanel, event.window !== self?.statusItem?.button?.window {
                self?.closeHistoryPanel()
            }
            return event
        }
    }

    private func pasteHistoryEntry(_ entry: ClipboardEntry) {
        guard pasteTask == nil else { return }
        let target = pasteTarget
        pasteTask = Task { [weak self] in
            guard let self else { return }
            defer { self.pasteTask = nil }
            guard let changeCount = await model.copy(entry), !Task.isCancelled else { return }
            guard let target else {
                model.errorMessage = "Item copiado. Abra o histórico a partir do aplicativo em que deseja colar, ou use ⌘V."
                return
            }
            guard PasteController.isAllowed else {
                model.errorMessage = "Item copiado. Para colar automaticamente, autorize a colagem nas configurações do Clipp. Você também pode fechar esta janela e usar ⌘V."
                return
            }
            self.closeHistoryPanel(cancelPaste: false)
            if let error = await PasteController.paste(into: target, expectedChangeCount: changeCount), !Task.isCancelled {
                model.errorMessage = error
            }
        }
    }

    private func closeHistoryPanel(cancelPaste: Bool = true) {
        if cancelPaste { pasteTask?.cancel() }
        pasteTarget = nil
        historyPanel?.orderOut(nil)
        historyPanel?.contentViewController = nil
        model.isHistoryVisible = false
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
        outsideClickMonitor = nil
        localClickMonitor = nil
    }

    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === settingsWindow {
            shortcut.cancelRecording()
            model.isSettingsVisible = false
        }
    }

    func applicationDidResignActive(_ notification: Notification) {
        shortcut.cancelRecording()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
        shortcut.stop()
        closeHistoryPanel()
    }
}

@MainActor
private final class HistoryPanel: NSPanel {
    var onDismiss: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onDismiss?() }
}
