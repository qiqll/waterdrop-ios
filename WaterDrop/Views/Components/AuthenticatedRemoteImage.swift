import SwiftUI

/// 带鉴权的图片加载视图。
/// 服务端 `/files/{path}` 需要 Bearer token，SwiftUI 自带 AsyncImage 无法附加请求头，
/// 因此这里用 URLSession + AuthStateManager 的 token 手动加载，并在 @Observable 中缓存结果。
struct AuthenticatedRemoteImage: View {
    let urlString: String?

    @State private var state: LoadState = .loading

    enum LoadState {
        case loading
        case loaded(UIImage)
        case failed
    }

    var body: some View {
        Group {
            switch state {
            case .loaded(let image):
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            case .loading:
                ZStack {
                    Rectangle().fill(AppColors.neutral100)
                    ProgressView()
                }
            case .failed:
                ZStack {
                    Rectangle().fill(AppColors.neutral100)
                    Image(systemName: "photo")
                        .font(.system(size: 24))
                        .foregroundStyle(AppColors.neutral400)
                }
            }
        }
        .task(id: urlString) {
            await load()
        }
    }

    private func load() async {
        guard let urlString, let url = URL(string: urlString) else {
            state = .failed
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = ServerConfig.Timeout.read
        if let token = AuthStateManager.shared.getAccessToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let image = UIImage(data: data) else {
                state = .failed
                return
            }
            state = .loaded(image)
        } catch {
            state = .failed
        }
    }
}
