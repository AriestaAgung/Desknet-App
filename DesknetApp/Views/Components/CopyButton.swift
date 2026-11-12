import SwiftUI
/// Icon-only copy button. `label` is both the VoiceOver label and the tooltip.
struct CopyButton: View {
    let payload: CopyPayload
    let label: String
    let onCopy: (CopyPayload) -> Void

    init(payload: CopyPayload, label: String, onCopy: @escaping (CopyPayload) -> Void) {
        self.payload = payload
        self.label = label
        self.onCopy = onCopy
    }

    init(text: String, label: String, onCopy: @escaping (CopyPayload) -> Void) {
        self.init(payload: .text(text), label: label, onCopy: onCopy)
    }

    var body: some View {
        Button {
            onCopy(payload)
        } label: {
            Image(systemName: "doc.on.doc")
        }
        .buttonStyle(.plain)
        .foregroundColor(.secondary)
        .accessibilityLabel(label)
        .help(label)
    }
}
#Preview {
    CopyButton(text: "value", label: "Copy Content-Type") { _ in }
        .padding()
        .background(DesknetPalette.windowBackground)
        .preferredColorScheme(.dark)
}
