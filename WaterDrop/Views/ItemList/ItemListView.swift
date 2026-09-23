import SwiftUI

struct ItemListView: View {
    /// F-017 §3.4（D5）：工具栏语音按钮退出本页后回到主页
    @Environment(\.dismiss) private var dismiss
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
                        .font(.wdHero(size: 48))
                        .foregroundStyle(ThemeManager.shared.palette.neutral400)

                    Text("还没有记录任何物品")
                        .font(.wd(.titleLarge, weight: .medium))
                        .foregroundStyle(ThemeManager.shared.palette.neutral700)

                    Text("试试对麦克风说「钥匙放在玄关」")
                        .font(.wd(.bodyMedium))
                        .foregroundStyle(ThemeManager.shared.palette.neutral500)
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    // Item count
                    Text("共 \(viewModel.items.count) 件物品")
                        .font(.wd(.bodyMedium))
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
                                        .font(.wd(.labelLarge, weight: .medium))
                                        .foregroundStyle(ThemeManager.shared.palette.neutral600)
                                    Text("\(group.items.count)件")
                                        .font(.wd(.labelMedium))
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
                    message: "已删除「\(viewModel.undoItemName)」",
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // F-017 §3.4（决策 D5）：语音入口常驻。
                // iOS 这里用导航栏按钮而非浮动按钮 —— 三个列表页的底部都已有内容
                // （群组/提醒是横向操作按钮、物品是撤销提示条），浮动按钮会遮挡。
                // 语义相同：不必退回主页就能开口。
                Button {
                    VoiceEntryBus.shared.postStartListening()
                    dismiss()
                } label: {
                    Image(systemName: "mic")
                }
                .accessibilityLabel("用语音记录或查找物品")
            }
        }

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
