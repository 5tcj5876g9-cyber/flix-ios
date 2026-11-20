import SwiftUI

@main
struct FlixApp: App {
    @StateObject private var downloads = DownloadManager()
    @StateObject private var sniffer = MediaSniffer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(downloads)
                .environmentObject(sniffer)
                .preferredColorScheme(.dark)
        }
    }
}
