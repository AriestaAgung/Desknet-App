import SwiftUI

/// Card with a chevron header that shows or hides its content.
struct DisclosureCard<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                        .accessibilityHidden(true)
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                content()
                    .padding(.top, 4)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
        .cardStyle()
    }
}

#Preview {
    @Previewable @State var open = true
    @Previewable @State var closed = false
    VStack(spacing: 12) {
        DisclosureCard(title: "Response Body", isExpanded: $open) { Text("{ \"ok\": true }") }
        DisclosureCard(title: "Request Headers", isExpanded: $closed) { Text("hidden") }
    }
    .padding()
    .frame(width: 360)
    .background(DesknetPalette.windowBackground)
    .preferredColorScheme(.dark)
}
