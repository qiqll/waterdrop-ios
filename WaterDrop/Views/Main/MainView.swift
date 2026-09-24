import SwiftUI

struct MainView: View {
    @State private var viewModel = MainViewModel()
    @State private var showSettings = false
    @State private var showItemList = false
    @State private var showHelp = false
    @State private var permissionDenied = false

    // F-018 §1：主页新手引导。
    //
    // 首次进入主页时展示四步蒙版引导（按住说 / 点按说 / 物品列表 / 问一句）。
    // 只做主页 —— 四步指向的都是主页控件；跨页面引导需先跳转再定位，
    // 复杂度高一个量级，本期不做。
    @State private var showCoachMark = false
    /// 引导锚点的 frame。在 ZStack 这一层收集 —— 见 CoachMarkOverlay 里
    /// 关于「preference 只能子传父」的注释。
    @State private var coachAnchors: [String: CGRect] = [:]

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
                            .coachAnchor("help")
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

                    // 按钮上方的提示（F-017-screens §01）。
                    //
                    // 放在按钮**正上方**而不是下方：手指按在球上时不会遮挡它，
                    // 而下方紧贴屏幕边缘、容易被 Home Indicator 挤到。
                    // 引导展示时隐藏 —— 引导第 1 步讲的就是同一件事，重复且挤占空间。
                    if !fabTip.isEmpty && !showCoachMark {
                        Text(fabTip)
                            .font(.wd(.bodyMedium))
                            .foregroundStyle(ThemeManager.shared.palette.neutral600)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 10)
                            .transition(.opacity)
                    }

                    // Voice FAB
                    VoiceFabView(
                        onPressStart: {
                            handlePressStart()
                        },
                        onPressRelease: {
                            handlePressRelease()
                        },
                        onEnterListenMode: {
                            // 连续聆听：录音已在跑，这里只切界面状态
                            viewModel.setListening()
                        },
                        onExitListenMode: {
                            handlePressRelease()
                        }
                    )
                    .coachAnchor("voiceFab")
                    .padding(.bottom, 32)
                }

                // Undo snackbar overlay
                //
                // 同一位置承载两种撤销：删除的、和刚记下那条的。
                // **两者互斥** —— 删除条优先（它是用户刚点的动作，更即时），
                // 否则两条会叠在一起，用户不知道该点哪个。
                VStack {
                    Spacer()
                    if viewModel.showUndoSnackbar {
                        UndoSnackbarView(
                            message: "已删除「\(viewModel.pendingDeleteItemName)」",
                            onUndo: {
                                withAnimation {
                                    viewModel.cancelDelete()
                                }
                            },
                            isShowing: true
                        )
                    } else if let recordedName = viewModel.lastRecordedItemId != nil ? viewModel.lastRecordedItemName : nil {
                        UndoSnackbarView(
                            message: "已记下「\(recordedName)」",
                            onUndo: {
                                viewModel.undoLastRecord()
                            },
                            isShowing: true
                        )
                    }
                }
                .animation(.spring(response: 0.3), value: viewModel.showUndoSnackbar)

                // F-018 §1：新手引导蒙版（放最上层，盖住所有控件）
                if showCoachMark {
                    CoachMarkOverlay(
                        steps: coachSteps,
                        anchors: coachAnchors,
                        onFinish: {
                            CoachMarkPrefs.markSeen()
                            withAnimation(.easeOut(duration: 0.2)) { showCoachMark = false }
                        },
                        onSkip: {
                            // 跳过**不写标记** —— 下次进入还会展示（他们确实还没学会怎么用）
                            withAnimation(.easeOut(duration: 0.2)) { showCoachMark = false }
                        }
                    )
                    .transition(.opacity)
                }
            }
            .onPreferenceChange(CoachAnchorKey.self) { coachAnchors = $0 }
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
        // F-018 §1：首次进入主页时展示引导。
        //
        // 用延迟而不是立即 —— 引导要读锚点 frame（`.coachAnchor` 注册的），
        // 而 frame 要等第一帧布局完成才有值；立刻展示会拿到全 0 的 rect，
        // 洞挖在左上角。（Android 侧踩过同一个坑，那边用 addOnPreDrawListener 解决。）
        .onAppear {
            guard !CoachMarkPrefs.hasSeen, !showCoachMark else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                withAnimation(.easeIn(duration: 0.22)) { showCoachMark = true }
            }
        }
    }

    // MARK: - 按钮提示（F-017-screens §01）

    /// 按钮上方的提示。按界面状态切换。
    ///
    /// 连续模式与单次模式的结束方式不同，提示必须跟着变 ——
    /// 否则用户在连续模式里会一直按着不放。
    private var fabTip: String {
        switch viewModel.uiState {
        case .idle:
            return "按住说一句短的，松手就好"
        case .listening:
            // 连续聆听：录音已在跑，结束方式是「再点一下」
            return viewModel.isInListenMode ? "说完再点一下结束" : "正在听…松手就结束"
        case .processing:
            return "正在整理你说的话"
        case .result:
            // 结果页已有撤回条，再多一句会抢注意力
            return ""
        }
    }

    // MARK: - 新手引导（F-018 §1）

    private var coachSteps: [CoachMarkOverlay.Step] {
        [
            .init(
                anchor: "voiceFab",
                title: "按住说一句",
                body: "按住这个圆按钮，说完松手就好。比如「钥匙放在玄关了」。",
                placement: .above
            ),
            .init(
                anchor: "voiceFab",
                title: "点一下，连着说",
                body: "要一次记好几样？点一下开始，说完再点一下结束 —— 中间手可以放下。",
                placement: .above
            ),
            .init(
                anchor: "itemList",
                title: "记下的都在这儿",
                body: "说过的物品会自动分成类，在这里能翻看、修改、删除。",
                placement: .below
            ),
            .init(
                anchor: "help",
                title: "忘了就问一声",
                body: "想不起来放哪了，直接问。也可以问点别的。",
                placement: .below,
                skippable: false
            ),
        ]
    }

    // MARK: - Voice Handling

    /// 按下按钮 —— **两种按法共用**的入口。
    ///
    /// 按下时还不知道是单击还是按住（要靠按压时长判定），
    /// 所以先按「单次」处理；若是单击，`VoiceFabView` 随后会调
    /// `onEnterListenMode` 把它升级为连续模式。
    private func handlePressStart() {
        Task {
            let granted = await viewModel.speechManager.requestPermissions()
            if granted {
                viewModel.speechManager.startListening()
                viewModel.setListeningOnce()
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
