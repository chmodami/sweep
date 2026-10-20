import SwiftUI

struct RemovalResult {
    let app: InstalledApp
    let removedApp: Bool
    let removedCount: Int
    let freed: Int64
    let toTrash: Bool
    let failures: [String]
}

@MainActor
final class AppModel: ObservableObject {
    @Published var apps: [InstalledApp] = []
    @Published var search = ""
    @Published private(set) var selected: InstalledApp?

    @Published private(set) var items: [FoundItem] = []
    @Published var checked: Set<URL> = []
    @Published private(set) var isScanning = false
    @Published private(set) var isRemoving = false
    @Published var moveToTrash = true
    @Published var result: RemovalResult?
    @Published var errorMessage: String?

    private var signature: Signature?

    var searchResults: [InstalledApp] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? [] : apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var checkedItems: [FoundItem] { items.filter { checked.contains($0.url) } }
    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    var checkedSize: Int64 { checkedItems.reduce(0) { $0 + $1.size } }

    func reloadApps() {
        Task {
            apps = await Task.detached { Scanner.installedApps() }.value
        }
    }

    /// Abre um .app de qualquer lugar (arrastado para a janela ou escolhido no Finder).
    func open(_ url: URL) {
        guard let app = Scanner.loadApp(at: url) else {
            errorMessage = "“\(url.lastPathComponent)” não é um aplicativo válido."
            return
        }
        guard !app.isProtected else {
            errorMessage = "“\(app.name)” é um app do sistema e não pode ser removido."
            return
        }
        select(app)
    }

    func select(_ app: InstalledApp) {
        result = nil
        search = ""
        selected = app
        scan(app)
    }

    /// Volta para a tela inicial.
    func close() {
        selected = nil
        result = nil
        items = []
        checked = []
        signature = nil
    }

    private func scan(_ app: InstalledApp) {
        items = []
        checked = []
        signature = nil
        isScanning = true
        Task {
            let (signature, found) = await Task.detached {
                let signature = Scanner.signature(for: app)
                return (signature, Scanner.items(for: app, signature: signature))
            }.value
            guard selected == app else { return }
            self.signature = signature
            items = found
            // Correspondências só por nome começam desmarcadas: o usuário confirma.
            checked = Set(found.filter { $0.kind != .name }.map(\.url))
            isScanning = false
        }
    }

    func removeChecked() {
        guard let app = selected, let signature else { return }
        let targets = checkedItems
        let toTrash = moveToTrash
        isRemoving = true

        Task {
            let outcome = await Task.detached {
                Remover.remove(targets, app: app, signature: signature, toTrash: toTrash)
            }.value
            isRemoving = false
            result = RemovalResult(
                app: app,
                removedApp: outcome.removed.contains { $0.kind == .appBundle },
                removedCount: outcome.removed.count,
                freed: outcome.removed.reduce(0) { $0 + $1.size },
                toTrash: toTrash,
                failures: outcome.failed.map { "\(Format.path($0.item.url)) — \($0.reason)" }
            )
            reloadApps()
        }
    }
}
