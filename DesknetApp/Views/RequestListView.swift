import SwiftUI

/// Middle column: search plus the request list, newest first.
struct RequestListView: View {
    @Binding var query: String
    let rows: [RequestRow]
    let selectedID: UUID?
    let onSelect: (UUID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            SearchField(placeholder: "Search requests...", text: $query, accessibilityLabel: "Search requests")
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 12)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(rows) { row in
                        Button {
                            onSelect(row.id)
                        } label: {
                            RequestRowView(row: row, isSelected: selectedID == row.id)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selectedID == row.id ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .background(DesknetPalette.windowBackground)
    }
}

struct RequestRowView: View {
    let row: RequestRow
    let isSelected: Bool

    var body: some View {
        let accent = row.isError ? Color.red : Color.green

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                StatusDot(color: accent)

                DesknetPill(text: row.method, textColor: accent, fillColor: accent.opacity(0.15))
                    .font(.system(size: 12, weight: .bold))

                Text(row.statusCodeText)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(accent)
            }

            Text(row.title)
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(1)

            Text(row.metricsText)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .selectableRowStyle(isSelected: isSelected, idleOpacity: 0.68)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.accessibilityLabel)
    }
}
