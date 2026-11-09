import SwiftUI

/// Top bar: app title, request count, Clear.
struct HeaderView: View {
    let countText: String
    let onClear: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 18, weight: .regular))
                .foregroundColor(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Desknet")
                    .font(.system(size: 17, weight: .bold))
                Text("Network Logger")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 16)

            CountBadge(text: countText)

            Button("Clear", action: onClear)
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(minHeight: 82)
    }
}

#Preview {
    HeaderView(countText: "12 requests", onClear: {})
        .frame(width: 800)
        .background(DesknetPalette.windowBackground)
        .preferredColorScheme(.dark)
}
