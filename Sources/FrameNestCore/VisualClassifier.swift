import Foundation
import Vision
import AVFoundation
import ImageIO
import CryptoKit

public struct VisualLabel: Codable, Sendable {
    public let name: String
    public let confidence: Double
}

public struct VisualAnalysis: Codable, Sendable {
    public let engine: String
    public let category: String?
    public let reason: String
    public let sampledTimes: [Double]
    public let framesAnalyzed: Int
    public let labels: [VisualLabel]
    public let status: String
    public var cacheHit: Bool
    public var ocrFrames: Int? = nil
}

struct VisualFrame: Codable {
    var labels: [String: Double] = [:]
    var faceX: Double?
    var faceY: Double?
    var faceHeight: Double?
    var textAnalyzed = false
    var textCount = 0
    var largeTitle = false
    var interfaceText = false
    var testReadout = false

    var screenshot: Bool {
        (labels["screenshot"] ?? 0) >= 0.65 ||
        ((labels["screenshot"] ?? 0) >= 0.3 && (interfaceText || testReadout)) ||
        (interfaceText && textCount >= 6 && (labels["document"] ?? 0) >= 0.45 && faceX == nil)
    }
    var electronics: Bool {
        ["consumer_electronics", "camera", "phone", "computer", "computer_mouse", "computer_keyboard", "computer_monitor", "headphones", "speakers_music", "microphone", "watch", "remote_control"].contains { (labels[$0] ?? 0) >= 0.45 }
    }
}

/// On-device object classification, OCR and face geometry. No network requests.
public enum VisualClassifier {
    static let revision = "apple-vision-1.6.0"
    static let imageExtensions = Organizer.images.subtracting(["svg", "exr", "dpx"]).union(Organizer.rawPhotos)
    static let videoExtensions = Organizer.videos.subtracting(["r3d", "braw", "insv", "360"])

    public static func eligible(_ item: OrganizeItem) -> Bool {
        !item.wholeDirectory && item.category == "09_待确认" &&
        (imageExtensions.contains(item.source.pathExtension.lowercased()) || videoExtensions.contains(item.source.pathExtension.lowercased()))
    }

    public static func refine(_ items: [OrganizeItem], useCache: Bool = true, control: OperationControl? = nil, progress: (String) -> Void = { _ in }) throws -> [OrganizeItem] {
        var result = items
        let indices = result.indices.filter { eligible(result[$0]) }
        for (position, index) in indices.enumerated() {
            try control?.checkpoint()
            progress("正在识别画面 \(position + 1)/\(indices.count)：\(result[index].source.lastPathComponent)")
            control?.report(.recognizing, completed: position, total: indices.count, message: "正在识别画面：" + result[index].source.lastPathComponent)
            let analysis = try autoreleasepool { try analyzeCancellable(result[index].source, useCache: useCache, control: control) }
            result[index].visualAnalysis = analysis
            if let category = analysis.category { result[index].category = category }
            result[index].reason = analysis.reason
        }
        control?.report(.recognizing, completed: indices.count, total: indices.count, message: "画面识别完成")
        return result
    }

    public static func analyze(_ url: URL, useCache: Bool = true) -> VisualAnalysis {
        // Without a cancellation control, analysis failures remain review results.
        (try? autoreleasepool { try analyzeCancellable(url, useCache: useCache, control: nil) }) ?? unavailable("画面识别未完成，保留待确认。")
    }

    public static func analyze(_ url: URL, useCache: Bool = true, control: OperationControl) throws -> VisualAnalysis {
        try autoreleasepool { try analyzeCancellable(url, useCache: useCache, control: control) }
    }

    private static func analyzeCancellable(_ url: URL, useCache: Bool, control: OperationControl?) throws -> VisualAnalysis {
        try control?.checkpoint()
        let ext = url.pathExtension.lowercased()
        let isVideo = videoExtensions.contains(ext)
        guard isVideo || imageExtensions.contains(ext) else {
            return unavailable("当前格式暂不支持本地画面识别，需确认。")
        }
        let signature = cacheURL(url)
        let cache = useCache ? signature : nil
        if let cache, let data = try? Data(contentsOf: cache), var saved = try? JSONDecoder().decode(VisualAnalysis.self, from: data) {
            saved.cacheHit = true
            return saved
        }
        do {
            let result: VisualAnalysis
            if isVideo {
                result = try video(url, control: control)
            } else {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 1280,
                        kCGImageSourceShouldCacheImmediately: true
                      ] as CFDictionary) else { throw HelperError.message("图片无法解码") }
                result = decide([try observe(image, control: control)], times: [], isVideo: false)
            }
            try control?.checkpoint()
            guard signature == cacheURL(url) else { return unavailable("识别期间文件发生变化，请重新扫描。") }
            if let cache, result.status != "unavailable", let data = try? JSONEncoder().encode(result) {
                let parent = cache.deletingLastPathComponent()
                try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try? data.write(to: cache, options: .atomic)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cache.path)
            }
            return result
        } catch is CancellationError { throw CancellationError() }
        catch {
            return unavailable("画面读取失败，保留待确认：\(error.localizedDescription)")
        }
    }

    static func unavailable(_ reason: String) -> VisualAnalysis {
        VisualAnalysis(engine: "Apple Vision", category: nil, reason: reason, sampledTimes: [], framesAnalyzed: 0, labels: [], status: "unavailable", cacheHit: false)
    }

    static func cacheURL(_ url: URL) -> URL? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attrs[.modificationDate] as? Date, let size = attrs[.size] as? NSNumber,
              let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let identity = "\(revision)|\(ProcessInfo.processInfo.operatingSystemVersionString)|\(url.resolvingSymlinksInPath().path)|\(date.timeIntervalSince1970.bitPattern)|\(size)|\(attrs[.systemFileNumber] ?? "")"
        let key = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent("io.github.weixunkkkkk.framenest/VisualAnalysis/" + key + ".json")
    }

    static func observe(_ image: CGImage, isVideo: Bool = false, session: VisionSession = VisionSession(), control: OperationControl? = nil) throws -> VisualFrame {
        try control?.checkpoint()
        let classification = session.classification, faces = session.faces, text = session.text
        let handler = VNImageRequestHandler(cgImage: image)
        try handler.perform([classification, faces])
        var frame = VisualFrame()
        for label in classification.results ?? [] where label.confidence >= 0.01 {
            frame.labels[label.identifier] = Double(label.confidence)
        }
        let detectedFaces = faces.results ?? []
        if detectedFaces.count == 1, let face = detectedFaces.first,
           face.boundingBox.height >= 0.14, face.boundingBox.width * face.boundingBox.height >= 0.018,
           (0.2...0.8).contains(face.boundingBox.midX), abs(face.yaw?.doubleValue ?? 0) < 0.65 {
            frame.faceX = face.boundingBox.midX
            frame.faceY = face.boundingBox.midY
            frame.faceHeight = face.boundingBox.height
        }
        // OCR cannot change these video decisions: screenshot evidence is already
        // decisive, or document/screenshot labels are below the text-based rules.
        let screenScore = frame.labels["screenshot"] ?? 0
        let documentScore = frame.labels["document"] ?? 0
        let skipText = isVideo && (screenScore >= 0.65 ||
            (screenScore < 0.15 && documentScore < 0.2 && (frame.faceX != nil || frame.electronics)))
        if skipText { return frame }
        try control?.checkpoint()
        try handler.perform([text])
        frame.textAnalyzed = true
        let words = (text.results ?? []).compactMap { observation -> (String, CGRect)? in
            guard let best = observation.topCandidates(1).first, best.confidence >= 0.4 else { return nil }
            return (best.string, observation.boundingBox)
        }
        frame.textCount = words.count
        frame.largeTitle = words.filter { $0.0.count >= 3 && $0.1.height >= 0.055 }.count >= 2
        let corpus = words.map(\.0).joined(separator: " ").lowercased()
        let interfaceWords = ["finder", "file edit", "文件 编辑", "文件编辑", "浏览器", "https://", "http://", "localhost", "终端", "素材归类", "新建项目", "任务管理", "system settings", "系统设置", "visual studio", "菜单栏", "资源管理器"]
        frame.interfaceText = interfaceWords.contains(where: corpus.contains)
        let measurement = ["fixed:", "fixed：", "pps:", "pps：", "avs:", "avs：", "power-z", "km003", "电压", "电流", "纹波", "voltage", "current"]
        frame.testReadout = measurement.filter { corpus.contains($0) }.count >= 2 || (corpus.contains("fixed") && corpus.contains("pps"))
        return frame
    }

    static func decide(_ frames: [VisualFrame], times: [Double], isVideo: Bool) -> VisualAnalysis {
        var labels: [String: Double] = [:]
        for frame in frames { for (name, score) in frame.labels { labels[name, default: 0] += score / Double(frames.count) } }
        let top = labels.sorted { $0.value > $1.value }.prefix(6).map { VisualLabel(name: $0.key, confidence: $0.value) }
        func answer(_ category: String?, _ reason: String) -> VisualAnalysis {
            VisualAnalysis(engine: "Apple Vision", category: category, reason: reason,
                           sampledTimes: times, framesAnalyzed: frames.count, labels: top,
                           status: category == nil ? "uncertain" : "classified", cacheHit: false, ocrFrames: frames.filter(\.textAnalyzed).count)
        }
        guard !frames.isEmpty, !isVideo || frames.count >= 3 else { return answer(nil, "有效画面不足，保留待确认。") }
        let needed = isVideo ? Int(ceil(Double(frames.count) * 0.8)) : 1
        let screens = frames.filter(\.screenshot).count
        let products = frames.filter { $0.electronics && !$0.screenshot && $0.faceX == nil }.count
        let portraits = frames.filter { $0.faceX != nil && !$0.screenshot }.count
        if !isVideo, let frame = frames.first, frame.largeTitle, !frame.interfaceText,
           !frame.testReadout, frame.textCount <= 18, frame.faceX != nil || frame.electronics {
            return answer("04_图片与封面/封面", "画面识别：人像或产品配合大标题，建议作为封面。")
        }
        if screens >= needed {
            return answer(isVideo ? "02_原始素材/屏幕录制" : "04_图片与封面/截图",
                          "画面识别：\(isVideo ? "多帧为屏幕界面" : "屏幕界面或测试读数截图")（\(frames.count) 帧）。")
        }
        if isVideo, portraits >= needed {
            let xs = frames.compactMap(\.faceX), ys = frames.compactMap(\.faceY), heights = frames.compactMap(\.faceHeight)
            let stable = (xs.max()! - xs.min()! <= 0.16) && (ys.max()! - ys.min()! <= 0.16) && (heights.max()! / heights.min()! <= 1.8)
            if stable { return answer("02_原始素材/口播", "画面识别：多帧稳定近景人像，建议作为口播（\(frames.count) 帧）。") }
        }
        if products >= needed {
            return answer(isVideo ? "02_原始素材/产品实拍" : "04_图片与封面/产品原图",
                          "画面识别：\(isVideo ? "多帧以数码设备为主体" : "以数码设备为主体的图片")（\(frames.count) 帧）。")
        }
        return answer(nil, "画面识别：\(screens > 0 || products > 0 || portraits > 0 ? "画面用途混杂或依据不足" : "没有足够依据确定用途")，保留待确认（\(frames.count) 帧）。")
    }

    private static func wait(_ semaphore: DispatchSemaphore, control: OperationControl?, message: String) throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 12
        while semaphore.wait(timeout: .now() + 0.05) == .timedOut {
            try control?.checkpoint()
            if ProcessInfo.processInfo.systemUptime >= deadline { throw HelperError.message(message) }
        }
        try control?.checkpoint()
    }

    static func video(_ url: URL, control: OperationControl?) throws -> VisualAnalysis {
        let asset = AVURLAsset(url: url)
        let loading = DurationLoad()
        let task = Task.detached {
            do {
                let value = try await asset.load(.duration).seconds
                loading.lock.withLock { loading.value = value }
            } catch { loading.lock.withLock { loading.failure = error } }
            loading.done.signal()
        }
        do { try wait(loading.done, control: control, message: "视频信息读取超时") }
        catch { task.cancel(); throw error }
        if let error = loading.failure { throw error }
        let duration = loading.value ?? 0
        guard duration.isFinite, duration > 0 else { throw HelperError.message("视频时长不可用") }
        let fractions: [Double] = [0.05, 0.25, 0.5, 0.75, 0.95]
        let values = Set(fractions.map { fraction in
            CMTime(seconds: Double(Int(min(max(0, duration - 0.02), duration * fraction) * 1000)) / 1000, preferredTimescale: 600).value
        }).sorted()
        let times = values.map { CMTime(value: $0, timescale: 600) }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 1280)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.08, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.08, preferredTimescale: 600)
        let batch = FrameBatch(count: times.count)
        generator.generateCGImagesAsynchronously(forTimes: times.map { NSValue(time: $0) }) { requested, image, actual, result, _ in
            batch.receive(key: requested.value, image: result == .succeeded ? image : nil, actual: actual.seconds)
        }
        do { try wait(batch.done, control: control, message: "视频抽帧超时") }
        catch { generator.cancelAllCGImageGeneration(); throw error }
        var frames: [VisualFrame] = [], sampled: [Double] = []
        let session = VisionSession()
        for time in times {
            try control?.checkpoint()
            if let decoded = batch.take(time.value) {
                frames.append(try autoreleasepool { try observe(decoded.image, isVideo: true, session: session, control: control) })
                sampled.append(decoded.actual.isFinite ? decoded.actual : time.seconds)
            }
        }
        return decide(frames, times: sampled, isVideo: true)
    }
}

final class VisionSession {
    let classification = VNClassifyImageRequest()
    let faces = VNDetectFaceRectanglesRequest()
    let text = VNRecognizeTextRequest()
    init() {
        text.recognitionLevel = .accurate
        text.recognitionLanguages = ["zh-Hans", "en-US"]
        text.usesLanguageCorrection = false
    }
}

private final class FrameBatch: @unchecked Sendable {
    struct Decoded { let image: CGImage; let actual: Double }
    private let lock = NSLock()
    let done = DispatchSemaphore(value: 0)
    private var remaining: Int
    private var images: [Int64: Decoded] = [:]
    init(count: Int) { remaining = count }
    func receive(key: Int64, image: CGImage?, actual: Double) {
        lock.withLock {
            if let image { images[key] = Decoded(image: image, actual: actual) }
            remaining -= 1
            if remaining == 0 { done.signal() }
        }
    }
    func take(_ key: Int64) -> Decoded? { lock.withLock { images.removeValue(forKey: key) } }
}

private final class DurationLoad: @unchecked Sendable {
    let lock = NSLock()
    let done = DispatchSemaphore(value: 0)
    var value: Double?
    var failure: Error?
}
