import SwiftUI

struct MainView: View {
    @State private var viewModel = MainViewModel()
    @State private var showSettings = false
    @State private var showItemList = false
    @State private var showHelp = false
    @State private var permissionDenied = false

    var body: some View {
        NavigationStack {
            ZStack {
                ThemeManager.shared.palette.background.ignoresSafeArea()

                VStack {
                    // Top bar
                    HStack {
                        Button(action: { showSettings = true }) {
                            Image(systemName: "gearshape")
                                .font(.wd(.headlineMedium))
                                .foregroundStyle(ThemeManager.shared.palette.neutral700)
                        }

                        Spacer()

                        Text("水滴管家")
                            .font(.wd(.titleLarge, weight: .semibold))
                            .foregroundStyle(ThemeManager.shared.palette.neutral800)

                        Spacer()

                        HStack(spacing: 16) {
                            Button(action: { showItemList = true }) {
                                Image(systemName: "list.bullet")
                                    .font(.wd(.headlineMedium))
                                    .foregroundStyle(ThemeManager.shared.palette.neutral700)
                            }

                            Button(action: { showHelp = true }) {
                                Image(systemName: "questionmark.circle")
                                    .font(.wd(.headlineMedium))
                                    .foregroundStyle(ThemeManager.shared.palette.neutral700)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    Spacer()

                    // Main content card
                    VStack {
                        switch viewModel.uiState {
                        case .idle:
                            IdleStateView()
                                .transition(.opacity)
                        case .listening:
                            ListeningStateView(partialText: viewModel.speechManager.partialText)
                                .transition(.opacity)
                        case .processing:
                            // F-017 §4.2：松手后的零反馈空窗期，本设计唯一新增的状态
                            ProcessingStateView()
                                .transition(.opacity)
                        case .result:
                            ResultStateView(
                                result: viewModel.processedResult,
                                errorMessage: viewModel.errorMessage
                            )
                            .transition(.opacity)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .background(ThemeManager.shared.palette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
                    .padding(.horizontal, 20)
                    .animation(.easeInOut(duration: 0.2), value: viewModel.uiState)

                    Spacer()

                    // Voice FAB
                    VoiceFabView(
                        onPressStart: {
                            handlePressStart()
                        },
                        onPressRelease: {
                            handlePressRelease()
                        },
                        onSlideToListenMode: {
                            // Already listening, just update UI
                            viewModel.setListening()
                        },
                        onExitListenMode: {
                            handlePressRelease()
                        }
                    )
                    .padding(.bottom, 32)
                }

                // Undo snackbar overlay
                VStack {
                    Spacer()
                    UndoSnackbarView(
                        itemName: viewModel.pendingDeleteItemName,
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
            // F-017 §3.4（决策 D5）：列表页工具栏的语音按钮会 post 一个信号，
            // 退出导航回到主页后由这里接手开始聆听。
            //
            // 用 onChange 而非 onAppear：本页在 push 期间并未消失，从列表页返回时
            // onAppear **不会**再触发，只有观察标志位的变化才收得到。
            .onChange(of: VoiceEntryBus.shared.pendingStartListening) { _, pending in
                guard pending, VoiceEntryBus.shared.consumeStartListening() else { return }
                handlePressStart()
            }
            .navigationDestination(isPresented: $showSettings) {
                SettingsView()
            }
            .navigationDestination(isPresented: $showItemList) {
                ItemListView()
            }
            .navigationDestination(isPresented: $showHelp) {
                HelpView()
            }
            .alert("需要麦克风权限", isPresented: $permissionDenied) {
                Button("去设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("水滴管家需要麦克风和语音识别权限来理解您的语音指令")
            }
        }
        .onDisappear {
            viewModel.flushPendingDelete()
        }
        // F-012 ⑥ (D-10)：进入主界面时上报一次活跃。
        //
        // 放在 `.task` 里（主界面的唯一入口）而不是 `WaterDropApp` 的 scenePhase：
        // 后者每次切回前台都会触发，而服务端落的是累加计数器。`.task` 本身也只在
        // 视图出现时跑一次，两重保险。真正的幂等由 `HeartbeatReporter` 的按天节流保证。
        .task {
            await HeartbeatReporter.reportIfNeeded()
        }
    }

    // MARK: - Voice Handling

    private func handlePressStart() {
        Task {
            let granted = await viewModel.speechManager.requestPermissions()
            if granted {
                viewModel.speechManager.startListening()
                viewModel.setListening()
            } else {
                permissionDenied = true
            }
        }
    }

    private func handlePressRelease() {
        viewModel.speechManager.stopListening()

        // Wait for final result
        Task {
            // Small delay for speech recognition to finalize
            try? await Task.sleep(for: .milliseconds(500))

            let text = viewModel.speechManager.recognizedText.isEmpty
                ? viewModel.speechManager.partialText
                : viewModel.speechManager.recognizedText

            await viewModel.processVoiceInput(text)
        }
    }
}
