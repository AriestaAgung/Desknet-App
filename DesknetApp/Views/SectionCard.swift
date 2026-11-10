import SwiftUI

/// Collapsible headers or body card in the detail pane.
struct SectionCard: View {
    let content: RequestDetail.SectionContent
    @Binding var isExpanded: Bool
    let onCopy: (String) -> Void

    var body: some View {
        DisclosureCard(title: content.section.title, isExpanded: $isExpanded) {
            switch content.content {
            case let .headers(headers):
                headerList(headers)
            case let .body(text):
                // nil only while collapsed; the view model decodes it on expand.
                bodyBlock(text ?? "")
            case let .image(data):
                // nil only while collapsed, same as .body.
                imageBlock(data)
            }
        }
    }

    @ViewBuilder
    private func headerList(_ headers: [RequestDetail.Header]) -> some View {
        if headers.isEmpty {
            Text("No headers")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(headers, id: \.key) { header in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top) {
                            Text(header.key)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                            Spacer()
                            CopyButton(text: header.value, label: "Copy \(header.key)", onCopy: onCopy)
                        }
                        Text(header.value)
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
    }

    private func bodyBlock(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()
                CopyButton(text: text, label: "Copy \(content.section.title)", onCopy: onCopy)
            }
            Text(text)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .tintedBox(tint)
    }

    private func imageBlock(_ data: Data?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let data, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: min(image.size.width, 400), maxHeight: min(image.size.height, 400))
                    .accessibilityLabel("\(content.section.title) image")
                Text("\(Int(image.size.width)) × \(Int(image.size.height)) px")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else if let data {
                Text("Image data could not be decoded (\(data.count) bytes)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tintedBox(tint)
    }

    private var tint: Color {
        switch content.section {
        case .requestHeaders: return .green
        case .requestBody: return DesknetPalette.teal
        case .responseHeaders: return .blue
        case .responseBody: return .orange
        }
    }
}
