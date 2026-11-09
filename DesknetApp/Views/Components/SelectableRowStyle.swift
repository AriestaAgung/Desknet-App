import SwiftUI

extension View {
    /// List row background: brighter fill and a border when selected.
    /// `idleOpacity` is the fill when not selected (0 for apps, 0.68 for requests).
    func selectableRowStyle(isSelected: Bool, idleOpacity: Double) -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(DesknetPalette.controlBackground.opacity(isSelected ? 0.96 : idleOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? DesknetPalette.selectionBorder.opacity(0.55) : Color.clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
    }
}

#Preview {
    VStack(spacing: 6) {
        Text("Selected").padding(10).selectableRowStyle(isSelected: true, idleOpacity: 0.68)
        Text("Idle request").padding(10).selectableRowStyle(isSelected: false, idleOpacity: 0.68)
        Text("Idle app").padding(10).selectableRowStyle(isSelected: false, idleOpacity: 0)
    }
    .padding()
    .frame(width: 280)
    .background(DesknetPalette.windowBackground)
    .preferredColorScheme(.dark)
}
