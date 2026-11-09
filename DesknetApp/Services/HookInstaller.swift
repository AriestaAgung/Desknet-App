import Foundation

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
