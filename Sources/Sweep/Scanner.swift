import Foundation

enum Scanner {
    private static let fm = FileManager.default
    private static var home: URL { fm.homeDirectoryForCurrentUser }

    /// Pastas onde os apps costumam deixar arquivos. Só o primeiro nível de cada uma é examinado.
    private static var searchRoots: [URL] {
        let userLibrary = [
            "Application Scripts", "Application Support", "Application Support/CrashReporter",
            "Caches", "Caches/SentryCrash", "Containers", "Cookies", "Group Containers",
            "HTTPStorages", "LaunchAgents", "Logs", "Logs/DiagnosticReports", "Preferences",
            "Preferences/ByHost", "Saved Application State", "WebKit",
        ].map { home.appendingPathComponent("Library/\($0)") }

        let systemLibrary = [
            "/Library/Application Support", "/Library/Caches", "/Library/LaunchAgents",
            "/Library/LaunchDaemons", "/Library/Logs", "/Library/Logs/DiagnosticReports",
            "/Library/Preferences", "/Library/PrivilegedHelperTools", "/private/var/db/receipts",
        ].map { URL(fileURLWithPath: $0) }

        return userLibrary + [home.appendingPathComponent("Applications")] + systemLibrary
    }

    // MARK: - Apps instalados

    static func installedApps() -> [InstalledApp] {
        let folders = [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
        // Links simbólicos apontam para um app que já está na lista; resolve e remove duplicados.
        var seen: Set<String> = []
        let urls = folders
            .flatMap { appBundles(in: $0, depth: 2) }
            .map { $0.resolvingSymlinksInPath() }
            .filter { seen.insert($0.path).inserted }

        // Medir o tamanho de cada .app é a parte lenta; em paralelo fica bem mais rápido.
        var loaded = [InstalledApp?](repeating: nil, count: urls.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: urls.count) { index in
            let app = loadApp(at: urls[index])
            lock.withLock { loaded[index] = app }
        }
        return loaded
            .compactMap { $0 }
            .filter { !$0.isProtected }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func appBundles(in folder: URL, depth: Int) -> [URL] {
        guard let children = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        return children.flatMap { child -> [URL] in
            if child.pathExtension == "app" { return [child] }
            let isDirectory = (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            return isDirectory && depth > 1 ? appBundles(in: child, depth: depth - 1) : []
        }
    }

    static func loadApp(at url: URL) -> InstalledApp? {
        guard url.pathExtension == "app", let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { return nil }
        return InstalledApp(
            url: url,
            name: url.deletingPathExtension().lastPathComponent,
            bundleID: bundleID,
            version: bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            size: size(of: url)
        )
    }

    // MARK: - Arquivos do app

    static func signature(for app: InstalledApp) -> Signature {
        var identifiers: Set<String> = [app.bundleID]
        var names: Set<String> = [app.name]
        if let info = Bundle(url: app.url)?.infoDictionary {
            for key in ["CFBundleName", "CFBundleDisplayName"] {
                if let name = info[key] as? String { names.insert(name) }
            }
        }

        // Helpers embutidos (outros .app, extensões, XPC) costumam ter bundle ids e pastas próprias.
        // Frameworks são ignorados porque bibliotecas compartilhadas (ex.: Sparkle) gerariam falsos positivos.
        let contents = app.url.appendingPathComponent("Contents")
        if let enumerator = fm.enumerator(at: contents, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for case let url as URL in enumerator {
                switch url.pathExtension {
                case "framework":
                    enumerator.skipDescendants()
                case "app", "appex", "xpc":
                    if let id = Bundle(url: url)?.bundleIdentifier, !id.hasPrefix("com.apple.") { identifiers.insert(id) }
                    if url.pathExtension == "app" { names.insert(url.deletingPathExtension().lastPathComponent) }
                default:
                    continue
                }
            }
        }

        // Nomes curtos ("Arc", "Zed") casariam com coisas demais.
        return Signature(identifiers: identifiers, names: names.filter { $0.count >= 4 })
    }

    static func items(for app: InstalledApp, signature: Signature) -> [FoundItem] {
        var items = [FoundItem(url: app.url, size: size(of: app.url), kind: .appBundle, needsAdmin: needsAdmin(app.url))]
        var seen: Set<String> = [app.url.standardizedFileURL.path]

        for root in searchRoots {
            guard let children = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { continue }
            for child in children {
                let path = child.standardizedFileURL.path
                guard !seen.contains(path), let kind = match(child.lastPathComponent, signature) else { continue }
                seen.insert(path)
                items.append(FoundItem(url: child, size: size(of: child), kind: kind, needsAdmin: needsAdmin(child)))
            }
        }
        return items
    }

    static func match(_ fileName: String, _ signature: Signature) -> FoundItem.Kind? {
        let full = fileName.lowercased()
        let base = (full as NSString).deletingPathExtension

        for id in signature.identifiers.map({ $0.lowercased() }) {
            for candidate in [full, base] {
                // "com.x.app", "com.x.app.helper", "TEAMID.group.com.x.app"
                if candidate == id || candidate.hasPrefix(id + ".") || candidate.contains("." + id) { return .identifier }
            }
        }
        for name in signature.names.map({ $0.lowercased() }) where base.hasPrefix(name) {
            return .name
        }
        return nil
    }

    // MARK: - Utilitários

    static func size(of url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isDirectoryKey, .isSymbolicLinkKey]
        guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return 0 }
        guard values.isDirectory == true, values.isSymbolicLink != true else { return Int64(values.totalFileAllocatedSize ?? 0) }

        var total: Int64 = 0
        let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true })
        while let file = enumerator?.nextObject() as? URL {
            total += Int64((try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    private static func needsAdmin(_ url: URL) -> Bool {
        !fm.isWritableFile(atPath: url.deletingLastPathComponent().path)
    }
}
