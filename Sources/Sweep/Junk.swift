import AppKit
import SwiftUI

/// Um grupo de lixo encontrado: uma categoria (caches, logs…) ou os restos de um app desinstalado.
struct JunkGroup: Identifiable, Hashable {
    enum Cleanup: Hashable {
        /// Apagado direto: o sistema ou o app recria quando precisar.
        case delete
        /// Vai para a Lixeira: pode ser algo que o usuário ainda quer.
        case trash
        /// Lixeira sem Acesso Total ao Disco: só o Finder consegue esvaziar.
        case emptyTrash
    }

    let id: String
    let title: String
    let detail: String
    let symbol: String
    let color: Color
    let urls: [URL]
    /// Tamanho de cada URL, na mesma ordem; usado para somar o que foi liberado de fato.
    let sizes: [Int64]
    let cleanup: Cleanup
    /// Pode ser falso positivo: começa desmarcado e aparece na seção "revise antes".
    let needsReview: Bool
    /// Falso quando não deu para medir (Lixeira sem Acesso Total ao Disco).
    let isMeasured: Bool

    var size: Int64 { sizes.reduce(0, +) }
    var isCheckedByDefault: Bool { !needsReview && id != "trash" }
}

enum JunkScanner {
    private static let fm = FileManager.default
    private static var home: URL { fm.homeDirectoryForCurrentUser }
    private static var library: URL { home.appendingPathComponent("Library") }

    static func scan() -> [JunkGroup] {
        let running = runningIdentifiers()
        let orphans = orphans(skipping: running)
        let orphanURLs = Set(orphans.flatMap(\.urls))
        let safe = [caches(skipping: running, excluding: orphanURLs), logs(), developerCaches(), trash()]
        return safe.compactMap { $0 } + orphans + [installers()].compactMap { $0 }
    }

    // MARK: - Limpeza segura

    private static func caches(skipping running: Set<String>, excluding orphanURLs: Set<URL>) -> JunkGroup? {
        let ownID = Bundle.main.bundleIdentifier?.lowercased()
        let urls = children(of: library.appendingPathComponent("Caches")).filter { url in
            let name = url.lastPathComponent.lowercased()
            if name.hasPrefix("com.apple.") || name == ownID || orphanURLs.contains(url) { return false }
            // Apagar o cache de um app aberto pode deixá-lo instável.
            return !running.contains { name == $0 || name.hasPrefix($0 + ".") }
        }
        return make(id: "caches", title: String(localized: "App caches"),
                    detail: String(localized: "Rebuilt automatically · open apps are skipped"),
                    symbol: "shippingbox.fill", color: .orange, urls: urls, cleanup: .delete)
    }

    private static func logs() -> JunkGroup? {
        let logs = library.appendingPathComponent("Logs")
        let urls = children(of: logs).filter { $0.lastPathComponent != "DiagnosticReports" }
            + children(of: logs.appendingPathComponent("DiagnosticReports"))
        return make(id: "logs", title: String(localized: "Logs and crash reports"),
                    detail: String(localized: "Records apps write while they run"),
                    symbol: "doc.text.fill", color: .gray, urls: urls, cleanup: .delete)
    }

    private static func developerCaches() -> JunkGroup? {
        let paths = [
            "Library/Developer/Xcode/DerivedData",
            "Library/Developer/Xcode/iOS DeviceSupport",
            "Library/Developer/Xcode/watchOS DeviceSupport",
            "Library/Developer/CoreSimulator/Caches",
            ".npm/_cacache",
            ".gradle/caches",
        ]
        let urls = paths.map { home.appendingPathComponent($0) }.filter { fm.fileExists(atPath: $0.path) }
        return make(id: "developer", title: String(localized: "Developer caches"),
                    detail: String(localized: "Xcode, simulators, npm and Gradle"),
                    symbol: "hammer.fill", color: .blue, urls: urls, cleanup: .delete)
    }

    private static func trash() -> JunkGroup? {
        let trash = home.appendingPathComponent(".Trash")
        if let items = (try? fm.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil))?
            .filter({ $0.lastPathComponent != ".DS_Store" }) {
            return make(id: "trash", title: String(localized: "Trash"),
                        detail: String(localized: "Items you already deleted · can’t be undone"),
                        symbol: "trash.fill", color: .red, urls: items, cleanup: .delete)
        }
        // Sem Acesso Total ao Disco não dá para ler a Lixeira; o Finder ainda consegue esvaziá-la.
        return JunkGroup(id: "trash", title: String(localized: "Trash"),
                         detail: String(localized: "Size unavailable without Full Disk Access"),
                         symbol: "trash.fill", color: .red, urls: [trash], sizes: [0],
                         cleanup: .emptyTrash, needsReview: false, isMeasured: false)
    }

    // MARK: - Revise antes

    /// Pastas e arquivos com o bundle id de um app que não está mais instalado.
    private static func orphans(skipping running: Set<String>) -> [JunkGroup] {
        var owned = running
        if let ownID = Bundle.main.bundleIdentifier { owned.insert(ownID.lowercased()) }
        for app in Scanner.installedApps() {
            owned.formUnion(Scanner.signature(for: app).identifiers.map { $0.lowercased() })
        }
        // Se o fabricante tem outro app instalado, o item provavelmente é dele (atualizadores, helpers…).
        let vendors = Set(owned.compactMap(vendor))

        let roots = [
            "Application Scripts", "Application Support", "Caches", "Containers", "Cookies", "Group Containers",
            "HTTPStorages", "LaunchAgents", "Preferences", "Saved Application State", "WebKit",
        ]
        var found: [String: [URL]] = [:]
        var displayNames: [String: String] = [:]
        for root in roots {
            for child in children(of: library.appendingPathComponent(root)) {
                guard let display = bundleID(fromFileName: child.lastPathComponent) else { continue }
                let id = display.lowercased()
                if let vendor = vendor(id), vendors.contains(vendor) || ignoredVendors.contains(vendor) { continue }
                if owned.contains(where: { id == $0 || id.hasPrefix($0 + ".") || $0.hasPrefix(id + ".") }) { continue }
                found[id, default: []].append(child)
                displayNames[id] = displayNames[id] ?? display
            }
        }

        // Helpers ("com.x.app.shipit", "com.x.app.network-extension") entram no grupo do app principal.
        for id in found.keys.sorted(by: { $0.count > $1.count }) {
            guard let parent = found.keys.filter({ id.hasPrefix($0 + ".") }).min(by: { $0.count < $1.count }),
                  let urls = found.removeValue(forKey: id) else { continue }
            found[parent, default: []].append(contentsOf: urls)
        }

        return found.sorted { $0.key < $1.key }.compactMap { id, urls in
            make(id: "orphan:\(id)", title: displayNames[id] ?? id,
                 detail: urls.count == 1
                    ? String(localized: "1 place · app no longer installed")
                    : String(localized: "\(urls.count) places · app no longer installed"),
                 symbol: "questionmark.folder.fill", color: .purple, urls: urls, cleanup: .trash, needsReview: true)
        }
    }

    private static func installers() -> JunkGroup? {
        let urls = children(of: home.appendingPathComponent("Downloads"))
            .filter { ["dmg", "pkg", "mpkg", "xip"].contains($0.pathExtension.lowercased()) }
        return make(id: "installers", title: String(localized: "Installers in Downloads"),
                    detail: urls.count == 1
                        ? String(localized: "1 file · .dmg and .pkg")
                        : String(localized: "\(urls.count) files · .dmg and .pkg"),
                    symbol: "arrow.down.circle.fill", color: .teal, urls: urls, cleanup: .trash, needsReview: true)
    }

    // MARK: - Utilitários

    /// Componentes do sistema e bibliotecas embutidas em vários apps: não são restos de um app específico.
    private static let ignoredVendors: Set<String> = [
        "is.workflow", "org.cups", "org.webkit", "org.swift", "org.python", "com.hackemist",
        "com.launchdarkly", "com.segment", "com.install4j", "ort.pyke", "com.crashlytics", "io.sentry",
    ]

    /// Extrai o bundle id (com a grafia original) de nomes como "com.x.app", "com.x.app.plist" ou "TEAMID.group.com.x.app".
    static func bundleID(fromFileName name: String) -> String? {
        var parts = name.split(separator: ".").map(String.init)
        if let team = parts.first, team.count == 10, team == team.uppercased(), team.allSatisfy({ $0.isLetter || $0.isNumber }) {
            parts.removeFirst()
        }
        if parts.first == "group" { parts.removeFirst() }
        if let last = parts.last, ["plist", "savedState", "binarycookies"].contains(last) { parts.removeLast() }
        guard parts.count >= 3, let tld = parts.first, (2...5).contains(tld.count), tld.allSatisfy(\.isLetter) else { return nil }
        let id = parts.joined(separator: ".")
        return id.lowercased().contains("apple") ? nil : id
    }

    private static func vendor(_ id: String) -> String? {
        let parts = id.split(separator: ".")
        return parts.count >= 2 ? parts.prefix(2).joined(separator: ".") : nil
    }

    private static func runningIdentifiers() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier?.lowercased() })
    }

    private static func children(of folder: URL) -> [URL] {
        ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent != ".DS_Store" }
    }

    private static func make(
        id: String, title: String, detail: String, symbol: String, color: Color,
        urls: [URL], cleanup: JunkGroup.Cleanup, needsReview: Bool = false
    ) -> JunkGroup? {
        guard !urls.isEmpty else { return nil }
        var sizes = [Int64](repeating: 0, count: urls.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: urls.count) { index in
            let size = Scanner.size(of: urls[index])
            lock.withLock { sizes[index] = size }
        }
        guard sizes.reduce(0, +) > 0 else { return nil }
        return JunkGroup(id: id, title: title, detail: detail, symbol: symbol, color: color, urls: urls,
                         sizes: sizes, cleanup: cleanup, needsReview: needsReview, isMeasured: true)
    }
}

enum JunkCleaner {
    struct Outcome {
        var removedCount = 0
        var freed: Int64 = 0
        var failures: [String] = []
    }

    static func clean(_ groups: [JunkGroup]) -> Outcome {
        let fm = FileManager.default
        var outcome = Outcome()
        for group in groups {
            var failed = 0
            for (url, size) in zip(group.urls, group.sizes) {
                do {
                    switch group.cleanup {
                    case .delete:
                        try fm.removeItem(at: url)
                    case .trash:
                        Remover.prepare(url)
                        try fm.trashItem(at: url, resultingItemURL: nil)
                    case .emptyTrash:
                        let result = Remover.run("/usr/bin/osascript", ["-e", "tell application \"Finder\" to empty trash"])
                        if result.status != 0 { throw CocoaError(.fileWriteNoPermission) }
                    }
                    outcome.removedCount += 1
                    outcome.freed += size
                } catch {
                    failed += 1
                }
            }
            if failed > 0 {
                outcome.failures.append(String(localized: "\(group.title) — \(failed) items couldn’t be removed"))
            }
        }
        return outcome
    }
}
