import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ClipboardModel: ObservableObject {
    @Published var entries: [ClipboardEntry] = []
    @Published var query = ""
    @Published var isPaused = false
    @Published var errorMessage: String?
    @Published var accessDenied = false
    @Published var total = 0
    @Published var hasMore = false
    @Published private(set) var isLoading = false
    @Published private(set) var paginationError: String?
    @Published var copiedID: Int64?
    @Published var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: "notificationsEnabled") }
    }
    @Published var showCopiedTextInNotifications: Bool {
        didSet { defaults.set(showCopiedTextInNotifications, forKey: "showCopiedTextInNotifications") }
    }
    @Published var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: "soundEnabled") }
    }
    @Published private(set) var historyLimit: Int
    @Published private(set) var diskUsage: Int64 = 0
    @Published private(set) var isMaintaining = false
    @Published var settingsMessage: String?

    let directory: URL
    let feedback: CopyFeedback
    private let defaults: UserDefaults
    private let pasteboard: NSPasteboard
    private(set) var store: ClipboardStore?
    private var lastChange: Int
    private var timer: Timer?
    var isHistoryVisible = false {
        didSet { if oldValue && !isHistoryVisible { resetHistory() } }
    }
    var isSettingsVisible = false
    private var captureTask: Task<Void, Never>?
    private var pending: ArraySlice<(content: ClipboardContent, source: String?, date: Date)> = []
    private var revision = 0
    private let pageSize = 30
    private var loadedQuery: String?
    var isLoadingMore: Bool { isLoading && loadedQuery != nil }

    init(pasteboard: NSPasteboard = .general, directory: URL? = nil, defaults: UserDefaults = .standard) {
        self.pasteboard = pasteboard
        self.defaults = defaults
        notificationsEnabled = defaults.object(forKey: "notificationsEnabled") as? Bool ?? true
        showCopiedTextInNotifications = defaults.object(forKey: "showCopiedTextInNotifications") as? Bool ?? true
        soundEnabled = defaults.object(forKey: "soundEnabled") as? Bool ?? true
        historyLimit = max(0, defaults.integer(forKey: "historyLimit"))
        feedback = CopyFeedback(enabled: pasteboard.name == .general)
        // Start with future copies; do not import content from before launch.
        lastChange = pasteboard.changeCount
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Clipp", isDirectory: true)
        do {
            store = try ClipboardStore(directory: self.directory)
        } catch {
            errorMessage = "Não foi possível abrir o histórico: \(error.localizedDescription)"
        }
    }

    func start() {
        guard timer == nil, store != nil else { return }
        // ponytail: polling can miss copies less than 0.5 s apart; lower this interval if needed.
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.poll() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        Task {
            if historyLimit > 0 { await applyHistoryLimit(historyLimit) }
            if notificationsEnabled { await feedback.requestAuthorization() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func togglePause() {
        isPaused.toggle()
        lastChange = pasteboard.changeCount
    }

    func poll() async {
        guard let store, captureTask == nil, !isMaintaining else { return }
        guard !isPaused else {
            lastChange = pasteboard.changeCount
            return
        }
        if #available(macOS 15.4, *) {
            let denied = pasteboard.accessBehavior == .alwaysDeny
            if accessDenied != denied { accessDenied = denied }
            if denied { return }
        }
        let change = pasteboard.changeCount
        guard change != lastChange || !pending.isEmpty else { return }
        let task = Task {
            if change != lastChange {
                let source = NSWorkspace.shared.frontmostApplication?.localizedName
                let date = Date()
                let contents = Self.readContents(from: pasteboard)
                // A new owner can replace the pasteboard while a provider is fulfilling data.
                guard pasteboard.changeCount == change else { return }
                lastChange = change
                var prepared = contents
                if contents.contains(where: { $0.imageData != nil }) {
                    prepared = await Task.detached(priority: .utility) {
                        contents.map { content in
                            guard let data = content.imageData else { return content }
                            return ClipboardContent(kind: .image, text: nil, imageData: data, thumbnail: Self.thumbnail(for: data))
                        }
                    }.value
                }
                pending.append(contentsOf: prepared.map { ($0, source, date) })
            }
            guard !pending.isEmpty else { return }
            do {
                // Retain failed writes for the next poll; successful items are never inserted twice.
                while let item = pending.first {
                    try await store.insert(item.content, sourceApp: item.source, createdAt: item.date)
                    pending.removeFirst()
                    await feedback.notify(kind: item.content.kind, text: item.content.text,
                                          showCopiedText: showCopiedTextInNotifications,
                                          notifications: notificationsEnabled, sound: soundEnabled)
                }
                pending = [] // Release the slice's consumed payloads.
                if historyLimit > 0 { _ = try await store.prune(keeping: historyLimit) }
                errorMessage = nil
                await refreshVisibleContent()
            } catch {
                pending = Array(pending)[...] // Release successful payloads even when the remainder must retry.
                errorMessage = "\(pending.count) cópia(s) aguardando gravação. Mantenha o Clipp aberto para tentar novamente. \(error.localizedDescription)"
            }
        }
        captureTask = task
        await task.value
        captureTask = nil
    }

    static func readContents(from pasteboard: NSPasteboard) -> [ClipboardContent] {
        let excluded = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType"]
            .map { NSPasteboard.PasteboardType($0) }
        guard !(pasteboard.types ?? []).contains(where: excluded.contains) else { return [] }
        return (pasteboard.pasteboardItems ?? []).compactMap { item in
            guard !item.types.contains(where: excluded.contains) else { return nil }
            // Keep the original bytes; decoding and thumbnail work happens off the main thread.
            let imageTypes = [.png, .tiff] + item.types.filter { UTType($0.rawValue)?.conforms(to: .image) == true }
            if let type = item.availableType(from: imageTypes), let data = item.data(forType: type), !data.isEmpty {
                return ClipboardContent(kind: .image, text: nil, imageData: data, thumbnail: nil)
            }
            if let text = item.string(forType: .string), !text.isEmpty {
                return ClipboardContent(kind: .text, text: text, imageData: nil, thumbnail: nil)
            }
            return nil
        }
    }

    nonisolated static func thumbnail(for data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 240,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        let result = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(result, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return result as Data
    }

    private func resetHistory() {
        revision += 1
        entries = []
        hasMore = false
        isLoading = false
        loadedQuery = nil
        paginationError = nil
    }

    func reload() async {
        guard let store else { return }
        revision += 1
        let currentRevision = revision
        let currentQuery = query
        if loadedQuery != currentQuery { entries = [] }
        loadedQuery = nil
        hasMore = false
        isLoading = true
        paginationError = nil
        defer { if revision == currentRevision { isLoading = false } }
        do {
            let result = try await store.fetch(query: currentQuery, limit: pageSize + 1)
            let count = try await store.count()
            guard revision == currentRevision, query == currentQuery, !Task.isCancelled else { return }
            entries = Array(result.prefix(pageSize))
            loadedQuery = currentQuery
            hasMore = result.count > pageSize
            total = count
        } catch {
            guard revision == currentRevision, query == currentQuery else { return }
            errorMessage = "Não foi possível carregar o histórico: \(error.localizedDescription)"
        }
    }

    func loadMore() async {
        guard let store, hasMore, !isLoading,
              loadedQuery == query, let last = entries.last else { return }
        let currentRevision = revision
        let currentQuery = query
        isLoading = true
        paginationError = nil
        defer { if revision == currentRevision { isLoading = false } }
        do {
            let result = try await store.fetch(query: currentQuery, limit: pageSize + 1, before: last)
            guard revision == currentRevision, query == currentQuery, !Task.isCancelled else { return }
            entries.append(contentsOf: result.prefix(pageSize))
            hasMore = result.count > pageSize
        } catch {
            guard revision == currentRevision, query == currentQuery else { return }
            paginationError = "Não foi possível carregar mais itens: \(error.localizedDescription)"
        }
    }

    func loadMoreIfNeeded(after entry: ClipboardEntry) async {
        guard paginationError == nil, entries.suffix(5).contains(where: { $0.id == entry.id }) else { return }
        await loadMore()
    }

    @discardableResult
    func copy(_ entry: ClipboardEntry) async -> Int? {
        guard let store, !isMaintaining else { return nil }
        do {
            guard let content = try await store.content(id: entry.id) else { return nil }
            let item = NSPasteboardItem()
            if let text = content.text {
                item.setString(text, forType: .string)
            } else if let data = content.imageData,
                      let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let type = CGImageSourceGetType(source) {
                item.setData(data, forType: NSPasteboard.PasteboardType(type as String))
            } else {
                errorMessage = "Esta imagem não pôde ser copiada."
                return nil
            }
            pasteboard.clearContents()
            let succeeded = pasteboard.writeObjects([item])
            let change = pasteboard.changeCount
            lastChange = change // Recopies must not create a feedback loop.
            guard succeeded else {
                errorMessage = "Não foi possível copiar este item."
                return nil
            }
            copiedID = entry.id
            await feedback.notify(kind: content.kind, text: content.text,
                                  showCopiedText: showCopiedTextInNotifications,
                                  notifications: notificationsEnabled, sound: soundEnabled)
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if self?.copiedID == entry.id { self?.copiedID = nil }
            }
            return change
        } catch {
            errorMessage = "Não foi possível copiar: \(error.localizedDescription)"
            return nil
        }
    }

    func delete(_ entry: ClipboardEntry) async {
        guard !isMaintaining else { return }
        do {
            try await store?.delete(id: entry.id)
            await refreshVisibleContent()
        } catch {
            errorMessage = "Não foi possível excluir: \(error.localizedDescription)"
        }
    }

    func refreshStats() async {
        guard let store else { return }
        do {
            total = try await store.count()
            diskUsage = try await store.diskUsage()
        } catch {
            settingsMessage = "Não foi possível medir o uso do disco: \(error.localizedDescription)"
        }
    }

    private func refreshVisibleContent() async {
        if isHistoryVisible { await reload() }
        if isSettingsVisible { await refreshStats() }
    }

    private func maintain(failure: String, _ action: (ClipboardStore) async throws -> Void) async {
        guard let store, !isMaintaining else { return }
        isMaintaining = true
        defer { isMaintaining = false }
        await captureTask?.value
        do {
            try await action(store)
            await refreshVisibleContent()
        } catch {
            settingsMessage = "\(failure): \(error.localizedDescription)"
        }
    }

    func applyHistoryLimit(_ limit: Int) async {
        guard limit >= 0 else {
            settingsMessage = "Informe pelo menos 1 item ou selecione Sem limite."
            return
        }
        await maintain(failure: "Não foi possível aplicar o limite") { store in
            if limit > 0 { _ = try await store.prune(keeping: limit) }
            historyLimit = limit
            defaults.set(limit, forKey: "historyLimit")
            settingsMessage = limit == 0 ? "Histórico sem limite de itens." : "Serão mantidos os \(limit) itens mais recentes."
        }
    }

    func clearHistory() async {
        await maintain(failure: "A limpeza não foi concluída") { store in
            try await store.clear()
            resetHistory()
            total = 0
            pending = []
            errorMessage = nil
            copiedID = nil
            settingsMessage = "Histórico limpo."
        }
    }
}
