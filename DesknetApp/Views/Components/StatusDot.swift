import SwiftUI

/// 8pt filled circle. Decorative: callers put the meaning in their own accessibility label.
struct StatusDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: 12) {
        StatusDot(color: .green)
        StatusDot(color: .red)
        StatusDot(color: Color.secondary.opacity(0.5))
    }
    .padding()
    .background(DesknetPalette.windowBackground)
    .preferredColorScheme(.dark)
}
