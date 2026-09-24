import SwiftUI

/// 待机态（F-017-screens §01）。
///
/// ## 本次改动
///
/// 去掉水滴图标，改为「主文案 + 引导句」两行居中。
///
/// **为什么去掉图标**：它与下方那个大圆按钮（FAB）语义重复 ——
/// 都是「点这里说话」的意思，连着出现两次反而稀释了重点。
/// 去掉之后视线直接落到按钮上，而那才是要让用户按的东西。
///
/// 与 Android `activity_main.xml` 的 `idle_container` 对应，改动请同步。
struct IdleStateView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("有什么需要我帮你记住的吗？")
                .font(.wd(.titleLarge))
                .foregroundStyle(ThemeManager.shared.palette.neutral800)
                .multilineTextAlignment(.center)

            Text("比如说一句「钥匙放在玄关了」")
                .font(.wd(.bodyMedium))
                .foregroundStyle(ThemeManager.shared.palette.neutral400)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
    }
}

#if DEBUG
#Preview {
    IdleStateView()
        .background(ThemeManager.shared.palette.surface)
}
#endif
