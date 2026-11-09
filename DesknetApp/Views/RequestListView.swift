import SwiftUI

struct DesknetRequestRowView: View {
    let entry: NetworkLogEntry
    let isSelected: Bool
    @ObservedObject var viewModel: DesknetMonitorViewModel

    var body: some View {
        let accent = viewModel.isError(entry) ? Color.red : Color.green

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Circle()
                    .fill(accent)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)

                DesknetPill(text: entry.method, textColor: accent, fillColor: accent.opacity(0.15))
                    .font(.system(size: 12, weight: .bold))

                Text(entry.statusCode.map(String.init) ?? "-")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(accent)
            }

            Text(viewModel.endpointTitle(for: entry))
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(1)

            Text("◷ \(viewModel.durationText(for: entry))   \(viewModel.sizeText(for: entry))")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(DesknetPalette.controlBackground.opacity(isSelected ? 0.96 : 0.68))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? DesknetPalette.selectionBorder.opacity(0.55) : Color.clear, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(entry.method) \(viewModel.endpointTitle(for: entry)), \(viewModel.statusText(for: entry)), \(viewModel.durationText(for: entry))"
        )
    }
}
