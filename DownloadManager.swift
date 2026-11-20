import Foundation
import AVFoundation

/// Handles both download shapes the site can hand over:
///
/// * a progressive file (mp4) — plain background `URLSession`, resumable by the system
/// * an HLS stream (m3u8) — `AVAssetDownloadURLSession`, which stores a decodable
///   offline bundle that `AVPlayer` plays with no network
///
/// Jobs are keyed by their source URL so tapping download twice does not duplicate work.
///
/// The class is not annotated `@MainActor`: `URLSession` delegate callbacks arrive on
/// a background queue and the class is instantiated from a `@StateObject` initializer
/// that Swift 5.9 treats as nonisolated. Every mutation of published state therefore
/// hops to the main actor explicitly instead.
final class DownloadManager: NSObject, ObservableObject {
    enum State: String, Codable {
        case queued, downloading, finished, failed
    }

    struct Job: Identifiable, Equatable {
        let id: UUID
        let urlString: String
        var title: String
        var isHLS: Bool
        var state: State
        var progress: Double
        var detail: String
    }

    @Published private(set) var jobs: [Job] = []
    @Published private(set) var library: [MediaItem] = MediaStore.load()

    private var fileSession: URLSession!
    private var hlsSession: AVAssetDownloadURLSession!
    private var taskForJob: [UUID: URLSessionTask] = [:]
    private var jobForTask: [Int: UUID] = [:]

    override init() {
        super.init()
        configureSessions()
    }

    private func configureSessions() {
        let config = URLSessionConfiguration.background(withIdentifier: "app.filmna.flix.downloads")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.httpMaximumConnectionsPerHost = 3
        fileSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        let hlsConfig = URLSessionConfiguration.background(withIdentifier: "app.filmna.flix.hls")
        hlsSession = AVAssetDownloadURLSession(
            configuration: hlsConfig,
            assetDownloadDelegate: self,
            delegateQueue: .main
        )
    }

    // MARK: - Public API

    func enqueue(urlString: String, suggestedTitle: String?) {
        guard let url = URL(string: urlString), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return }

        if let existing = jobs.first(where: { $0.urlString == urlString && $0.state != .failed }) {
            _ = existing
            return
        }

        let isHLS = url.pathExtension.lowercased() == "m3u8" || url.absoluteString.contains(".m3u8")
        let title = (suggestedTitle?.isEmpty == false ? suggestedTitle : nil)
            ?? url.deletingPathExtension().lastPathComponent.removingPercentEncoding
            ?? "مقطع"

        let job = Job(
            id: UUID(),
            urlString: urlString,
            title: title,
            isHLS: isHLS,
            state: .queued,
            progress: 0,
            detail: isHLS ? "تحضير البث" : "بدء التنزيل"
        )
        jobs.append(job)

        if isHLS {
            startHLS(job: job, url: url)
        } else {
            startFile(job: job, url: url)
        }
    }

    func cancel(_ job: Job) {
        taskForJob[job.id]?.cancel()
        taskForJob[job.id] = nil
        update(job.id) { $0.state = .failed; $0.detail = "أُلغي" }
    }

    func retry(_ job: Job) {
        jobs.removeAll { $0.id == job.id }
        enqueue(urlString: job.urlString, suggestedTitle: job.title)
    }

    func delete(_ item: MediaItem) {
        MediaStore.delete(item)
        library.removeAll { $0.id == item.id }
        MediaStore.save(library)
    }

    func clearFinished() {
        jobs.removeAll { $0.state == .finished }
    }

    var storageText: String {
        ByteCountFormatter.string(fromByteCount: MediaStore.totalBytes(), countStyle: .file)
    }

    // MARK: - Progressive files

    private func startFile(job: Job, url: URL) {
        let task = fileSession.downloadTask(with: url)
        taskForJob[job.id] = task
        jobForTask[task.taskIdentifier] = job.id
        update(job.id) { $0.state = .downloading; $0.detail = "جارٍ التنزيل" }
        task.resume()
    }

    // MARK: - HLS

    private func startHLS(job: Job, url: URL) {
        let asset = AVURLAsset(url: url, options: [AVURLAssetHTTPHeaderFieldsKey: ["Referer": url.absoluteString]])
        let task = hlsSession.makeAssetDownloadTask(
            asset: asset,
            assetTitle: job.title,
            assetArtworkData: nil,
            options: [AVAssetDownloadTaskMinimumRequiredMediaBitrateKey: 1_200_000]
        )
        guard let task else {
            update(job.id) { $0.state = .failed; $0.detail = "تعذّر إنشاء مهمة البث" }
            return
        }
        task.taskDescription = job.id.uuidString
        taskForJob[job.id] = task
        jobForTask[task.taskIdentifier] = job.id
        update(job.id) { $0.state = .downloading; $0.detail = "جارٍ تنزيل البث" }
        task.resume()
    }

    /// AVAssetDownloadTask finishes into a temporary location; the file is moved
    /// into Documents so the library owns it and can delete it cleanly.
    private func persistHLS(tempURL: URL, jobID: UUID) {
        guard let job = jobs.first(where: { $0.id == jobID }) else { return }
        let name = "\(job.id.uuidString).movpkg"
        let destination = MediaStore.mediaDirectory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.moveItem(at: tempURL, to: destination)
        } catch {
            update(jobID) { $0.state = .failed; $0.detail = "فشل الحفظ" }
            return
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64) ?? 0
        finish(jobID: jobID, fileName: name, isHLS: true, byteSize: size)
    }

    private func persistFile(tempURL: URL, jobID: UUID) -> String? {
        guard let job = jobs.first(where: { $0.id == jobID }) else { return nil }
        let ext = URL(string: job.urlString)?.pathExtension ?? "mp4"
        let name = "\(job.id.uuidString).\(ext.isEmpty ? "mp4" : ext)"
        let destination = MediaStore.mediaDirectory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.moveItem(at: tempURL, to: destination)
            let size = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64) ?? 0
            finish(jobID: jobID, fileName: name, isHLS: false, byteSize: size)
            return name
        } catch {
            update(jobID) { $0.state = .failed; $0.detail = "فشل الحفظ" }
            return nil
        }
    }

    private func finish(jobID: UUID, fileName: String, isHLS: Bool, byteSize: Int64) {
        guard let job = jobs.first(where: { $0.id == jobID }) else { return }
        update(jobID) { $0.state = .finished; $0.progress = 1; $0.detail = "متاح بلا اتصال" }

        let item = MediaItem(
            id: jobID,
            title: job.title,
            fileName: fileName,
            isHLS: isHLS,
            addedAt: Date(),
            byteSize: byteSize,
            sourceURL: job.urlString
        )
        library.removeAll { $0.id == item.id }
        library.insert(item, at: 0)
        MediaStore.save(library)
        taskForJob[jobID] = nil
    }

    private func update(_ id: UUID, _ mutate: (inout Job) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        mutate(&jobs[index])
    }
}

// MARK: - URLSession (progressive)

extension DownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let fraction = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : 0
        let received = ByteCountFormatter.string(fromByteCount: totalBytesWritten, countStyle: .file)
        let total = totalBytesExpectedToWrite > 0
            ? ByteCountFormatter.string(fromByteCount: totalBytesExpectedToWrite, countStyle: .file)
            : "؟"
        let identifier = downloadTask.taskIdentifier

        Task { @MainActor in
            guard let jobID = self.jobForTask[identifier] else { return }
            self.update(jobID) {
                $0.state = .downloading
                $0.progress = min(0.999, fraction)
                $0.detail = "\(received) من \(total)"
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let identifier = downloadTask.taskIdentifier
        // The temporary file is deleted when this method returns, so the move has
        // to happen synchronously before hopping back to the main actor.
        let staged = FileManager.default.temporaryDirectory
            .appendingPathComponent("stage-\(UUID().uuidString)")
        try? FileManager.default.copyItem(at: location, to: staged)

        Task { @MainActor in
            guard let jobID = self.jobForTask[identifier] else { return }
            _ = self.persistFile(tempURL: staged, jobID: jobID)
            try? FileManager.default.removeItem(at: staged)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        let identifier = task.taskIdentifier
        Task { @MainActor in
            guard let jobID = self.jobForTask[identifier] else { return }
            self.update(jobID) {
                $0.state = .failed
                $0.detail = error.localizedDescription.prefix(60).description
            }
        }
    }
}

// MARK: - AVAssetDownloadURLSession (HLS)

extension DownloadManager: AVAssetDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        didLoad timeRange: CMTimeRange,
        totalTimeRangesLoaded loadedTimeRanges: [NSValue],
        timeRangeExpectedToLoad: CMTimeRange
    ) {
        var loaded = 0.0
        for value in loadedTimeRanges {
            loaded += value.timeRangeValue.duration.seconds
        }
        let expected = timeRangeExpectedToLoad.duration.seconds
        let fraction = expected > 0 ? loaded / expected : 0
        let identifier = assetDownloadTask.taskIdentifier
        let megabytes = ByteCountFormatter.string(
            fromByteCount: Int64(max(0, timeRange.duration.seconds)) * 350_000,
            countStyle: .file
        )

        Task { @MainActor in
            guard let jobID = self.jobForTask[identifier] else { return }
            self.update(jobID) {
                $0.progress = min(0.999, fraction)
                $0.detail = "بث \(String(format: "%.0f", fraction * 100))% — \(megabytes)"
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let staged = FileManager.default.temporaryDirectory
            .appendingPathComponent("stage-\(UUID().uuidString).movpkg")
        try? FileManager.default.copyItem(at: location, to: staged)
        let identifier = assetDownloadTask.taskIdentifier

        Task { @MainActor in
            guard let jobID = self.jobForTask[identifier] else { return }
            self.persistHLS(tempURL: staged, jobID: jobID)
            try? FileManager.default.removeItem(at: staged)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        let identifier = assetDownloadTask.taskIdentifier
        Task { @MainActor in
            guard let jobID = self.jobForTask[identifier] else { return }
            self.update(jobID) {
                $0.state = .failed
                $0.detail = error.localizedDescription.prefix(60).description
            }
        }
    }
}
