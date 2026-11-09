import SwiftUI

/// Magnifier plus plain text field on a rounded control background. Outer padding is the caller's.
struct SearchField: View {
    let placeholder: String
    @Binding var text: String
    let accessibilityLabel: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .accessibilityLabel(accessibilityLabel)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(DesknetPalette.controlBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    @Previewable @State var text = ""
    SearchField(placeholder: "Search requests...", text: $text, accessibilityLabel: "Search requests")
        .padding()
        .frame(width: 320)
        .background(DesknetPalette.windowBackground)
        .preferredColorScheme(.dark)
}
