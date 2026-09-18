import SwiftUI

struct ItemListView: View {
    @State private var viewModel = ItemListViewModel()
    @State private var showDeleteAlert = false
    @State private var itemToDelete: Item?

    var body: some View {
        ZStack {
            ThemeManager.shared.palette.background.ignoresSafeArea()

            if viewModel.items.isEmpty {
                // Empty state
                VStack(spacing: 16) {
                    Image(systemName: "tray")
                        .font(.system(size: 48))
                        .foregroundStyle(ThemeManager.shared.palette.neutral400)

                    Text("还没有记录任何物品")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(ThemeManager.shared.palette.neutral700)

                    Text("试试对麦克风说「钥匙放在玄关」")
                        .font(.system(size: 14))
                        .foregroundStyle(ThemeManager.shared.palette.neutral500)
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    // Item count
                    Text("共 \(viewModel.items.count) 件物品")
                        .font(.system(size: 14))
                        .foregroundStyle(ThemeManager.shared.palette.neutral600)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)

                    // Grouped list
                    List {
                        ForEach(viewModel.groupedItems, id: \.category) { group in
                            Section {
                                ForEach(group.items) { item in
                                    ItemCardView(item: item) {
                                        await viewModel.refreshItems()
                                    }
                                    .swipeActions(edge: .trailing) {
                                            Button(role: .destructive) {
                                                itemToDelete = item
                                                showDeleteAlert = true
                                            } label: {
                                                Label("删除", systemImage: "trash")
                                            }
                                        }
                                }
                            } header: {
                                HStack {
                                    Text(group.category)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(ThemeManager.shared.palette.neutral600)
                                    Text("\(group.items.count)件")
                                        .font(.system(size: 12))
                                        .foregroundStyle(ThemeManager.shared.palette.neutral400)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable {
                        await viewModel.refreshItems()
                    }
                }
            }

            // Undo snackbar
            VStack {
                Spacer()
                UndoSnackbarView(
                    itemName: viewModel.undoItemName,
                    onUndo: {
                        withAnimation {
                            viewModel.cancelDelete()
                        }
                    },
                    isShowing: viewModel.showUndoSnackbar
                )
            }
            .animation(.spring(response: 0.3), value: viewModel.showUndoSnackbar)
        }
        .navigationTitle("我的物品")
        .navigationBarTitleDisplayMode(.inline)
        .alert("确认删除", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) {
                itemToDelete = nil
            }
            Button("删除", role: .destructive) {
                if let item = itemToDelete {
                    withAnimation {
                        viewModel.scheduleDelete(item)
                    }
                    itemToDelete = nil
                }
            }
        } message: {
            if let item = itemToDelete {
                Text("确定要删除「\(item.name)」的记录吗？")
            }
        }
        .task {
            await viewModel.refreshItems()
        }
    }
}
