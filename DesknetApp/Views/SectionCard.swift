import SwiftUI

/// Collapsible headers or body card in the detail pane.
struct SectionCard: View {
    let content: RequestDetail.SectionContent
    @Binding var isExpanded: Bool
    let onCopy: (CopyPayload) -> Void
    /// Image opened in the zoomable preview sheet, if any.
    @State private var preview: ImagePreviewItem?

    var body: some View {
        card
            .sheet(item: $preview) { item in
                ImagePreviewSheet(item: item, onCopy: onCopy)
            }
    }

    private var card: some View {
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
            case let .multipart(parts):
                // nil only while collapsed, same as .body.
                multipartBlock(parts ?? [])
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
            if let data {
                if NSImage(data: data) != nil {
                    HStack {
                        Spacer()
                        CopyButton(payload: .image(data), label: "Copy \(content.section.title) Image", onCopy: onCopy)
                    }
                }
                imagePreview(data, label: "\(content.section.title) image")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tintedBox(tint)
    }

    @ViewBuilder
    private func imagePreview(_ data: Data, label: String) -> some View {
        if let image = NSImage(data: data) {
            Button {
                preview = ImagePreviewItem(title: label, image: image, data: data)
            } label: {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: min(image.size.width, 400), maxHeight: min(image.size.height, 400))
            }
            .buttonStyle(.plain)
            .help("Open preview to zoom")
            .accessibilityLabel(label)
            .accessibilityHint("Opens a zoomable preview")
            Text("\(Int(image.size.width)) × \(Int(image.size.height)) px")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        } else {
            Text("Image data could not be decoded (\(data.count) bytes)")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }

    /// One box per form field: name and filename on top, then its text or image.
    @ViewBuilder
    private func multipartBlock(_ parts: [MultipartPart]) -> some View {
        if parts.isEmpty {
            Text("Empty multipart body")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    multipartPart(part)
                }
            }
        }
    }

    private func multipartPart(_ part: MultipartPart) -> some View {
        let name = part.name ?? "Unnamed part"
        let detail = [part.filename, part.contentType].compactMap { $0 }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                switch part.value {
                case let .text(text):
                    CopyButton(text: text, label: "Copy \(name)", onCopy: onCopy)
                case let .image(data) where NSImage(data: data) != nil:
                    CopyButton(payload: .image(data), label: "Copy \(name) Image", onCopy: onCopy)
                default:
                    EmptyView()
                }
            }
            switch part.value {
            case let .text(text):
                Text(text)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .textSelection(.enabled)
            case let .image(data):
                imagePreview(data, label: "\(name) image")
            case let .binary(count):
                Text("Binary data (\(count) bytes)")
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
