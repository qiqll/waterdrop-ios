import SwiftUI

struct SplashView: View {
    let onFinished: () -> Void
    @State private var dropOffset: CGFloat = -100
    @State private var dropOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var sloganOpacity: Double = 0

    /// F-012 ①: 强更新信息。非 nil 时用 fullScreenCover 拦住用户，不进入应用。
    @State private var forceUpdateInfo: VersionCheckResponse?

    var body: some View {
        ZStack {
            ThemeManager.shared.palette.background.ignoresSafeArea()

            VStack(spacing: 16) {
                Spacer()

                // Water drop icon
                Image(systemName: "drop.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(ThemeManager.shared.palette.primary)
                    .offset(y: dropOffset)
                    .opacity(dropOpacity)

                // App name
                Text("水滴管家")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(ThemeManager.shared.palette.neutral800)
                    .opacity(textOpacity)

                // Slogan
                Text("点点滴滴，记在心里")
                    .font(.system(size: 16))
                    .foregroundStyle(ThemeManager.shared.palette.neutral600)
                    .opacity(sloganOpacity)

                Spacer()
            }
        }
        .onAppear {
            startAnimation()
        }
        .fullScreenCover(item: $forceUpdateInfo) { info in
            ForceUpdateView(info: info)
        }
    }

    private func startAnimation() {
        let isFirstLaunch = !UserDefaults.standard.bool(forKey: "has_launched_before")
        let totalDuration: Double = isFirstLaunch ? 2.8 : 1.2

        // 版本检查与动画**并行**：它只写 @State，不参与下面的导航计时。
        // 冷启动耗时不受网络影响 —— 检查超时（3s）或失败都静默放行。
        startVersionCheck()

        // Drop animation with overshoot
        withAnimation(.interpolatingSpring(stiffness: 100, damping: 10).delay(0.1)) {
            dropOffset = 0
            dropOpacity = 1
        }

        // Text fade in
        withAnimation(.easeOut(duration: 0.5).delay(totalDuration * 0.3)) {
            textOpacity = 1
        }

        // Slogan fade in
        withAnimation(.easeOut(duration: 0.5).delay(totalDuration * 0.5)) {
            sloganOpacity = 1
        }

        // Mark as launched and navigate
        UserDefaults.standard.set(true, forKey: "has_launched_before")

        DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration) {
            // 已有强更新结果就先别走：fullScreenCover 会盖在上面，
            // 但导航到登录页的结果不可逆，所以这里必须先判断。
            guard forceUpdateInfo == nil else { return }
            onFinished()
        }
    }

    /// 检查更新。
    ///
    /// 三条纪律，缺一条都会把「更新检查」变成「启动故障」：
    /// 1. **有超时**：`withTimeout` 封顶 3s，超过就当作没有更新。
    /// 2. **静默失败**：网络不可达 / 服务端 5xx / 解析失败一律吞掉 —— 冷启动路径上
    ///    没有任何 UI 可以承载错误，也不该为版本检查弹提示。
    /// 3. **只拦强更新**：OPTIONAL / SILENT 一律放行，让用户先进应用。
    private func startVersionCheck() {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""

        Task {
            let info: VersionCheckResponse?
            do {
                info = try await withTimeout(seconds: 3) {
                    let response = try await VersionAPIService.checkVersion(currentVersion: currentVersion)
                    guard response.code == 200 else { return nil }
                    return response.data
                }
            } catch {
                // 故意吞掉：更新检查失败不是启动失败。
                info = nil
            }

            guard let info, info.needUpdate else { return }
            // 只有强更新才打断启动。OPTIONAL/SILENT 交给后续的更新引导。
            guard info.updateType == VersionUpdateType.force.rawValue else { return }

            await MainActor.run {
                forceUpdateInfo = info
            }
        }
    }
}

// MARK: - Timeout Helper

/// 给任意 async 操作加超时上限，超时返回 nil 而不是抛错。
///
/// 用 `Task.sleep` 竞速而非 `TaskGroup`：这里不需要取消底层请求
/// （URLSession 自己会在 read timeout 到点后收尾），只要不再阻塞启动流程即可。
private func withTimeout<T: Sendable>(
    seconds: Double,
    _ operation: @escaping @Sendable () async throws -> T?
) async throws -> T? {
    try await withThrowingTaskGroup(of: T?.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            return nil
        }
        let result = try await group.next() ?? nil
        group.cancelAll()
        return result
    }
}

// MARK: - Force Update View

/// 强更新拦截页。
///
/// `interactiveDismissDisabled(true)` 是这里的关键：强更新意味着当前版本存在
/// 无法通过热修解决的问题，必须升级才能继续用。没有「稍后」、不能下滑关闭、
/// 也没有取消按钮 —— 唯一的出路是去下载。
struct ForceUpdateView: View {
    let info: VersionCheckResponse

    var body: some View {
        ZStack {
            ThemeManager.shared.palette.background.ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()

                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(ThemeManager.shared.palette.primary)

                Text("发现新版本")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(ThemeManager.shared.palette.neutral800)

                if let latest = info.latestVersion {
                    Text(latest)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(ThemeManager.shared.palette.primary)
                }

                if let fileSize = info.fileSize, fileSize > 0 {
                    Text("大小：\(formatSize(fileSize))")
                        .font(.system(size: 14))
                        .foregroundStyle(ThemeManager.shared.palette.neutral600)
                }

                if let notes = updateNotes, !notes.isEmpty {
                    ScrollView {
                        Text(notes)
                            .font(.system(size: 15))
                            .foregroundStyle(ThemeManager.shared.palette.neutral600)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .frame(maxHeight: 200)
                    .background(ThemeManager.shared.palette.neutral100)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 32)
                }

                Text("当前版本已无法继续使用，请升级后重试")
                    .font(.system(size: 13))
                    .foregroundStyle(ThemeManager.shared.palette.neutral600)

                Spacer()

                Button {
                    openDownload()
                } label: {
                    Text("立即更新")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(ThemeManager.shared.palette.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }
        }
        .interactiveDismissDisabled(true)
    }

    /// 更新说明：优先 changelog，退回 description。
    private var updateNotes: String? {
        if let changelog = info.changelog, !changelog.isEmpty { return changelog }
        return info.description
    }

    /// 跳转下载页。用系统浏览器而不是应用内下载 —— 本需求只负责「把用户导向下载」，
    /// 应用内下载/安装涉及额外权限与流程，超出 ① 的范围。
    private func openDownload() {
        guard let urlString = info.downloadUrl, !urlString.isEmpty,
              let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
    }

    private func formatSize(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1024.0 / 1024.0
        return mb >= 1 ? String(format: "%.1f MB", mb) : "\(bytes / 1024) KB"
    }
}
