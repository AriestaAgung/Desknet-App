import SwiftUI

struct DesknetSummaryCard: View {
    let entry: NetworkLogEntry
    @ObservedObject var viewModel: DesknetMonitorViewModel

    var body: some View {
        let methodAccent = viewModel.isError(entry) ? Color.red : Color.green

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                DesknetPill(text: entry.method, textColor: methodAccent, fillColor: methodAccent.opacity(0.15))
                    .font(.system(size: 13, weight: .bold))
                DesknetPill(
                    text: viewModel.statusText(for: entry),
                    textColor: .white,
                    fillColor: viewModel.isError(entry) ? .red.opacity(0.85) : .green.opacity(0.85)
                )
                .font(.system(size: 13, weight: .bold))
            }

            VStack(alignment: .leading, spacing: 8) {
                makeURLLine(title: "Base URL", value: viewModel.baseURLText(for: entry))
                makeURLLine(title: "Endpoint", value: viewModel.endpointDetailText(for: entry))
            }

            let columns = [GridItem(.adaptive(minimum: 180), spacing: 14)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(viewModel.metricRows(for: entry), id: \.0) { metric in
                    labeledValue(title: metric.0, value: metric.1)
                }
            }

            labeledValue(title: "Timestamp", value: viewModel.timestampText(for: entry))

            if let error = entry.errorDescription {
                labeledValue(title: "Error", value: error)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesknetPalette.windowBackground)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(DesknetPalette.separator, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func labeledValue(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func makeURLLine(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .monospaced))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}
