// Spike agent: compiled into the Desknet_iOS module, so `Desknet` is the iOS SDK type.
// ponytail: no SDK-marker gate yet (spike 0.4 measures what happens without it); real one is task 1.3.
import Foundation

@_cdecl("desknet_agent_start")
func desknetAgentStart() {
    guard Bundle.main.bundlePath.contains("/Containers/Bundle/Application/") else { return }
    Desknet.shared.start()
}
