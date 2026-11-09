import SwiftUI

enum DesknetPalette {
    static let windowBackground = Color(red: 0.12, green: 0.12, blue: 0.13)
    static let controlBackground = Color.white.opacity(0.08)
    static let separator = Color.white.opacity(0.14)
    static let selectionBorder = Color.white.opacity(0.40)
    static let teal = Color(red: 0.23, green: 0.70, blue: 0.64)
}

extension View {
    func sectionBox(tint: Color) -> some View {
        background(tint.opacity(0.10))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(tint.opacity(0.22), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
