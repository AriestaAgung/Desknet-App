import SwiftUI

/// Small secondary title over a selectable value.
struct LabeledValue: View {
    enum Style {
        /// Bold value that fills the row; for metrics, timestamp, error.
        case metric
        /// Monospaced value; for base URL and endpoint.
        case url
    }

    let title: String
    let value: String
    var style: Style = .metric

    var body: some View {
        let content = VStack(alignment: .leading, spacing: style == .metric ? 4 : 2) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            Text(value)
                .font(valueFont)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        if style == .metric {
            content.frame(maxWidth: .infinity, alignment: .leading)
        } else {
            content
        }
    }

    private var valueFont: Font {
        switch style {
        case .metric: return .system(size: 16, weight: .bold)
        case .url: return .system(size: 17, weight: .semibold, design: .monospaced)
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        LabeledValue(title: "Base URL", value: "https://api.example.com", style: .url)
        LabeledValue(title: "Duration", value: "123.400ms")
    }
    .padding()
    .frame(width: 360)
    .background(DesknetPalette.windowBackground)
    .preferredColorScheme(.dark)
}
