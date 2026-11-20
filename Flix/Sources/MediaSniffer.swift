import Foundation
import Combine

/// Media URLs seen inside the page, including cross-origin player iframes.
///
/// WKUserScript with `forMainFrameOnly: false` is injected by the web engine into
/// every frame regardless of origin, which is the one hook a web page cannot
/// block. The script forwards any <video> source and any m3u8/mp4 request it sees
/// here, and the UI offers to download it natively.
///
/// No `@MainActor` on the type: it is built inside a `@StateObject` initializer,
/// which Swift 5.9 treats as nonisolated. Published state is mutated on the main
/// queue explicitly instead.
final class MediaSniffer: ObservableObject {
    struct Candidate: Identifiable, Equatable {
        let id = UUID()
        let url: String
        let host: String
        let kind: String   // "mp4" | "m3u8"

        var label: String {
            "\(host) · \(kind.uppercased())"
        }
    }

    @Published private(set) var candidates: [Candidate] = []

    func add(urlString: String) {
        guard let url = URL(string: urlString), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return }

        let lower = urlString.lowercased()
        let kind: String
        if lower.contains(".m3u8") {
            kind = "m3u8"
        } else if lower.contains(".mp4") {
            kind = "mp4"
        } else {
            return
        }

        let host = url.host ?? "cdn"
        let candidate = Candidate(url: urlString, host: host, kind: kind)
        onMain { self.apply(candidate) }
    }

    func clear() {
        onMain { self.candidates.removeAll() }
    }

    /// Signed CDN links change per request; two links to the same host and kind
    /// are the same source for the user, so the newest one replaces the old.
    private func apply(_ candidate: Candidate) {
        candidates.removeAll { $0.host == candidate.host && $0.kind == candidate.kind }
        candidates.insert(candidate, at: 0)
        if candidates.count > 6 { candidates.removeLast() }
    }

    private func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
}
