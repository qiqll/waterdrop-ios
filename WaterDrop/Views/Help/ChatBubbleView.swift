import SwiftUI

struct ChatBubbleView: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.isUser { Spacer(minLength: 60) }

            Text(message.content)
                .font(.system(size: 15))
                .foregroundStyle(message.isUser ? .white : (message.isError ? AppColors.semanticError : AppColors.neutral800))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    message.isUser ? AppColors.primary : (message.isError ? AppColors.semanticErrorBg : AppColors.neutral100)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))

            if !message.isUser { Spacer(minLength: 60) }
        }
    }
}
