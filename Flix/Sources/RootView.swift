import SwiftUI

struct RootView: View {
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var sniffer: MediaSniffer
    @State private var reloadToken = 0
    @State private var showAddSheet = false
    @State private var pastedURL = ""
    @State private var pastedTitle = ""

    var body: some View {
        TabView {
            browseTab
                .tabItem { Label("تصفّح", systemImage: "play.rectangle") }

            DownloadsView()
                .tabItem { Label("التنزيلات", systemImage: "arrow.down.circle") }

            LibraryView()
                .tabItem { Label("المكتبة", systemImage: "square.stack") }
        }
        .tint(Color(red: 0.36, green: 0.62, blue: 1.0))
        .onOpenURL { url in
            // Handles flixapp:// when the app is launched cold from a link,
            // not just when a page inside the web shell navigates to it.
            guard url.scheme?.lowercased() == "flixapp", url.host == "download" else { return }
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let target = components?.queryItems?.first(where: { $0.name == "url" })?.value
            let title = components?.queryItems?.first(where: { $0.name == "title" })?.value
            guard let target, !target.isEmpty else { return }
            downloads.enqueue(urlString: target, suggestedTitle: title)
        }
    }

    private var browseTab: some View {
        ZStack(alignment: .top) {
            WebShellView(reloadToken: $reloadToken)
                .ignoresSafeArea(edges: .bottom)

            VStack(spacing: 0) {
                Spacer()

                if !sniffer.candidates.isEmpty {
                    candidateBar
                }

                HStack(spacing: 10) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Label("تنزيل رابط", systemImage: "plus.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial, in: Capsule())
                    }

                    Button {
                        reloadToken += 1
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .semibold))
                            .padding(11)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .padding(.bottom, 26)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            NavigationStack {
                Form {
                    Section("رابط الفيديو") {
                        TextField("https://…mp4 أو …m3u8", text: $pastedURL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    Section("الاسم") {
                        TextField("اسم العمل", text: $pastedTitle)
                    }
                    Section {
                        Button("أضف إلى التنزيلات") {
                            downloads.enqueue(urlString: pastedURL, suggestedTitle: pastedTitle)
                            pastedURL = ""
                            pastedTitle = ""
                            showAddSheet = false
                        }
                        .disabled(URL(string: pastedURL)?.scheme == nil)
                    } footer: {
                        Text("الصق رابط البث المباشر (المشغّل ينسخه من قائمة الفيديو). الرابط mp4 يُنزَّل كملف، وm3u8 يُنزَّل بثاً كاملاً للمشاهدة بلا اتصال.")
                    }
                }
                .navigationTitle("تنزيل")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("إغلاق") { showAddSheet = false }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    /// Shown the moment the in-page sniffer catches a stream URL: one tap sends
    /// it to the native downloader, no copy and paste.
    private var candidateBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("رابط بث جاهز للتنزيل")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(sniffer.candidates) { candidate in
                        Button {
                            downloads.enqueue(urlString: candidate.url, suggestedTitle: nil)
                            sniffer.clear()
                        } label: {
                            Label(candidate.label, systemImage: "arrow.down.circle.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(red: 0.36, green: 0.62, blue: 1.0).opacity(0.22), in: Capsule())
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
}
