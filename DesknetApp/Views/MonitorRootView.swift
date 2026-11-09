import SwiftUI

/// Desknet's macOS monitor: header, request list on the left, details on the right.
struct DesknetMonitorRootView: View {
    @ObservedObject var viewModel: DesknetMonitorViewModel
    @ObservedObject var runningApps: RunningAppsMonitor

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            HSplitView {
                RunningAppsView(monitor: runningApps, viewModel: viewModel)
                    .frame(minWidth: 200, idealWidth: 240, maxWidth: 320)
                sidebarView
                    .frame(minWidth: 280, idealWidth: 340, maxWidth: 420)
                detailView
                    .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesknetPalette.windowBackground)
        .preferredColorScheme(.dark)
    }

    private var headerView: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 18, weight: .regular))
                .foregroundColor(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Desknet")
                    .font(.system(size: 17, weight: .bold))
                Text("Network Logger")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 16)

            Text(viewModel.requestCountText)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(DesknetPalette.controlBackground)
                .clipShape(Capsule())

            Button("Clear") {
                viewModel.clear()
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(minHeight: 82)
    }

    private var sidebarView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)
                TextField("Search requests...", text: $viewModel.query)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Search requests")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(DesknetPalette.controlBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 12)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.entries) { entry in
                        Button {
                            viewModel.selectedEntryID = entry.id
                        } label: {
                            DesknetRequestRowView(
                                entry: entry,
                                isSelected: viewModel.selectedEntryID == entry.id,
                                viewModel: viewModel
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(viewModel.selectedEntryID == entry.id ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .background(DesknetPalette.windowBackground)
    }

    @ViewBuilder
    private var detailView: some View {
        if let selectedEntry = viewModel.selectedEntry {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    DesknetSummaryCard(entry: selectedEntry, viewModel: viewModel)
                    ForEach(DesknetMonitorViewModel.DetailSection.allCases, id: \.self) { section in
                        DesknetSectionCard(
                            section: section,
                            entry: selectedEntry,
                            isExpanded: viewModel.sectionBinding(section),
                            viewModel: viewModel
                        )
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text(viewModel.emptyStateText)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(24)
        }
    }
}
