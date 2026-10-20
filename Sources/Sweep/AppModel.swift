import SwiftUI

struct RemovalResult {
    let app: InstalledApp
    let removedApp: Bool
    let removedCount: Int
    let freed: Int64
    let toTrash: Bool
    let failures: [String]
}

enum SortOrder: String, CaseIterable, Identifiable {
    case largest, smallest, name

    var id: Self { self }

    var title: String {
        switch self {
        case .largest: "Maiores primeiro"
        case .smallest: "Menores primeiro"
        case .name: "Nome"
        }
    }

    var shortTitle: String {
        switch self {
        case .largest: "Maiores"
        case .smallest: "Menores"
        case .name: "A–Z"
        }
    }

    func areInIncreasingOrder(_ a: InstalledApp, _ b: InstalledApp) -> Bool {
        switch self {
        case .largest: a.size > b.size
        case .smallest: a.size < b.size
        case .name: a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var apps: [InstalledApp] = []
    @Published var search = "" {
        didSet { highlighted = 0 }
    }
    /// Linha destacada na lista da tela inicial (mouse ou setas do teclado).
    @Published var highlighted = 0
    @Published private(set) var selected: InstalledApp?

    @Published private(set) var items: [FoundItem] = []
    @Published var checked: Set<URL> = []
    @Published private(set) var isScanning = false
    @Published private(set) var isRemoving = false
    @Published var moveToTrash = true
    @Published var result: RemovalResult?
    @Published var errorMessage: String?

    private var signature: Signature?

    @Published var sortOrder: SortOrder = .largest {
        didSet { highlighted = 0 }
    }

    /// Todos os apps na ordem escolhida; com busca, só os que combinam, os mais relevantes primeiro.
    var visibleApps: [InstalledApp] {
        let sorted = apps.sorted(by: sortOrder.areInIncreasingOrder)
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return sorted }

        // Nome que começa com a busca vem antes de palavra que começa com ela, que vem antes de "contém".
        func rank(_ app: InstalledApp) -> Int? {
            let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
            guard let range = app.name.range(of: query, options: options) else { return nil }
            if range.lowerBound == app.name.startIndex { return 0 }
            return app.name[app.name.index(before: range.lowerBound)] == " " ? 1 : 2
        }
        // Ordenação estável: dentro da mesma relevância, vale a ordem escolhida.
        let ranked = sorted.compactMap { app in rank(app).map { (app, $0) } }
        return ranked.enumerated()
            .sorted { ($0.element.1, $0.offset) < ($1.element.1, $1.offset) }
            .map(\.element.0)
    }

    var highlightedApp: InstalledApp? {
        let apps = visibleApps
        return apps.indices.contains(highlighted) ? apps[highlighted] : nil
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
        // A busca é mantida: limpá-la aqui trocava a lista no meio do fade e, ao voltar, os resultados continuam lá.
        result = nil
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
