import SwiftUI
import AVKit
import AVFoundation

struct LibraryView: View {
    @EnvironmentObject private var downloads: DownloadManager
    @State private var playing: MediaItem?

    var body: some View {
        NavigationStack {
            Group {
                if downloads.library.isEmpty {
                    ContentUnavailableView(
                        "المكتبة فاضية",
                        systemImage: "square.stack",
                        description: Text("كل ما ينتهي تنزيله يظهر هنا ويُشغَّل بلا إنترنت.")
                    )
                } else {
                    List {
                        ForEach(downloads.library) { item in
                            Button {
                                playing = item
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: item.isHLS ? "dot.radiowaves.left.and.right" : "film")
                                        .font(.system(size: 18))
                                        .frame(width: 34, height: 34)
                                        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.title)
                                            .font(.system(size: 15, weight: .semibold))
                                            .lineLimit(2)
                                        Text("\(item.sizeText) • \(item.isHLS ? "بث منزَّل" : "ملف")")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "play.circle.fill")
                                        .font(.system(size: 22))
                                        .foregroundStyle(Color(red: 0.36, green: 0.62, blue: 1.0))
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button(role: .destructive) {
                                    downloads.delete(item)
                                } label: {
                                    Label("حذف", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("المكتبة")
            .fullScreenCover(item: $playing) { item in
                OfflinePlayer(item: item)
            }
        }
    }
}

/// Plays straight from the sandboxed file — no network, no DRM handshake, no
/// provider involvement. HLS bundles are opened as .movpkg directories, which
/// AVPlayer treats as a local stream.
struct OfflinePlayer: View {
    let item: MediaItem
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var error: String?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            if let player {
                VideoSurface(player: player)
                    .ignoresSafeArea()
            } else if let error {
                Text(error)
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ProgressView().tint(.white)
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .padding(12)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(20)
        }
        .onAppear(perform: prepare)
        .onDisappear { player?.pause() }
    }

    private func prepare() {
        let url = item.fileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            error = "الملف غير موجود على الجهاز."
            return
        }
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer
        newPlayer.play()
    }
}

private struct VideoSurface: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.videoGravity = .resizeAspect
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        controller.player = player
    }
}
