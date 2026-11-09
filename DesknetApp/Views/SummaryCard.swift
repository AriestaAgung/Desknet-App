import SwiftUI

/// Method, status, URL parts, metrics, timestamp and error for the selected request.
struct SummaryCard: View {
    let detail: RequestDetail

    var body: some View {
        let accent = detail.isError ? Color.red : Color.green

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                DesknetPill(text: detail.method, textColor: accent, fillColor: accent.opacity(0.15))
                    .font(.system(size: 13, weight: .bold))
                DesknetPill(text: detail.statusText, textColor: .white, fillColor: accent.opacity(0.85))
                    .font(.system(size: 13, weight: .bold))
            }

            VStack(alignment: .leading, spacing: 8) {
                LabeledValue(title: "Base URL", value: detail.baseURL, style: .url)
                LabeledValue(title: "Endpoint", value: detail.endpoint, style: .url)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 14)], alignment: .leading, spacing: 12) {
                ForEach(detail.metrics, id: \.title) { metric in
                    LabeledValue(title: metric.title, value: metric.value)
                }
            }

            LabeledValue(title: "Timestamp", value: detail.timestamp)

            if let error = detail.error {
                LabeledValue(title: "Error", value: error)
            }
        }
        .padding(12)
        .cardStyle()
    }
}
