import AppKit

struct InstalledApp: Identifiable, Hashable {
    let url: URL
    let name: String
    let bundleID: String
    let version: String

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

    /// Nome amigável do tipo de arquivo, a partir da pasta onde ele está.
    var category: String {
        if kind == .appBundle { return "Aplicativo" }
        let parent = url.deletingLastPathComponent().path
        let categories: [(suffix: String, label: String)] = [
            ("/Application Support", "Dados do app"),
            ("/Application Scripts", "Scripts"),
            ("/Caches", "Cache"),
            ("/Caches/SentryCrash", "Relatórios de falha"),
            ("/CrashReporter", "Relatórios de falha"),
            ("/DiagnosticReports", "Relatórios de falha"),
            ("/Containers", "Contêiner"),
            ("/Group Containers", "Contêiner compartilhado"),
            ("/Cookies", "Cookies"),
            ("/HTTPStorages", "Dados de rede"),
            ("/WebKit", "Dados de navegação"),
            ("/LaunchAgents", "Serviço em segundo plano"),
            ("/LaunchDaemons", "Serviço do sistema"),
            ("/PrivilegedHelperTools", "Ferramenta auxiliar"),
            ("/Logs", "Logs"),
            ("/Preferences", "Preferências"),
            ("/Preferences/ByHost", "Preferências"),
            ("/Saved Application State", "Estado das janelas"),
            ("/receipts", "Recibo de instalação"),
            ("/Applications", "Atalho"),
        ]
        return categories.last { parent.hasSuffix($0.suffix) }?.label ?? "Arquivo"
    }
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
