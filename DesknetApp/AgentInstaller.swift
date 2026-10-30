import Foundation

/// Copies the bundled agent and LLDB hook to `~/Library/Application Support/Desknet/` on launch,
/// so the hook always points at this build's agent.
enum DesknetAgentInstaller {
    static let supportURL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Application Support/Desknet")

    static func install() {
        let bundle = Bundle.main
        if let agent = bundle.privateFrameworksURL?.appendingPathComponent("DesknetAgent.framework") {
            replace(supportURL.appendingPathComponent("Agent/macosx/DesknetAgent.framework"), with: agent)
        }
        if let agent = bundle.resourceURL?.appendingPathComponent("Agent/iphonesimulator/DesknetAgent.framework") {
            replace(supportURL.appendingPathComponent("Agent/iphonesimulator/DesknetAgent.framework"), with: agent)
        }
        if let hook = bundle.url(forResource: "desknet_hook", withExtension: "py") {
            replace(supportURL.appendingPathComponent("desknet_hook.py"), with: hook)
        }
    }

    /// Copy to a temp file, then swap it in. Overwriting a loaded binary in place makes the next `LoadImage` fail.
    private static func replace(_ destination: URL, with source: URL) {
        let files = FileManager.default
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).new")
        do {
            guard files.fileExists(atPath: source.path) else { throw CocoaError(.fileNoSuchFile) }
            try files.createDirectory(at: temporary.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? files.removeItem(at: temporary)
            try files.copyItem(at: source, to: temporary)
            if files.fileExists(atPath: destination.path) {
                _ = try files.replaceItemAt(destination, withItemAt: temporary)
            } else {
                try files.moveItem(at: temporary, to: destination)
            }
        } catch {
            DesknetDiagnostics.log("Agent", "install failed path=\(destination.path) error=\(error.localizedDescription)")
        }
    }
}

/// Adds or removes the Desknet block in Xcode's LLDB init files. Only text between the markers is touched;
/// each file is copied to `<file>.desknet-backup` before it changes.
enum DesknetHookInstaller {
    static let begin = "# BEGIN Desknet Xcode Hook"
    static let end = "# END Desknet Xcode Hook"
    static let block = "\(begin)\ncommand script import \"~/Library/Application Support/Desknet/desknet_hook.py\"\n\(end)\n"

    /// Xcode 27.1 reads the first; the second is for other Xcode versions.
    static let files = [".lldbinit-Xcode", ".lldbinit-lldb-rpc-server"].map {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent($0)
    }

    static var isInstalled: Bool {
        files.allSatisfy { (try? String(contentsOf: $0.resolvingSymlinksInPath(), encoding: .utf8))?.contains(begin) == true }
    }

    static func install() throws { try edit(adding(to:)) }
    static func uninstall() throws { try edit(removing(from:)) }

    static func adding(to text: String) -> String {
        guard !text.contains(begin) else { return text }
        return (text.isEmpty || text.hasSuffix("\n") ? text : text + "\n") + block
    }

    static func removing(from text: String) -> String {
        guard let start = text.range(of: begin),
              let stop = text.range(of: end, range: start.upperBound..<text.endIndex) else { return text }
        var upper = stop.upperBound
        if upper < text.endIndex, text[upper] == "\n" { upper = text.index(after: upper) }
        return text.replacingCharacters(in: start.lowerBound..<upper, with: "")
    }

    private static func edit(_ change: (String) -> String) throws {
        let fileManager = FileManager.default
        for file in files {
            let url = file.resolvingSymlinksInPath()
            let exists = fileManager.fileExists(atPath: url.path)
            // Throws on an unreadable file rather than treating it as empty and overwriting it.
            let old = exists ? try String(contentsOf: url, encoding: .utf8) : ""
            let new = change(old)
            guard new != old else { continue }
            if exists {
                let backup = url.appendingPathExtension("desknet-backup")
                try? fileManager.removeItem(at: backup)
                try fileManager.copyItem(at: url, to: backup)
            }
            try new.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
