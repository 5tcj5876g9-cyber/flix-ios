import SwiftUI

struct DownloadsView: View {
    @EnvironmentObject private var downloads: DownloadManager

    var body: some View {
        NavigationStack {
            Group {
                if downloads.jobs.isEmpty {
                    ContentUnavailableView(
                        "لا تنزيلات",
                        systemImage: "arrow.down.circle",
                        description: Text("افتح أي عمل ثم اضغط تنزيل داخل التطبيق، أو الصق رابطاً مباشراً من زر «تنزيل رابط».")
                    )
                } else {
                    List {
                        ForEach(downloads.jobs) { job in
                            row(job)
                        }
                        Section {
                            Text("المساحة المستخدمة: \(downloads.storageText)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Button("مسح المنتهية") { downloads.clearFinished() }
                                .font(.footnote)
                        }
                    }
                }
            }
            .navigationTitle("التنزيلات")
        }
    }

    private func row(_ job: DownloadManager.Job) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(job.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Text(badge(job.state))
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(badgeColor(job.state).opacity(0.18), in: Capsule())
                    .foregroundStyle(badgeColor(job.state))
            }

            if job.state == .downloading {
                ProgressView(value: max(0.01, job.progress))
                    .tint(Color(red: 0.36, green: 0.62, blue: 1.0))
            }

            HStack {
                Text(job.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if job.state == .downloading {
                    Button("إلغاء") { downloads.cancel(job) }
                        .font(.caption)
                } else if job.state == .failed || job.state == .finished {
                    Button("إعادة") { downloads.retry(job) }
                        .font(.caption)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func badge(_ state: DownloadManager.State) -> String {
        switch state {
        case .queued: return "بالانتظار"
        case .downloading: return "ينزل"
        case .finished: return "مكتمل"
        case .failed: return "فشل"
        }
    }

    private func badgeColor(_ state: DownloadManager.State) -> Color {
        switch state {
        case .queued: return .gray
        case .downloading: return .blue
        case .finished: return .green
        case .failed: return .red
        }
    }
}
