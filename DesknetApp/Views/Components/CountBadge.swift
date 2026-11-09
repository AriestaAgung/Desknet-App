import SwiftUI

/// Capsule with a short count, e.g. "12 requests".
struct CountBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(DesknetPalette.controlBackground)
            .clipShape(Capsule())
    }
}

#Preview {
    CountBadge(text: "12 requests")
        .padding()
        .background(DesknetPalette.windowBackground)
        .preferredColorScheme(.dark)
}
