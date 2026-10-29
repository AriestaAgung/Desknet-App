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

struct DesknetSectionCard: View {
    let section: DesknetMonitorViewModel.DetailSection
    let entry: NetworkLogEntry
    @Binding var isExpanded: Bool
    @ObservedObject var viewModel: DesknetMonitorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                        .accessibilityHidden(true)
                    Text(section.title)
                        .font(.system(size: 14, weight: .semibold))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                sectionContent
                    .padding(.top, 4)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesknetPalette.windowBackground)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(DesknetPalette.separator, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch section {
        case .requestHeaders, .responseHeaders:
            let headers = viewModel.headers(for: section, entry: entry)
            if headers.isEmpty {
                Text("No headers")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(headers.sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }, id: \.key) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .top) {
                                Text(item.key)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.secondary)
                                Spacer()
                                copyButton(item.value, label: "Copy \(item.key)")
                            }
                            Text(item.value)
                                .font(.system(size: 12, weight: .regular, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(3)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .sectionBox(tint: tint)
                    }
                }
            }
        case .requestBody, .responseBody:
            let text = viewModel.bodyText(for: section, entry: entry)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Spacer()
                    copyButton(text, label: "Copy \(section.title)")
                }
                Text(text)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .sectionBox(tint: tint)
        }
    }

    private func copyButton(_ text: String, label: String) -> some View {
        Button {
            viewModel.copyToPasteboard(text)
        } label: {
            Image(systemName: "doc.on.doc")
        }
        .buttonStyle(.plain)
        .foregroundColor(.secondary)
        .accessibilityLabel(label)
        .help(label)
    }

    private var tint: Color {
        switch section {
        case .requestHeaders: return .green
        case .requestBody: return DesknetPalette.teal
        case .responseHeaders: return .blue
        case .responseBody: return .orange
        }
    }
}

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

enum DesknetPalette {
    static let windowBackground = Color(red: 0.12, green: 0.12, blue: 0.13)
    static let controlBackground = Color.white.opacity(0.08)
    static let separator = Color.white.opacity(0.14)
    static let selectionBorder = Color.white.opacity(0.40)
    static let teal = Color(red: 0.23, green: 0.70, blue: 0.64)
}

private extension View {
    func sectionBox(tint: Color) -> some View {
        background(tint.opacity(0.10))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(tint.opacity(0.22), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
