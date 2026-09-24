import SwiftUI

struct HelpView: View {
    @State private var viewModel = HelpViewModel()
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    /// 对话页的语音输入状态（F-017 §14.4）。
    ///
    /// `@State` + `@Observable` 是 SwiftUI 17 的推荐写法：
    /// 视图持有它，内部属性变化会自动触发重绘。
    @State private var isListening = false
    @State private var speechManager = SpeechRecognitionManager()
    /// 麦克风无权限时的提示（本视图自持，不复用 ViewModel 的状态）
    @State private var micPermissionDenied = false

    var body: some View {
        ZStack {
            ThemeManager.shared.palette.background.ignoresSafeArea()

            VStack(spacing: 0) {
                if viewModel.messages.isEmpty {
                    // Empty state
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "questionmark.bubble")
                            .font(.wdHero(size: 48))
                            .foregroundStyle(ThemeManager.shared.palette.neutral400)

                        Text("有什么可以帮您？")
                            .font(.wd(.headlineMedium, weight: .medium))
                            .foregroundStyle(ThemeManager.shared.palette.neutral700)

                        // 文案按设计稿 §08 改：原来写「您可以问我任何关于水滴管家的
                        // 使用问题」，那把人框在了「产品问题」里，而这一屏现在
                        // 同时承接语音听不懂的通用问题。
                        Text("问产品怎么用，或者随便问点什么")
                            .font(.wd(.bodyMedium))
                            .foregroundStyle(ThemeManager.shared.palette.neutral500)

                        // 可点示例（F-017-screens §08）。
                        // 作用不是「展示能问什么」，而是**降低开口门槛** ——
                        // 面对空白输入框，一个可点的例子比一句「随便问」有用得多。
                        // 三个覆盖三类：通用知识 / 产品操作 / 功能设置。
                        VStack(spacing: 8) {
                            HStack(spacing: 8) {
                                exampleChip("这个季节适合养什么花")
                                exampleChip("怎么共享给家人")
                            }
                            exampleChip("提醒怎么设置")
                        }
                        .padding(.top, 10)
                    }
                    Spacer()
                } else {
                    // Message list
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(viewModel.messages) { message in
                                    ChatBubbleView(message: message)
                                        .id(message.id)
                                }

                                if viewModel.isLoading {
                                    HStack {
                                        ProgressView()
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 10)
                                            .background(ThemeManager.shared.palette.neutral100)
                                            .clipShape(RoundedRectangle(cornerRadius: 16))
                                        Spacer()
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .onChange(of: viewModel.messages.count) { _, _ in
                            if let lastId = viewModel.messages.last?.id {
                                withAnimation {
                                    proxy.scrollTo(lastId, anchor: .bottom)
                                }
                            }
                        }
                    }
                }

                // Input bar
                HStack(spacing: 12) {
                    // F-017 §14.4：语音输入。
                    //
                    // 为什么这一屏需要它：本页的存在理由就是「语音没听懂」，
                    // 用户点进来时嘴还张着，却只能打字 —— 得把刚说过的话再敲一遍。
                    // 交互刻意比主页更简单：只支持按住说话、松手即停。
                    // 这里问的是一句话，不存在主页那种「连续记十几件」的场景。
                    Image(systemName: isListening ? "stop.fill" : "mic.fill")
                        .font(.wd(.titleLarge))
                        .foregroundStyle(isListening
                                         ? ThemeManager.shared.palette.recordingActive
                                         : ThemeManager.shared.palette.neutral600)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle().fill(isListening
                                          ? ThemeManager.shared.palette.recordingActive.opacity(0.15)
                                          : ThemeManager.shared.palette.surfaceVariant)
                        )
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { _ in
                                    // onChanged 会持续回调，只在第一次触发
                                    guard !isListening else { return }
                                    startVoiceInput()
                                }
                                .onEnded { _ in
                                    stopVoiceInput()
                                }
                        )
                        .accessibilityLabel("用语音提问")

                    TextField("输入您的问题...", text: $inputText)
                        .font(.wd(.bodyLarge))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(ThemeManager.shared.palette.surfaceVariant)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .focused($isInputFocused)

                    Button(action: sendQuestion) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.wd(.display))
                            .foregroundStyle(
                                inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? ThemeManager.shared.palette.neutral300
                                    : ThemeManager.shared.palette.primary
                            )
                    }
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(ThemeManager.shared.palette.surface)
            }
        }
        .navigationTitle("帮助中心")
        .navigationBarTitleDisplayMode(.inline)
        .alert("需要麦克风权限", isPresented: $micPermissionDenied) {
            Button("去设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("水滴管家需要麦克风和语音识别权限来听懂您的问题")
        }
        // F-012 ⑥ (D-6)：进入页面时加载历史问答记录（仅当消息列表为空时生效）。
        // 对齐 Android `HelpActivity.onCreate` 里的 `viewModel.loadHistory()`。
        .task {
            await viewModel.loadHistory()
        }
    }

    // MARK: - 语音输入（F-017 §14.4）

    /// 按下麦克风：请求权限并开始聆听。
    private func startVoiceInput() {
        Task {
            let granted = await speechManager.requestPermissions()
            guard granted else {
                micPermissionDenied = true
                return
            }
            isListening = true
            speechManager.startListening()
            // 识别结果实时落进输入框（partial 也写），松开后再由 final 覆盖一次。
            // 这样用户能边看边确认，而不是松手才看到一大段。
            observeSpeechResults()
        }
    }

    /// 松手：停止录音。**不自动发送** —— 识别结果留在输入框里让用户过目。
    ///
    /// 理由与 Android 一致：对话里的问题值得先确认一次，
    /// 说错一个字就发出去，AI 会答歪。
    private func stopVoiceInput() {
        guard isListening else { return }
        speechManager.stopListening()
        isListening = false
    }

    /// 轮询把识别文字同步到输入框。
    ///
    /// 用轮询而不是回调：`SpeechRecognitionManager` 是 `@Observable`，
    /// 结果停在它的 `recognizedText` / `partialText` 属性上，
    /// 而本视图需要的是一个持续同步的动作。识别结束（state == .finished / .error）即退出。
    private func observeSpeechResults() {
        Task { @MainActor in
            while isListening || speechManager.state == .processing {
                let text = speechManager.recognizedText.isEmpty
                    ? speechManager.partialText
                    : speechManager.recognizedText
                if !text.isEmpty {
                    inputText = text
                }
                if case .error = speechManager.state {
                    isListening = false
                    break
                }
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
    }

    /// 空态的可点示例。
    ///
    /// 点了**直接发起提问**，不是只填进输入框 ——
    /// 那等于把「不用想的入口」又变回了「表单」。
    private func exampleChip(_ text: String) -> some View {
        Text(text)
            .font(.wd(.bodySmall))
            .foregroundStyle(ThemeManager.shared.palette.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(ThemeManager.shared.palette.primaryLight)
            .clipShape(Capsule())
            .contentShape(Capsule())
            .onTapGesture {
                Task { await viewModel.sendQuestion(text) }
            }
    }

    private func sendQuestion() {
        let question = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        inputText = ""
        Task {
            await viewModel.sendQuestion(question)
        }
    }
}
