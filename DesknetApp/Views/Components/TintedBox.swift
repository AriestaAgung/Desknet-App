import SwiftUI

extension View {
    /// Faint tinted fill with a matching border, for header and body blocks inside a section card.
    func tintedBox(_ tint: Color) -> some View {
        background(tint.opacity(0.10))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(tint.opacity(0.22), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    VStack(spacing: 8) {
        ForEach([Color.green, DesknetPalette.teal, .blue, .orange], id: \.self) { tint in
            Text("{ }").padding(10).frame(maxWidth: .infinity, alignment: .leading).tintedBox(tint)
        }
    }
    .padding()
    .frame(width: 280)
    .background(DesknetPalette.windowBackground)
    .preferredColorScheme(.dark)
}
