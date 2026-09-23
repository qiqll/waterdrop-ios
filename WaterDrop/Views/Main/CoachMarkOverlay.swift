import SwiftUI

/// 新手引导蒙版（F-018 §1）。
///
/// ## 是什么
///
/// 盖在**真实界面**之上的一层：整体压暗，把当前要讲的控件**挖个洞亮出来**，
/// 旁边配一句话和「下一步」。与「整页幻灯片式引导」的区别在于 ——
/// 用户看到的是他自己马上要操作的界面，而不是一张示意图。
///
/// 与 Android `CoachMarkOverlay` 是一套设计的两处实现，改动请同步。
///
/// ## 挖孔怎么做
///
/// SwiftUI 里比 Android 简单得多：把压暗矩形与「洞」放进同一个
/// `ZStack`，给洞加 `.blendMode(.destinationOut)`，再把整组
/// `.compositingGroup()` —— 洞就把压暗层擦掉了。
/// 不需要离屏 Canvas，也不需要 PorterDuff。
///
/// ## 锚点怎么定位
///
/// 用 `PreferenceKey` 收集目标控件的 frame（`GeometryReader` +
/// `.preference`），而不是像 Android 那样读屏幕坐标。
/// 这样天然适配 SwiftUI 的布局系统，旋转/尺寸变化也不用重算。
struct CoachMarkOverlay: View {

    /// 一步引导的内容。
    struct Step: Identifiable {
        let id = UUID()
        /// 锚点 id —— 对应 `.coachAnchor("...")` 里注册的字符串
        let anchor: String
        let title: String
        let body: String
        /// 挖孔形状
        let shape: Shape
        /// 气泡放在控件的哪一侧；nil 表示自动
        let placement: Placement?
        /// 最后一步不给跳过
        let skippable: Bool

        enum Shape { case circle, roundedRect }
        enum Placement { case above, below }

        /// 显式 init。
        ///
        /// 不用 memberwise init 的原因：`id` 有默认值且排在首位，
        /// 而调用处想按 `anchor/title/body/placement` 的顺序传 ——
        /// 编译器会因为中间夹着有默认值的 `id` 而推断失败。
        init(
            anchor: String,
            title: String,
            body: String,
            shape: Shape = .circle,
            placement: Placement? = nil,
            skippable: Bool = true
        ) {
            self.anchor = anchor
            self.title = title
            self.body = body
            self.shape = shape
            self.placement = placement
            self.skippable = skippable
        }
    }

    let steps: [Step]
    /// 各锚点的 frame，key 是 `.coachAnchor(...)` 的字符串。
    ///
    /// ⚠️ **由调用方传入，不在这里自己收集** —— SwiftUI 的 preference
    /// 只能「子 → 父」上传，而本视图与那些带锚点的按钮是**兄弟关系**，
    /// 自己订阅永远收不到。（这一点实测验证过：锚点为空 → 洞挖不出来。）
    /// 收集必须在共同祖先（MainView 的 ZStack）上做。
    let anchors: [String: CGRect]
    /// 走完全部步骤
    let onFinish: () -> Void
    /// 用户点了跳过
    let onSkip: () -> Void

    @State private var index = 0

    private var current: Step { steps[index] }

    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .topLeading) {
                // ① 压暗 + 挖孔
                //
                // 用 Canvas + 奇偶填充（even-odd）挖孔，而**不是** `blendMode(.destinationOut)`。
                // 后者在这里不生效：实测压暗层照画、洞没被擦掉，按钮完全没有被点亮。
                // 奇偶规则的行为是确定的 —— 一个矩形 + 一个洞路径组成的复合路径，
                // 重叠部分按「穿过次数为奇 = 填充」渲染，洞自然就是空的。
                // Android 侧用的是 PorterDuff.CLEAR，两端做法不同但效果一致。
                // 洞与描边必须**在同一个坐标系里**。
                //
                // 坑：Canvas 加了 `.ignoresSafeArea()` 后坐标系变成「屏幕」，
                // 而描边留在 ZStack 里是「安全区」坐标 —— 两者差一个状态栏高度，
                // 实测表现为「洞对了、圈偏下」。
                // 解法：把两者放进同一个 ignoresSafeArea 容器，统一用全局 rect。
                ZStack(alignment: .topLeading) {
                    Canvas { ctx, size in
                        var path = Path(CGRect(origin: .zero, size: size))
                        if let r = anchorRect {
                            switch current.shape {
                            case .circle:
                                path.addEllipse(in: r)
                            case .roundedRect:
                                path.addRoundedRect(in: r, cornerSize: CGSize(width: 14, height: 14))
                            }
                        }
                        ctx.fill(path, with: .color(.black.opacity(0.7)), style: FillStyle(eoFill: true))
                    }

                    if let rect = anchorRect {
                        holeShape()
                            .stroke(ThemeManager.shared.palette.accent, lineWidth: 2.5)
                            .frame(width: rect.width, height: rect.height)
                            .offset(x: rect.minX, y: rect.minY)
                    }
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)

                // ③ 气泡 —— 用 GeometryReader 直接算位置。
                //    曾用「上下各加 padding」的写法，多层 padding 会互相干扰、
                //    结果对不上；直接算 frame 更可靠也更好读。
                GeometryReader { geo in
                    bubble
                        .frame(width: geo.size.width)
                        .position(
                            x: geo.size.width / 2,
                            y: bubbleCenterY(in: geo.size.height)
                        )
                }
            }
        }
        // 点蒙版空白处**不推进** —— 见 Android 侧同名注释：
        // 曾经写成点任意处都推进，实测会误跳过（用户想点按钮，
        // 但气泡位置在这步变了，点在空白处就被当成「下一步」）。
        .contentShape(Rectangle())
    }

    // MARK: - 锚点

    private var anchorRect: CGRect? {
        guard let r = anchors[current.anchor] else { return nil }
        // 外扩一点，让洞比控件稍大，视觉上更舒服
        return r.insetBy(dx: -10, dy: -10)
    }

    /// 气泡在控件的上方还是下方。
    private var bubbleAbove: Bool {
        if let p = current.placement { return p == .above }
        guard let r = anchorRect else { return false }
        // 控件在下半屏 → 气泡放上方
        return r.midY > UIScreen.main.bounds.height * 0.55
    }

    /// 挖孔形状。
    ///
    /// 返回 `AnyShape` 而不是 `some View` —— 因为调用处既要把它当填充
    /// （加 `blendMode(.destinationOut)` 擦掉压暗层），又要 `.stroke` 描边。
    /// `some View` 是不透明类型，调不到 `.stroke`。
    private func holeShape() -> AnyShape {
        switch current.shape {
        case .circle:
            return AnyShape(Circle())
        case .roundedRect:
            return AnyShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - 气泡

    /// 气泡的纵向中心。
    private func bubbleCenterY(in height: CGFloat) -> CGFloat {
        guard let r = anchorRect else { return height / 2 }
        let gap: CGFloat = 14
        // 气泡高度约 150（标题 + 正文 + 按钮行），取一半做偏移
        let half: CGFloat = 80
        if bubbleAbove {
            let y = r.minY - gap - half
            // 上方放不下就翻到下方
            if y - half < 60 { return min(r.maxY + gap + half, height - half - 40) }
            return y
        } else {
            let y = r.maxY + gap + half
            if y + half > height - 40 { return max(r.minY - gap - half, half + 60) }
            return y
        }
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(current.title)
                .font(.wd(.titleMedium, weight: .semibold))
                .foregroundStyle(ThemeManager.shared.palette.neutral800)

            Text(current.body)
                .font(.wd(.bodyMedium))
                .foregroundStyle(ThemeManager.shared.palette.neutral600)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                if steps.count > 1 {
                    Text("\(index + 1) / \(steps.count)")
                        .font(.wd(.labelSmall))
                        .foregroundStyle(ThemeManager.shared.palette.neutral400)
                }
                Spacer()
                if current.skippable && index < steps.count - 1 {
                    Button("跳过") { onSkip() }
                        .font(.wd(.labelLarge))
                        .foregroundStyle(ThemeManager.shared.palette.neutral500)
                        .padding(.trailing, 6)
                }
                Button(index == steps.count - 1 ? "开始使用" : "下一步") {
                    advance()
                }
                .font(.wd(.labelLarge, weight: .bold))
                .foregroundStyle(ThemeManager.shared.palette.primary)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(ThemeManager.shared.palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.16), radius: 14, y: 5)
        .padding(.horizontal, 20)
    }

    private func advance() {
        if index >= steps.count - 1 {
            onFinish()
        } else {
            withAnimation(.easeInOut(duration: 0.22)) {
                index += 1
            }
        }
    }
}

// MARK: - 锚点注册

/// 收集各锚点 frame 的 PreferenceKey。
struct CoachAnchorKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// 把一个视图注册为引导锚点。
    ///
    /// 用法：`Text("...").coachAnchor("voiceFab")`
    /// 然后在 `CoachMarkOverlay.Step(anchor: "voiceFab", ...)` 里引用它。
    func coachAnchor(_ id: String) -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: CoachAnchorKey.self,
                    value: [id: geo.frame(in: .global)]
                )
            }
        )
    }
}

// MARK: - 偏好存储

/// 引导是否完整看过（F-018 §1）。
///
/// 语义是「**完整走完**」而非「出现过」：中途跳过不写标记，
/// 下次进入还会展示。与 Android `CoachMarkPrefs` 对应。
enum CoachMarkPrefs {
    private static let key = "main_coach_seen"

    static var hasSeen: Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    static func markSeen() {
        UserDefaults.standard.set(true, forKey: key)
    }

    /// 供开发/测试重置。生产代码不要调用。
    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
