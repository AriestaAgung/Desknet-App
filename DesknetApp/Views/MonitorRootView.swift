import SwiftUI

/// Desknet's macOS monitor: header, apps column, request list, details.
struct MonitorRootView: View {
    @Bindable var viewModel: MonitorViewModel

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(countText: viewModel.requestCountText, onClear: viewModel.clear)
            Divider()
            HSplitView {
                AppsSidebarView(
                    rows: viewModel.appRows,
                    selectedID: viewModel.selectedAppRowID,
                    hasRunningApps: viewModel.hasRunningApps,
                    showsHookWarning: !viewModel.isHookInstalled,
                    onSelect: viewModel.select(pid:)
                )
                .frame(minWidth: 200, idealWidth: 240, maxWidth: 320)
                RequestListView(
                    query: $viewModel.query,
                    rows: viewModel.requestRows,
                    selectedID: viewModel.selectedEntryID,
                    onSelect: viewModel.select(entry:)
                )
                .frame(minWidth: 280, idealWidth: 340, maxWidth: 420)
                RequestDetailView(
                    detail: viewModel.detail,
                    emptyText: viewModel.emptyStateText,
                    isExpanded: sectionBinding,
                    onCopy: viewModel.copy
                )
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesknetPalette.windowBackground)
        .preferredColorScheme(.dark)
    }

    private func sectionBinding(_ section: DetailSection) -> Binding<Bool> {
        Binding(
            get: { viewModel.isSectionExpanded(section) },
            set: { viewModel.setSection(section, expanded: $0) }
        )
    }
}
