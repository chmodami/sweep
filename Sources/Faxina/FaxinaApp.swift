import SwiftUI
import UniformTypeIdentifiers

@main
struct FaxinaApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 860, minHeight: 540)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isImporting = false
    @State private var isDropTargeted = false

    var body: some View {
        NavigationSplitView {
            List(model.filteredApps, selection: $model.selectedID) { app in
                HStack(spacing: 8) {
                    Image(nsImage: app.icon).resizable().frame(width: 22, height: 22)
                    Text(app.name).lineLimit(1)
                }
                .tag(app.id)
            }
            .searchable(text: $model.search, placement: .sidebar, prompt: "Buscar app")
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
            .toolbar {
                ToolbarItemGroup {
                    Button { isImporting = true } label: { Label("Escolher app…", systemImage: "plus") }
                        .help("Escolher um .app em qualquer pasta, inclusive na Lixeira")
                    Button { model.reloadApps() } label: { Label("Atualizar", systemImage: "arrow.clockwise") }
                }
            }
        } detail: {
            DetailView()
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            model.open(url)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.applicationBundle]) { result in
            if case .success(let url) = result { model.open(url) }
        }
        .alert("Faxina", isPresented: Binding(get: { model.resultMessage != nil }, set: { if !$0 { model.resultMessage = nil } })) {
            Button("OK") { model.resultMessage = nil }
        } message: {
            Text(model.resultMessage ?? "")
        }
        .onAppear { model.reloadApps() }
    }
}

struct DetailView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isConfirming = false

    var body: some View {
        if let app = model.selected {
            VStack(spacing: 0) {
                header(app)
                Divider()
                if model.isScanning {
                    ProgressView("Procurando arquivos de \(app.name)…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    itemList
                }
                Divider()
                footer(app)
            }
            .confirmationDialog("Remover \(app.name)?", isPresented: $isConfirming) {
                Button(model.moveToTrash ? "Mover para a Lixeira" : "Apagar permanentemente", role: .destructive) {
                    model.removeChecked()
                }
            } message: {
                Text(confirmationMessage)
            }
        } else {
            ContentUnavailableView(
                "Selecione um app",
                systemImage: "sparkles",
                description: Text("Escolha um app na lista ou arraste um .app (mesmo da Lixeira) para esta janela.")
            )
        }
    }

    private var confirmationMessage: String {
        let items = model.checkedItems
        let total = Format.bytes(items.reduce(0) { $0 + $1.size })
        var text = "\(items.count) itens (\(total)) serão removidos. O app será encerrado se estiver aberto."
        if model.moveToTrash && items.contains(where: \.needsAdmin) {
            text += "\n\nItens protegidos do sistema são apagados permanentemente e exigem sua senha."
        }
        return text
    }

    private func header(_ app: InstalledApp) -> some View {
        HStack(spacing: 14) {
            Image(nsImage: app.icon).resizable().frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(app.name).font(.title2.bold())
                Text([app.bundleID, app.version].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Spacer()
        }
        .padding(16)
    }

    private var itemList: some View {
        List {
            section("Aplicativo", items: model.items.filter { $0.kind == .appBundle })
            section("Arquivos do app", items: model.items.filter { $0.kind == .identifier })
            section("Possíveis correspondências — confira antes de marcar", items: model.items.filter { $0.kind == .name })
        }
    }

    @ViewBuilder
    private func section(_ title: String, items: [FoundItem]) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { item in
                    ItemRow(item: item, isOn: Binding(
                        get: { model.checked.contains(item.url) },
                        set: { isOn in
                            if isOn { model.checked.insert(item.url) } else { model.checked.remove(item.url) }
                        }
                    ))
                }
            }
        }
    }

    private func footer(_ app: InstalledApp) -> some View {
        HStack(spacing: 12) {
            Toggle("Mover para a Lixeira", isOn: $model.moveToTrash)
                .help("Desmarque para apagar permanentemente")
            Spacer()
            let items = model.checkedItems
            Text("\(items.count) selecionados · \(Format.bytes(items.reduce(0) { $0 + $1.size }))")
                .foregroundStyle(.secondary).monospacedDigit()
            if model.isRemoving { ProgressView().controlSize(.small) }
            Button("Remover", role: .destructive) { isConfirming = true }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(items.isEmpty || model.isScanning || model.isRemoving)
        }
        .padding(12)
    }
}

struct ItemRow: View {
    let item: FoundItem
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.checkbox)
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path)).resizable().frame(width: 18, height: 18)
            Text(Format.path(item.url))
                .lineLimit(1).truncationMode(.middle)
                .help(item.url.path)
            if item.needsAdmin {
                Image(systemName: "lock.fill").foregroundStyle(.secondary).help("Exige senha de administrador")
            }
            Spacer()
            Text(Format.bytes(item.size)).foregroundStyle(.secondary).monospacedDigit()
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Mostrar no Finder")
        }
    }
}
