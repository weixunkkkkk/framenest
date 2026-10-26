import FrameNestCore
import AppKit
import ImageIO
import UniformTypeIdentifiers

func runVisualSelfTests(base: URL, check: (Bool, String) throws -> Void) throws {
    let root = base.appendingPathComponent("visual-check")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    guard let context = CGContext(data: nil, width: 1280, height: 720, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw HelperError.message("Cannot create visual test fixture")
    }
    func save(_ image: CGImage, name: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        guard let output = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw HelperError.message("Cannot write image fixture")
        }
        CGImageDestinationAddImage(output, image, nil)
        guard CGImageDestinationFinalize(output) else { throw HelperError.message("Cannot finish image fixture") }
        return url
    }
    context.setFillColor(NSColor.white.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: 1280, height: 720))
    context.setFillColor(NSColor(white: 0.9, alpha: 1).cgColor)
    context.fill(CGRect(x: 0, y: 650, width: 1280, height: 70))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    let rows = ["Finder   File Edit View Window Help", "https://example.test/project", "Project files", "Name                  Date modified          Size", "C0001.mp4             2026-10-24             10 MB", "C0002.mp4             2026-10-24             20 MB", "IMG_0001.png          2026-10-24              2 MB", "script.md             2026-10-24              1 KB", "captions.srt          2026-10-24              1 KB"]
    for (index, row) in rows.enumerated() {
        (row as NSString).draw(at: CGPoint(x: 45, y: 675 - index * 65), withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 25, weight: .regular), .foregroundColor: NSColor.black])
    }
    NSGraphicsContext.restoreGraphicsState()
    let screenshot = try save(context.makeImage()!, name: "IMG_0001.png")
    let before = try Data(contentsOf: screenshot)
    let analyzed = VisualClassifier.analyze(screenshot, useCache: false)
    try check(analyzed.labels.contains { ["document", "screenshot"].contains($0.name) }, "默认命名图片通过真实视觉模型读取出文档或界面内容")
    try check(analyzed.framesAnalyzed == 1 && analyzed.engine == "Apple Vision", "识别结果包含引擎与实际帧数")
    try check(analyzed.sampledTimes.isEmpty && analyzed.status != "unavailable", "图片识别不伪造视频采样时间")
    try check(try Data(contentsOf: screenshot) == before, "画面识别不修改原图")
    context.setFillColor(NSColor.blue.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: 1280, height: 720))
    let plain = try save(context.makeImage()!, name: "IMG_0002.png")
    let unknown = VisualClassifier.analyze(plain, useCache: false)
    try check(unknown.category == nil && unknown.status == "uncertain", "纯色图片不会强行归类")
    let broken = root.appendingPathComponent("IMG_0003.png")
    try Data("not an image".utf8).write(to: broken)
    let failed = VisualClassifier.analyze(broken, useCache: false)
    try check(failed.category == nil && failed.status == "unavailable", "损坏图片保留待确认")
    let named = OrganizeItem(source: screenshot, relative: "产品原图.png", category: "04_图片与封面/产品原图", reason: "明确名称")
    let unchanged = try VisualClassifier.refine([named], useCache: false)
    try check(unchanged[0].category == named.category && unchanged[0].visualAnalysis == nil, "画面识别保留明确的名称分类")
    let directory = OrganizeItem(source: root, relative: "HyperFrames工程", category: "06_工程/动画", reason: "完整工程", wholeDirectory: true)
    try check(!VisualClassifier.eligible(directory), "完整工程不会展开做画面识别")
}
