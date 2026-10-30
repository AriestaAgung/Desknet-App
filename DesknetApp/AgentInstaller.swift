import Foundation

/// Copies the bundled agent and LLDB hook to `~/Library/Application Support/Desknet/` on launch,
/// so the hook always points at this build's agent.
/// ponytail: the `~/.lldbinit-Xcode` block is installed by hand for now (see README); add a Settings Install/Remove button.
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
