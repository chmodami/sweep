import SwiftUI
import UniformTypeIdentifiers

@main
struct SweepApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        Window("Sweep", id: "main") {
            RootView()
                .environmentObject(delegate.model)
                .frame(width: 460, height: 620)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    /// Apps arrastados para o ícone do Sweep ou abertos com `open -a Sweep App.app`.
    /// Tratar aqui evita que o SwiftUI abra uma janela nova para cada arquivo.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first, !model.isRemoving else { return }
        model.open(url)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isImporting = false
    @State private var isDropTargeted = false

    var body: some View {
        Group {
            if let result = model.result {
                ResultView(result: result)
            } else if let app = model.selected {
                DetailView(app: app)
            } else {
                HomeView(isDropTargeted: isDropTargeted, chooseInFinder: { isImporting = true })
            }
        }
        .padding(.top, 28) // espaço para os botões da janela
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .animation(.smooth(duration: 0.25), value: model.selected)
        .animation(.smooth(duration: 0.25), value: model.result == nil)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, !model.isRemoving else { return false }
            model.open(url)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.applicationBundle]) { result in
            if case .success(let url) = result { model.open(url) }
        }
        .alert("Sweep", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        // Na abertura a frio o SwiftUI entrega o arquivo aqui, e não ao AppDelegate.
        .onOpenURL { url in if !model.isRemoving { model.open(url) } }
        .onAppear { model.reloadApps() }
    }
}

// MARK: - Início

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    let isDropTargeted: Bool
    let chooseInFinder: () -> Void
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            if model.search.isEmpty {
                dropZone
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
            searchField
            if !model.search.isEmpty {
                results
            }
        }
        .padding(24)
        .animation(.smooth(duration: 0.2), value: model.search.isEmpty)
    }

    private var dropZone: some View {
        Button(action: chooseInFinder) {
            VStack(spacing: 12) {
                Image(systemName: "arrow.down.app")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(isDropTargeted ? Color.accentColor : .secondary)
                Text("Arraste um app aqui")
                    .font(.title3.weight(.medium))
                Text("ou clique para escolher no Finder")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(isDropTargeted ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(isDropTargeted ? Color.accentColor : Color.primary.opacity(0.15),
                                  style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            )
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Buscar app instalado", text: $model.search)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .onSubmit { if let first = model.searchResults.first { model.select(first) } }
            if !model.search.isEmpty {
                Button { model.search = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    private var results: some View {
        Group {
            if model.searchResults.isEmpty {
                Text("Nenhum app encontrado")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.searchResults) { app in
                            AppRow(app: app) { model.select(app) }
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

struct AppRow: View {
    let app: InstalledApp
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(nsImage: app.icon).resizable().frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name)
                    if !app.version.isEmpty {
                        Text(app.version).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isHovered ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Detalhes

struct DetailView: View {
    @EnvironmentObject private var model: AppModel
    let app: InstalledApp
    @State private var isConfirming = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                BackButton()
                Spacer()
            }
            .padding(.horizontal, 16)

            VStack(spacing: 6) {
                Image(nsImage: app.icon).resizable().frame(width: 80, height: 80)
                Text(app.name).font(.title2.weight(.semibold))
                Text(subtitle).font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
            .padding(.bottom, 20)

            if model.isScanning {
                ProgressView().controlSize(.small)
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ItemGroup(items: model.items.filter { $0.kind != .name })
                        let maybe = model.items.filter { $0.kind == .name }
                        if !maybe.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Pode ser deste app — confira antes")
                                    .font(.caption).foregroundStyle(.secondary)
                                    .padding(.leading, 4)
                                ItemGroup(items: maybe)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                }
                .scrollIndicators(.never)
            }

            footer
        }
        .confirmationDialog("Remover \(app.name)?", isPresented: $isConfirming) {
            Button(model.moveToTrash ? "Mover para a Lixeira" : "Apagar permanentemente", role: .destructive) {
                model.removeChecked()
            }
        } message: {
            Text(confirmationMessage)
        }
    }

    private var subtitle: String {
        let size = model.isScanning ? "calculando…" : Format.bytes(model.totalSize)
        return [app.version, size].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var confirmationMessage: String {
        var text = "O app será encerrado se estiver aberto."
        if model.moveToTrash && model.checkedItems.contains(where: \.needsAdmin) {
            text += " Itens protegidos do sistema são apagados permanentemente e pedem sua senha."
        }
        return text
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Button { isConfirming = true } label: {
                HStack(spacing: 8) {
                    if model.isRemoving { ProgressView().controlSize(.small) }
                    Text(model.isRemoving ? "Removendo…" : "Remover · \(Format.bytes(model.checkedSize))")
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .disabled(model.checkedItems.isEmpty || model.isScanning || model.isRemoving)

            Toggle("Mover para a Lixeira", isOn: $model.moveToTrash)
                .toggleStyle(.checkbox)
                .font(.callout)
                .foregroundStyle(.secondary)
                .help("Desmarque para apagar permanentemente")
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 20)
    }
}

struct ItemGroup: View {
    @EnvironmentObject private var model: AppModel
    let items: [FoundItem]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Divider().padding(.leading, 44) }
                ItemRow(item: item, isOn: Binding(
                    get: { model.checked.contains(item.url) },
                    set: { isOn in
                        if isOn { model.checked.insert(item.url) } else { model.checked.remove(item.url) }
                    }
                ))
            }
        }
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.06)))
    }
}

struct ItemRow: View {
    let item: FoundItem
    @Binding var isOn: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.checkbox)
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path)).resizable().frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.category)
                Text(item.url.lastPathComponent)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            .help(item.url.path)
            Spacer(minLength: 8)
            if isHovered {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help("Mostrar no Finder")
            }
            if item.needsAdmin {
                Image(systemName: "lock.fill").font(.caption).foregroundStyle(.tertiary)
                    .help("Pede senha de administrador")
            }
            Text(Format.bytes(item.size))
                .font(.callout).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { isOn.toggle() }
        .onHover { isHovered = $0 }
    }
}

struct BackButton: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Button { model.close() } label: {
            Label("Voltar", systemImage: "chevron.left")
                .font(.callout)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .disabled(model.isRemoving)
        .padding(.vertical, 8)
    }
}

// MARK: - Resultado

struct ResultView: View {
    @EnvironmentObject private var model: AppModel
    let result: RemovalResult

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: result.failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 52))
                .foregroundStyle(result.failures.isEmpty ? .green : .orange)
            Text(result.removedApp ? "\(result.app.name) removido" : "Arquivos removidos")
                .font(.title2.weight(.semibold))
            Text(summary)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if !result.failures.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Não foi possível remover:").font(.callout.weight(.medium))
                        ForEach(result.failures, id: \.self) { failure in
                            Text(failure).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                }
                .frame(maxHeight: 160)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            }

            Spacer()
            Button { model.close() } label: {
                Text("Concluído").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(24)
    }

    private var summary: String {
        let items = "\(result.removedCount) \(result.removedCount == 1 ? "item" : "itens")"
        return result.toTrash
            ? "\(items) · \(Format.bytes(result.freed)) movidos para a Lixeira"
            : "\(items) · \(Format.bytes(result.freed)) liberados"
    }
}
