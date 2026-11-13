import Foundation

/// Copy for the Xcode hook alert: Install when missing, Remove when present.
struct HookPrompt: Equatable {
    let title: String
    let message: String
    let confirm: String
    let cancel: String
    let isDestructive: Bool

    init(isInstalled: Bool) {
        title = isInstalled ? "Xcode hook is installed" : "Install the Xcode hook?"
        message =
            isInstalled
            ? "Remove it before you delete Desknet. Apps run from Xcode will no longer load the Desknet agent."
            : "Desknet adds one import line to ~/.lldbinit-Xcode and ~/.lldbinit-lldb-rpc-server so apps you run from Xcode send their network logs here. Restart Xcode afterwards."
        confirm = isInstalled ? "Remove" : "Install"
        cancel = isInstalled ? "Cancel" : "Not Now"
        isDestructive = isInstalled
    }
}
