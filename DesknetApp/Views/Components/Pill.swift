import SwiftUI

struct DesknetPill: View {
    let text: String
    let textColor: Color
    let fillColor: Color
    private var currentFont = Font.system(size: 12, weight: .semibold)

    init(text: String, textColor: Color, fillColor: Color) {
        self.text = text
        self.textColor = textColor
        self.fillColor = fillColor
    }

    var body: some View {
        Text(text)
            .font(currentFont)
            .foregroundColor(textColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(fillColor)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    func font(_ font: Font) -> DesknetPill {
        var copy = self
        copy.currentFont = font
        return copy
    }
}

#Preview {
    HStack(spacing: 8) {
        DesknetPill(text: "GET", textColor: .green, fillColor: Color.green.opacity(0.15))
        DesknetPill(text: "404 Not Found", textColor: .white, fillColor: Color.red.opacity(0.85))
            .font(.system(size: 13, weight: .bold))
    }
    .padding()
    .background(DesknetPalette.windowBackground)
    .preferredColorScheme(.dark)
}
