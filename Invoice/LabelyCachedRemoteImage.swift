import SwiftUI

/// Simple in-memory image cache to prevent thumbnail re-fetching when views are recreated
/// (e.g. switching tabs back to Home).
enum LabelyImageMemoryCache {
    static let shared = NSCache<NSURL, UIImage>()
}

@MainActor
final class LabelyRemoteImageLoader: ObservableObject {
    @Published var image: UIImage?
    private var currentURL: URL?

    func load(url: URL?) {
        guard let url else {
            image = nil
            currentURL = nil
            return
        }
        if currentURL == url, image != nil { return }
        currentURL = url

        let key = url as NSURL
        if let cached = LabelyImageMemoryCache.shared.object(forKey: key) {
            image = cached
            return
        }

        image = nil
        Task.detached(priority: .userInitiated) {
            var req = URLRequest(url: url)
            req.cachePolicy = .returnCacheDataElseLoad
            req.timeoutInterval = 20
            // Ensure image content types are accepted broadly.
            req.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")

            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
                      let img = UIImage(data: data), img.size.width > 8, img.size.height > 8 else {
                    return
                }
                LabelyImageMemoryCache.shared.setObject(img, forKey: key)
                await MainActor.run { [weak self] in
                    // Only set if we haven't switched URLs mid-flight.
                    if self?.currentURL == url {
                        self?.image = img
                    }
                }
            } catch {
                // Silent failure; callers show placeholder.
            }
        }
    }
}

struct LabelyCachedRemoteImage: View {
    let url: URL?
    var placeholderFill: Color = Color(red: 0.93, green: 0.94, blue: 0.96)

    @StateObject private var loader = LabelyRemoteImageLoader()

    var body: some View {
        Group {
            if let img = loader.image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholderFill
                    .overlay(ProgressView().scaleEffect(0.8))
            }
        }
        .onAppear { loader.load(url: url) }
        .onChange(of: url?.absoluteString ?? "") { _ in loader.load(url: url) }
    }
}

