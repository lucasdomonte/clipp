import AppKit
import SwiftUI

struct HistoryView: View {
    @ObservedObject var model: ClipboardModel
    let onSettings: () -> Void
    let onSelect: ((ClipboardEntry) -> Void)?
    var size = NSSize(width: 420, height: 580)
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Buscar no histórico", text: $model.query)
                    .focused($searchFocused)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Buscar no histórico")
                if !model.query.isEmpty {
                    Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .help("Limpar busca")
                        .accessibilityLabel("Limpar busca")
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 9))
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            if model.accessDenied {
                message("Permita o acesso do Clipp ao clipboard nos Ajustes do Sistema para registrar novas cópias.", symbol: "lock.fill")
            }
            if let error = model.errorMessage {
                HStack(alignment: .top) {
                    message(error, symbol: "exclamationmark.triangle")
                    Button { model.errorMessage = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).padding(12).help("Dispensar aviso")
                }
            }
            Divider()
            if model.isLoading && model.entries.isEmpty {
                ProgressView("Carregando histórico…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.entries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: model.query.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                        .font(.system(size: 36, weight: .light)).foregroundStyle(.secondary)
                    Text(model.query.isEmpty ? "Suas cópias, sempre à mão" : "Nenhum resultado")
                        .font(.headline)
                    Text(model.query.isEmpty ? "Copie um texto ou uma imagem.\nO histórico aparece aqui automaticamente." : "Tente buscar por outro texto.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(model.entries) { entry in
                            HistoryRow(entry: entry, copied: model.copiedID == entry.id,
                                       onPaste: onSelect.map { action in { action(entry) } },
                                       onCopy: { Task { await model.copy(entry) } },
                                       onDelete: { Task { await model.delete(entry) } })
                                .onAppear { Task { await model.loadMoreIfNeeded(after: entry) } }
                        }
                        if model.isLoadingMore {
                            ProgressView().controlSize(.small).padding(10)
                        } else if let error = model.paginationError {
                            VStack(spacing: 8) {
                                Text(error).font(.caption).foregroundStyle(.secondary)
                                Button("Tentar novamente") { Task { await model.loadMore() } }
                            }
                            .padding(10)
                        }
                    }
                    .padding(12)
                }
            }
            Divider()
            HStack {
                Text("\(model.total) \(model.total == 1 ? "item salvo" : "itens salvos")")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(onSelect == nil ? "Clique para copiar" : "Clique para colar").foregroundStyle(.tertiary)
                Menu {
                    Button("Configurações…", action: onSettings)
                        .keyboardShortcut(",")
                    Button("Abrir pasta do histórico") { NSWorkspace.shared.open(model.directory) }
                    Divider()
                    Button("Encerrar Clipp") { NSApp.terminate(nil) }
                        .keyboardShortcut("q")
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .accessibilityLabel("Opções do Clipp")
            }
            .font(.caption).padding(.horizontal, 16).padding(.vertical, 12)
        }
        .frame(width: size.width, height: size.height)
        .background(.regularMaterial)
        .onAppear { searchFocused = true }
        .task(id: model.query) {
            if !model.query.isEmpty {
                do { try await Task.sleep(nanoseconds: 200_000_000) } catch { return }
            }
            guard model.isHistoryVisible else { return }
            await model.reload()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            brandIcon
                .foregroundStyle(.tint)
                .frame(width: 38, height: 38)
                .background(.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text("Clipp").font(.system(size: 20, weight: .semibold, design: .rounded))
                HStack(spacing: 5) {
                    Circle().fill(model.isPaused || model.accessDenied || model.isMaintaining || model.store == nil ? Color.orange : Color.green)
                        .frame(width: 5, height: 5)
                    Text(model.store == nil ? "Histórico indisponível" : model.isMaintaining ? "Atualizando histórico…" : model.isPaused ? "Captura pausada" : model.accessDenied ? "Acesso bloqueado" : "Capturando neste Mac")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(action: onSettings) {
                Image(systemName: "gearshape").frame(width: 26, height: 26)
            }
            .buttonStyle(.borderless)
            .help("Configurações")
            .accessibilityLabel("Configurações")
            Button { model.togglePause() } label: {
                Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.borderless)
            .help(model.isPaused ? "Retomar captura" : "Pausar captura")
            .accessibilityLabel(model.isPaused ? "Retomar captura" : "Pausar captura")
            .disabled(model.store == nil)
        }
        .padding(16)
    }

    @ViewBuilder private var brandIcon: some View {
        if let icon = NSImage(named: "MenuBarIconTemplate") {
            Image(nsImage: icon).renderingMode(.template).resizable().scaledToFit()
                .frame(width: 26, height: 26)
                .accessibilityLabel("Clipp")
        } else {
            Image(systemName: "paperclip").font(.system(size: 21, weight: .semibold))
        }
    }

    private func message(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption).foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
    }
}

private struct HistoryRow: View {
    let entry: ClipboardEntry
    let copied: Bool
    let onPaste: (() -> Void)?
    let onCopy: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onPaste ?? onCopy) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    Image(systemName: entry.kind == .image ? "photo" : "text.alignleft")
                    Text(entry.kind == .image ? "Imagem" : "Texto")
                    if let source = entry.sourceApp {
                        Text("·").foregroundStyle(.tertiary)
                        Text(source).lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                        .foregroundStyle(copied ? Color.green : Color.secondary)
                }
                .font(.caption).foregroundStyle(.secondary)
                if let data = entry.thumbnail, let image = NSImage(data: data) {
                    Image(nsImage: image).resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 120, alignment: .leading)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .accessibilityLabel("Miniatura da imagem copiada")
                } else {
                    Text(entry.text ?? "Imagem salva")
                        .font(.system(size: 13)).lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Text(entry.createdAt, format: .dateTime.day().month().year().hour().minute().second())
                    Spacer()
                    Text(copied ? "Copiado!" : ByteCountFormatter.string(fromByteCount: Int64(entry.byteCount), countStyle: .file))
                }
                .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.06)))
        .help(onPaste != nil ? "Colar no aplicativo anterior • Clique direito para apenas copiar ou excluir" : "Copiar item • Clique direito para excluir")
        .contextMenu {
            Button("Copiar", action: onCopy)
            Button("Excluir do histórico", role: .destructive, action: onDelete)
        }
        .accessibilityAction(named: "Excluir do histórico", onDelete)
    }
}
