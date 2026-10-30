import SwiftUI

/// Left column: apps Xcode is running. Picking one shows only its requests.
struct RunningAppsView: View {
    @ObservedObject var monitor: RunningAppsMonitor
    @ObservedObject var viewModel: DesknetMonitorViewModel
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

            if !monitor.isHookInstalled {
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

            ScrollView {
                LazyVStack(spacing: 6) {
                    row(title: "All apps", subtitle: "\(viewModel.totalCount) requests",
                        pid: nil, isLive: !viewModel.connectedPIDs.isEmpty)

                    ForEach(monitor.apps) { app in
                        row(title: app.name, subtitle: subtitle(for: app),
                            pid: app.pid, isLive: viewModel.connectedPIDs.contains(app.pid))
                    }

                    // Keep a quit app selectable so its logs stay reachable.
                    if let pid = viewModel.selectedPID, !monitor.apps.contains(where: { $0.pid == pid }) {
                        row(title: "Ended app", subtitle: "PID \(pid) · \(viewModel.countsByPID[pid, default: 0]) requests",
                            pid: pid, isLive: false)
                    }

                    if monitor.apps.isEmpty {
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

    private func subtitle(for app: RunningApp) -> String {
        let count = viewModel.countsByPID[app.pid, default: 0]
        let logs = count > 0 || viewModel.connectedPIDs.contains(app.pid) ? "\(count) requests" : "no logs yet"
        return "\(app.platformText) · \(logs)"
    }

    private func row(title: String, subtitle: String, pid: pid_t?, isLive: Bool) -> some View {
        let isSelected = viewModel.selectedPID == pid
        return Button {
            viewModel.selectedPID = pid
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(isLive ? Color.green : Color.secondary.opacity(0.5))
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(DesknetPalette.controlBackground.opacity(isSelected ? 0.96 : 0.0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? DesknetPalette.selectionBorder.opacity(0.55) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(subtitle)\(isLive ? ", sending logs" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
