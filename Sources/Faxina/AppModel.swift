import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var apps: [InstalledApp] = []
    @Published var search = ""
    @Published var selectedID: URL? {
        didSet { if selectedID != oldValue { scanSelected() } }
    }

    @Published private(set) var items: [FoundItem] = []
    @Published var checked: Set<URL> = []
    @Published private(set) var isScanning = false
    @Published private(set) var isRemoving = false
    @Published var moveToTrash = true
    @Published var resultMessage: String?

    private var signature: Signature?

    var selected: InstalledApp? { apps.first { $0.id == selectedID } }

    var filteredApps: [InstalledApp] {
        search.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var checkedItems: [FoundItem] { items.filter { checked.contains($0.url) } }

    func reloadApps() {
        Task {
            let found = await Task.detached { Scanner.installedApps() }.value
            // Mantém apps abertos manualmente (ex.: arrastados da Lixeira) que não estão em /Applications.
            let extras = apps.filter { app in !found.contains { $0.url == app.url } && FileManager.default.fileExists(atPath: app.url.path) }
            apps = extras + found
        }
    }

    /// Abre um .app de qualquer lugar (arrastado para a janela ou escolhido no seletor).
    func open(_ url: URL) {
        guard let app = Scanner.loadApp(at: url) else {
            resultMessage = "“\(url.lastPathComponent)” não é um aplicativo válido."
            return
        }
        guard !app.isProtected else {
            resultMessage = "“\(app.name)” é um app do sistema e não pode ser removido."
            return
        }
        if !apps.contains(app) { apps.insert(app, at: 0) }
        search = ""
        selectedID = app.id
    }

    private func scanSelected() {
        items = []
        checked = []
        signature = nil
        guard let app = selected else { return }

        isScanning = true
        Task {
            let (signature, found) = await Task.detached {
                let signature = Scanner.signature(for: app)
                return (signature, Scanner.items(for: app, signature: signature))
            }.value
            guard selectedID == app.id else { return }
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

            let freed = outcome.removed.reduce(Int64(0)) { $0 + $1.size }
            var message = "\(outcome.removed.count) \(outcome.removed.count == 1 ? "item removido" : "itens removidos") · \(Format.bytes(freed))"
            message += toTrash ? " movidos para a Lixeira." : " liberados."
            if !outcome.failed.isEmpty {
                message += "\n\nNão foi possível remover:\n" + outcome.failed
                    .map { "• \(Format.path($0.item.url)) — \($0.reason)" }
                    .joined(separator: "\n")
            }
            resultMessage = message

            if outcome.removed.contains(where: { $0.kind == .appBundle }) {
                apps.removeAll { $0.id == app.id }
                selectedID = nil
            } else {
                scanSelected()
            }
        }
    }
}
