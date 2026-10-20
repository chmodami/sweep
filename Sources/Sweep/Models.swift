import AppKit

struct InstalledApp: Identifiable, Hashable {
    let url: URL
    let name: String
    let bundleID: String
    let version: String
    let size: Int64

    var id: URL { url }
    var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }

    /// Apps da Apple e o próprio Sweep não podem ser removidos.
    var isProtected: Bool {
        bundleID.hasPrefix("com.apple.") || bundleID == Bundle.main.bundleIdentifier || url.path.hasPrefix("/System/")
    }
}

/// Identificadores e nomes usados para reconhecer os arquivos de um app.
struct Signature {
    var identifiers: Set<String>
    var names: Set<String>
}

struct FoundItem: Identifiable, Hashable {
    enum Kind: Hashable {
        /// O próprio .app.
        case appBundle
        /// Corresponde ao bundle id do app (ou de um helper dele): confiável.
        case identifier
        /// Corresponde apenas ao nome do app: precisa de revisão.
        case name
    }

    let url: URL
    let size: Int64
    let kind: Kind
    let needsAdmin: Bool

    var id: URL { url }
}

enum Format {
    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    static func path(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}

/// Capacidade e espaço livre do disco de inicialização.
struct DiskUsage: Equatable {
    let total: Int64
    let free: Int64

    var used: Int64 { max(total - free, 0) }

    static func current() -> DiskUsage? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let free = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return DiskUsage(total: Int64(total), free: free)
    }
}
