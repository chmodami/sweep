import AppKit

enum Remover {
    struct Outcome {
        var removed: [FoundItem] = []
        var failed: [(item: FoundItem, reason: String)] = []
    }

    private static let fm = FileManager.default
    private static let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    static func remove(_ items: [FoundItem], app: InstalledApp, signature: Signature, toTrash: Bool) -> Outcome {
        quit(app, identifiers: signature.identifiers)
        if items.contains(where: { $0.kind == .appBundle }) {
            run(lsregister, ["-u", app.url.path])
        }

        var outcome = Outcome()
        var adminQueue: [FoundItem] = []
        for item in items {
            prepare(item)
            if item.needsAdmin { adminQueue.append(item); continue }
            do {
                if toTrash {
                    try fm.trashItem(at: item.url, resultingItemURL: nil)
                } else {
                    try fm.removeItem(at: item.url)
                }
                outcome.removed.append(item)
            } catch {
                // Ex.: .app instalado por .pkg pertence ao root; tenta de novo com senha de administrador.
                adminQueue.append(item)
            }
        }

        if !adminQueue.isEmpty {
            let error = removeAsAdmin(adminQueue)
            for item in adminQueue {
                if exists(item.url) {
                    outcome.failed.append((item, error ?? "não foi possível remover"))
                } else {
                    outcome.removed.append(item)
                }
            }
        }
        return outcome
    }

    /// Encerra o app e seus processos auxiliares antes de apagar os arquivos.
    private static func quit(_ app: InstalledApp, identifiers: Set<String>) {
        let appPath = app.url.standardizedFileURL.path
        let running = NSWorkspace.shared.runningApplications.filter { process in
            if let id = process.bundleIdentifier, identifiers.contains(id) { return true }
            guard let path = process.bundleURL?.standardizedFileURL.path else { return false }
            return path == appPath || path.hasPrefix(appPath + "/")
        }
        running.forEach { $0.terminate() }

        let deadline = Date().addingTimeInterval(5)
        while running.contains(where: { !$0.isTerminated }) && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
        }
        running.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }

        // Processos sem interface (daemons do emulador, por exemplo) não aparecem em runningApplications.
        run("/usr/bin/pkill", ["-f", NSRegularExpression.escapedPattern(for: appPath + "/")])
    }

    /// Descarrega serviços e limpa o cache de preferências antes de remover os arquivos.
    private static func prepare(_ item: FoundItem) {
        let parent = item.url.deletingLastPathComponent().path
        let library = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library").path

        if parent == library + "/Preferences", item.url.pathExtension == "plist" {
            // Sem isso o cfprefsd pode regravar o .plist que acabou de ser apagado.
            run("/usr/bin/defaults", ["delete", item.url.deletingPathExtension().lastPathComponent])
        } else if parent == library + "/LaunchAgents" {
            run("/bin/launchctl", ["bootout", "gui/\(getuid())", item.url.path])
        }
    }

    private static func removeAsAdmin(_ items: [FoundItem]) -> String? {
        let commands = items.flatMap { item -> [String] in
            let path = shellQuote(item.url.path)
            var lines: [String] = []
            if item.url.path.hasPrefix("/Library/LaunchDaemons/") {
                lines.append("launchctl bootout system \(path) 2>/dev/null")
            } else if item.url.path.hasPrefix("/Library/LaunchAgents/") {
                lines.append("launchctl bootout gui/\(getuid()) \(path) 2>/dev/null")
            }
            lines.append("rm -rf \(path)")
            return lines
        }
        let shell = commands.joined(separator: "; ")
        let script = """
        do shell script "\(appleScriptEscape(shell))" with prompt "O Sweep precisa da sua senha para remover arquivos protegidos." with administrator privileges
        """
        let result = run("/usr/bin/osascript", ["-e", script])
        return result.status == 0 ? nil : result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Utilitários

    /// Não segue links simbólicos, ao contrário de fileExists(atPath:).
    private static func exists(_ url: URL) -> Bool {
        (try? fm.attributesOfItem(atPath: url.path)) != nil
    }

    private static func shellQuote(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptEscape(_ string: String) -> String {
        string.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (-1, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
