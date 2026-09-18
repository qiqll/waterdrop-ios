import SwiftUI

struct HelpView: View {
    @State private var viewModel = HelpViewModel()
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        ZStack {
            ThemeManager.shared.palette.background.ignoresSafeArea()

            VStack(spacing: 0) {
                if viewModel.messages.isEmpty {
                    // Empty state
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "questionmark.bubble")
                            .font(.system(size: 48))
                            .foregroundStyle(ThemeManager.shared.palette.neutral400)

                        Text("有什么可以帮您？")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(ThemeManager.shared.palette.neutral700)

                        Text("您可以问我任何关于水滴管家的使用问题")
                            .font(.system(size: 14))
                            .foregroundStyle(ThemeManager.shared.palette.neutral500)
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
                    TextField("输入您的问题...", text: $inputText)
                        .font(.system(size: 16))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(ThemeManager.shared.palette.surfaceVariant)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .focused($isInputFocused)

                    Button(action: sendQuestion) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
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
