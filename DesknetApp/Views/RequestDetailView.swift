import SwiftUI

/// Right column: summary plus the four section cards, or a hint when nothing is selected.
struct RequestDetailView: View {
    let detail: RequestDetail?
    let emptyText: String
    let isExpanded: (DetailSection) -> Binding<Bool>
    let onCopy: (String) -> Void

    var body: some View {
        if let detail {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    SummaryCard(detail: detail)
                    ForEach(detail.sections) { content in
                        SectionCard(content: content, isExpanded: isExpanded(content.section), onCopy: onCopy)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text(emptyText)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(24)
        }
    }
}
