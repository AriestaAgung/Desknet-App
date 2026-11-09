import SwiftUI

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
                        .tintedBox(tint)
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
            .tintedBox(tint)
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
