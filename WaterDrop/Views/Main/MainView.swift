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
                AppColors.background.ignoresSafeArea()

                VStack {
                    // Top bar
                    HStack {
                        Button(action: { showSettings = true }) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 22))
                                .foregroundStyle(AppColors.neutral700)
                        }

                        Spacer()

                        Text("水滴管家")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppColors.neutral800)

                        Spacer()

                        HStack(spacing: 16) {
                            Button(action: { showItemList = true }) {
                                Image(systemName: "list.bullet")
                                    .font(.system(size: 22))
                                    .foregroundStyle(AppColors.neutral700)
                            }

                            Button(action: { showHelp = true }) {
                                Image(systemName: "questionmark.circle")
                                    .font(.system(size: 22))
                                    .foregroundStyle(AppColors.neutral700)
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
                        case .result:
                            ResultStateView(
                                result: viewModel.processedResult,
                                errorMessage: viewModel.errorMessage
                            )
                            .transition(.opacity)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .background(AppColors.surface)
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
