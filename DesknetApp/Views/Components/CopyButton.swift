import SwiftUI

/// Icon-only copy button. `label` is both the VoiceOver label and the tooltip.
struct CopyButton: View {
    let text: String
    let label: String
    let onCopy: (String) -> Void

    var body: some View {
        Button {
            onCopy(text)
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
