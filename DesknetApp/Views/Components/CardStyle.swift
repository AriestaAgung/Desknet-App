import SwiftUI

extension View {
    /// Full-width card: window background, 1pt separator stroke, 12pt corners.
    func cardStyle() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .background(DesknetPalette.windowBackground)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(DesknetPalette.separator, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    Text("Card content")
        .padding(12)
        .cardStyle()
        .padding()
        .frame(width: 320)
        .background(DesknetPalette.windowBackground)
        .preferredColorScheme(.dark)
}
