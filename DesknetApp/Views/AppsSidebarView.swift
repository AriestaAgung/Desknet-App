import SwiftUI

/// Left column: apps Xcode is running. Picking one shows only its requests.
struct AppsSidebarView: View {
    let rows: [AppRow]
    let selectedID: String
    let hasRunningApps: Bool
    let showsHookWarning: Bool
    let onSelect: (pid_t?) -> Void
    @State private var showsHookInfo = false

    private static let hookInfo = """
        Without the hook, apps you run from Xcode don't send network logs to Desknet. They still show in this list, but with no requests. Apps that link the Desknet SDK still work.

        To install, choose Hook ▸ Xcode Hook… and click Install, then restart Xcode.

        To uninstall later, for example before deleting Desknet, choose Hook ▸ Xcode Hook… again and click Remove.
        """

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Apps from Xcode")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 8)
                .accessibilityAddTraits(.isHeader)

            if showsHookWarning {
                hookWarning
            }

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(rows) { row in
                        AppRowView(row: row, isSelected: row.id == selectedID) { onSelect(row.pid) }
                    }

                    if !hasRunningApps {
                        Text("Run an app from Xcode to see it here.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 6)
                            .padding(.top, 6)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .background(DesknetPalette.windowBackground)
    }

    private var hookWarning: some View {
        Button {
            showsHookInfo.toggle()
        } label: {
            Label("Xcode hook not installed", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.orange)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Click for details")
        .accessibilityHint("Shows what doesn't work without the hook")
        .popover(isPresented: $showsHookInfo, arrowEdge: .trailing) {
            Text(Self.hookInfo)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 280, alignment: .leading)
                .padding(14)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }
}

private struct AppRowView: View {
    let row: AppRow
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                StatusDot(color: row.isLive ? .green : Color.secondary.opacity(0.5))
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text(row.subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .selectableRowStyle(isSelected: isSelected, idleOpacity: 0)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    AppsSidebarView(
        rows: [
            AppRow(pid: nil, title: "All apps", subtitle: "3 requests", isLive: true),
            AppRow(pid: 101, title: "Ticker", subtitle: "iPhone 17 · 3 requests", isLive: true),
            AppRow(pid: 202, title: "Cleano", subtitle: "My Mac · no logs yet", isLive: false),
        ],
        selectedID: "pid-101", hasRunningApps: true, showsHookWarning: true, onSelect: { _ in }
    )
    .frame(width: 240, height: 400)
    .preferredColorScheme(.dark)
}
