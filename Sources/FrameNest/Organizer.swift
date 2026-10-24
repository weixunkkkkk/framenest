import Foundation

struct OrganizeItem: Identifiable {
    let id = UUID()
    let source: URL
    let relative: String
    var category: String
    var reason: String
    var selected = true
    var wholeDirectory = false
    var typeInfo: (label: String, icon: String) { Organizer.fileType(source.pathExtension, directory: wholeDirectory) }
}

enum HelperError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}

enum Organizer {
    static let fm = FileManager.default
    static let categories = [
        "01_文稿与资料/口播与分镜", "01_文稿与资料/产品资料", "01_文稿与资料/实测数据",
        "02_原始素材/口播", "02_原始素材/产品实拍", "02_原始素材/屏幕录制",
        "03_音频/配音与现场声", "03_音频/BGM", "03_音频/音效",
        "04_图片与封面/产品原图", "04_图片与封面/截图", "04_图片与封面/封面",
        "05_字幕", "06_工程/剪辑", "06_工程/动画", "07_导出/预览", "07_导出/成片",
        "08_交付与发布/发布文案", "08_交付与发布/交付记录", "09_待确认",
        "06_工程/产品模型与PCB", "06_工程/字体与设计素材", "06_工程/脚本与工具"
    ]
    static let defaultFolders = categories.sorted().joined(separator: "\n")
    static func fail(_ s: String) throws -> Never { throw HelperError.message(s) }
    static func safeRelative(_ s: String) -> Bool {
        !s.isEmpty && !s.hasPrefix("/") && !s.contains("\\") && !s.contains(":") && !s.contains("\0") &&
        s.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
    static func createProject(parent: URL, name: String, folders: String) throws -> URL {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard safeRelative(clean), !clean.contains("/"), !clean.hasPrefix(".") else { try fail("项目名不能留空，也不能包含 /、\\、: 或 .. 路径。") }
        let paths = folders.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !paths.isEmpty, paths.allSatisfy(safeRelative) else { try fail("目录模板每行填写一个相对路径，例如：02_原始素材/口播。") }
        guard fm.fileExists(atPath: parent.path) else { try fail("保存位置不存在，请重新选择。") }
        let root = parent.appendingPathComponent(clean, isDirectory: true)
        guard !fm.fileExists(atPath: root.path) else { try fail("同名项目已存在，请换一个名字。已有文件不会被覆盖。") }
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        for path in paths { try fm.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true) }
        let note = "# \(clean)\n\n创建时间：\(Date().formatted(date: .numeric, time: .shortened))\n\n按视频制作工作流创建。原始素材、实测数据、工程、导出与发布记录分别保存。成片导出不代表已经发布。\n\n## 目录\n\n" + paths.map { "- `\($0)`" }.joined(separator: "\n") + "\n"
        try note.write(to: root.appendingPathComponent("项目说明.md"), atomically: true, encoding: .utf8)
        return root
    }
    static let videos: Set<String> = ["mp4", "mov", "mkv", "mxf", "avi", "webm", "mts", "m2ts", "r3d", "braw", "m4v", "insv", "360"]
    static let audios: Set<String> = ["wav", "mp3", "m4a", "aac", "aiff", "aif", "flac", "ogg", "opus", "wma"]
    static let images: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "webp", "tif", "tiff", "gif", "svg", "avif", "exr", "dpx"]
    static let rawPhotos: Set<String> = ["dng", "cr2", "cr3", "arw", "nef", "raf", "rw2", "orf"]
    static let docs: Set<String> = ["md", "txt", "pdf", "doc", "docx", "pages", "ppt", "pptx", "key", "rtf", "html"]
    static let code: Set<String> = ["py", "js", "mjs", "cjs", "jsx", "tsx", "ts", "css", "sh", "swift", "html"]
    static let data: Set<String> = ["csv", "tsv", "xlsx", "xls", "numbers", "parquet", "feather", "arrow"]
    static let models: Set<String> = ["glb", "gltf", "fbx", "obj", "stl", "step", "stp", "iges", "igs", "usd", "usdz", "epro", "epro2", "kicad_pro", "kicad_pcb", "kicad_sch", "schdoc", "pcbdoc", "gerber"]
    static let animationProjects: Set<String> = ["aep", "aepx", "blend", "blend1", "c4d", "hip", "hipnc", "motn"]
    static let editProjects: Set<String> = ["prproj", "drp", "dra", "fcpxml", "fcpbundle", "chatcutproject", "veg", "edl"]
    static let fonts: Set<String> = ["ttf", "otf", "woff", "woff2", "ttc"]
    static let design: Set<String> = ["psd", "psb", "ai", "afdesign", "afphoto", "sketch", "fig", "xd"]
    static let subtitles: Set<String> = ["srt", "ass", "ssa", "vtt", "sbv", "lrc"]
    static let archives: Set<String> = ["zip", "7z", "rar", "tar", "gz"]
    static func fileType(_ ext: String, directory: Bool = false) -> (label: String, icon: String) {
        let ext = ext.lowercased()
        if directory { return ("完整目录 / 文件包", "folder.fill") }
        if videos.contains(ext) { return ("视频 · \(ext.uppercased())", "film") }
        if audios.contains(ext) { return ("音频 · \(ext.uppercased())", "waveform") }
        if subtitles.contains(ext) { return ("字幕 · \(ext.uppercased())", "captions.bubble") }
        if models.contains(ext) { return ("模型 / PCB · \(ext.uppercased())", "cube.transparent") }
        if animationProjects.contains(ext) || editProjects.contains(ext) { return ("工程 · \(ext.uppercased())", "slider.horizontal.3") }
        if fonts.contains(ext) { return ("字体 · \(ext.uppercased())", "textformat") }
        if design.contains(ext) { return ("设计源文件 · \(ext.uppercased())", "square.stack.3d.up") }
        if images.contains(ext) || rawPhotos.contains(ext) { return ("图片 · \(ext.uppercased())", "photo") }
        if data.contains(ext) { return ("数据表 · \(ext.uppercased())", "tablecells") }
        if archives.contains(ext) { return ("压缩包 · \(ext.uppercased())", "doc.zipper") }
        if code.contains(ext) { return ("脚本 · \(ext.uppercased())", "chevron.left.forwardslash.chevron.right") }
        if docs.contains(ext) { return ("文档 · \(ext.uppercased())", "doc.text") }
        return (ext.isEmpty ? "未知类型" : ext.uppercased(), "doc")
    }
    static func classify(_ relative: String, directory: Bool = false) -> (String, String) {
        let parts = relative.lowercased().split(separator: "/").map(String.init)
        let leaf = parts.last ?? relative.lowercased()
        let ext = (leaf as NSString).pathExtension
        func has(_ s: String, _ words: [String]) -> Bool { words.contains { s.contains($0) } }
        if directory {
            if has(leaf, ["pcb", "easyeda", "嘉立创", "电源小板"]) { return (categories[20], "产品模型 / PCB 工程整体保留") }
            return (has(leaf, ["hyperframes", "blender", "动画", "motion", "3d", "remotion"]) ? categories[14] : categories[22], "工程目录整体保留")
        }
        if subtitles.contains(ext) { return (categories[12], "字幕格式") }
        if editProjects.contains(ext) { return (categories[13], "剪辑工程格式") }
        if animationProjects.contains(ext) { return (categories[14], "动画工程格式") }
        if models.contains(ext) { return (categories[20], "产品模型 / PCB 格式") }
        if fonts.contains(ext) { return (categories[21], "字体文件") }
        if ext == "txt", let originalExt = leaf.dropLast(4).split(separator: ".").last,
           audios.contains(String(originalExt)) || videos.contains(String(originalExt)) {
            return (categories[12], "音视频转写文本")
        }
        let scopes = [leaf] + Array(parts.dropLast().reversed())
        for (index, text) in scopes.enumerated() {
            let basis = index == 0 ? "文件名" : "所在目录"
            func hit(_ words: [String]) -> Bool { has(text, words) }
            if videos.contains(ext) {
                if hit(["aroll", "a-roll", "口播净版", "净口播", "原始口播"]) { return (categories[3], basis + "：口播原片 / A-roll") }
                if hit(["预览", "审片", "preview", "试听"]) { return (categories[15], basis + "：预览 / 审片") }
                if hit(["成片", "精剪", "初剪", "定稿", "交付", "导出", "配乐版", "混音版", "final"]) { return (categories[16], basis + "：剪辑版本 / 成片") }
                if hit(["录屏", "screenrecord", "screen_record", "screen recording"]) { return (categories[5], basis + "：屏幕录制") }
                if hit(["烤机", "纹波", "热成像", "曲线", "动效", "动画", "hyperframes", "motion", "透明叠加"]) { return (categories[14], basis + "：数据可视化 / 动画素材") }
                if hit(["口播", "补录"]) { return (categories[3], basis + "：口播") }
                if hit(["broll", "b-roll", "空镜", "产品实拍", "实拍", "开箱", "补拍"]) { return (categories[4], basis + "：产品实拍 / B-roll") }
            } else if audios.contains(ext) {
                if hit(["啸叫", "底噪", "采样", "原声", "现场", "配音", "口播", "人声", "旁白", "voice", "录音"]) { return (categories[6], basis + "：人声 / 现场证据音") }
                if hit(["sfx", "音效", "whoosh", "转场声", "落点"]) { return (categories[8], basis + "：音效") }
                if hit(["bgm", "配乐", "音乐", "music", "bpm", "循环"]) { return (categories[7], basis + "：BGM / 配乐") }
                if hit(["混音", "审片", "final", "导出"]) { return (categories[15], basis + "：混音 / 试听导出") }
            } else if images.contains(ext) || rawPhotos.contains(ext) || design.contains(ext) {
                if hit(["封面", "cover", "thumbnail"]) { return (categories[11], basis + "：封面") }
                if hit(["截图", "截屏", "screen", "评论", "反馈", "协议", "纹波", "热成像", "烤机", "曲线", "检查", "核验"]) { return (categories[10], basis + "：截图 / 测试证据图") }
                if hit(["产品", "原图", "抠图", "实拍", "渲染"]) { return (categories[9], basis + "：产品原图") }
                if hit(["动画", "hyperframes", "blender", "frames", "序列帧"]) { return (categories[14], basis + "：动画图片素材") }
            } else if data.contains(ext) || ["json", "jsonl", "log", "wts"].contains(ext) {
                if hit(["防抖", "轨迹", "gyro", "stabili"]) { return (categories[13], basis + "：防抖 / 剪辑辅助数据") }
                if hit(["烤机", "测试", "实测", "测量", "功率", "电压", "电流", "km003", "power-z", "纹波", "温度", "thermal"]) { return (categories[2], basis + "：实测数据") }
                if hit(["动画", "hyperframes", "blender", "timing", "keyframe", "beats", "scene", "timeline", "时间轴"]) { return (categories[14], basis + "：动画 / 时间线数据") }
                if hit(["交付", "检查", "核验", "解码", "验证", "render.log", "progress.log"]) { return (categories[18], basis + "：制作 / 检查记录") }
                if hit(["参数", "产品", "规格", "brief", "datasheet"]) { return (categories[1], basis + "：产品资料") }
                if hit(["asr", "transcript", "whisper", "转写", "字幕"]) { return (categories[12], basis + "：字幕转写数据") }
            } else if docs.contains(ext) || archives.contains(ext) {
                if hit(["发布", "标题", "简介", "抖音", "小红书"]) { return (categories[17], basis + "：发布文案") }
                if hit(["说明书", "规格书", "官方参数", "datasheet", "usb_type", "usb_2.0", "usb_20", "specification", "ifixit"]) { return (categories[1], basis + "：产品规格 / 官方资料") }
                if hit(["交付", "检查", "审查", "核验", "修订", "记录", "说明", "反馈", "交接"]) { return (categories[18], basis + "：交付 / 修改记录") }
                if hit(["口播", "文稿", "稿件", "分镜", "脚本", "剪后", "剪辑时间表", "镜头表"]) { return (categories[0], basis + "：口播 / 分镜") }
                if hit(["产品", "参数", "官方", "资料", "brief", "规格", "手册", "manual"]) { return (categories[1], basis + "：产品资料") }
                if hit(["原生3d", "模型", "pcb", "easyeda", "嘉立创"]) { return (categories[20], basis + "：模型 / PCB 资料包") }
            } else if code.contains(ext) && hit(["动画", "hyperframes", "blender", "motion", "render", "shader"]) {
                return (categories[14], basis + "：动画源代码")
            }
        }
        if rawPhotos.contains(ext) { return (categories[9], "相机 RAW 图片") }
        if audios.contains(ext) && has(leaf, ["试听", "预览"]) { return (categories[15], "音频试听 / 预览") }
        if design.contains(ext) || ext == "svg" { return (categories[21], "设计 / 矢量源文件") }
        if code.contains(ext) { return (categories[22], "脚本 / 网页源文件") }
        if ["parquet", "feather", "arrow"].contains(ext) { return (categories[2], "列式数据文件") }
        return (categories[19], "用途不明确，需确认")
    }
    static func projectCategory(_ url: URL) -> String? {
        let names = (try? fm.contentsOfDirectory(atPath: url.path)) ?? []
        let lower = names.map { $0.lowercased() }
        let ext = url.pathExtension.lowercased()
        if ["fcpbundle", "dra", "chatcutproject", "logicx", "band"].contains(ext) { return categories[13] }
        if ["pages", "key", "numbers"].contains(ext) { return classify(url.lastPathComponent).0 }
        if lower.contains("draft_content.json") || lower.contains("draft_info.json") { return categories[13] }
        if lower.contains("hyperframes.json") { return categories[14] }
        let folderName = url.lastPathComponent.lowercased()
        if folderName.contains("blender") && (lower.contains("scenes") || lower.contains(where: { $0.hasSuffix(".blend") || $0.hasSuffix(".py") })) { return categories[14] }
        if lower.contains(where: { $0.hasSuffix(".prproj") || $0.hasSuffix(".drp") }) { return categories[13] }
        if lower.contains(where: { $0.hasSuffix(".blend") || $0.hasSuffix(".aep") }) && lower.contains(where: { ["assets", "textures", "贴图"].contains($0) }) { return categories[14] }
        if lower.contains("package.json") {
            let manifest = (try? String(contentsOf: url.appendingPathComponent("package.json"), encoding: .utf8))?.lowercased() ?? ""
            return ["hyperframes", "remotion", "gsap", "three"].contains(where: manifest.contains) ? categories[14] : categories[22]
        }
        return nil
    }
    static func scan(_ source: URL, destination: URL) throws -> [OrganizeItem] {
        let source = source.resolvingSymlinksInPath().standardizedFileURL
        let src = source.path
        let dst = destination.resolvingSymlinksInPath().standardizedFileURL.path
        guard src != dst, !dst.hasPrefix(src + "/"), !src.hasPrefix(dst + "/") else { try fail("素材来源和目标项目不能相同或互相包含，请选择另一个位置。") }
        if let category = projectCategory(source) { return [.init(source: source, relative: source.lastPathComponent, category: category, reason: "完整工程目录，保留内部引用", wholeDirectory: true)] }
        var items: [OrganizeItem] = []
        var scanError: Error?
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]
        guard let en = fm.enumerator(at: source, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles], errorHandler: { _, err in scanError = err; return false }) else { try fail("无法读取素材文件夹。") }
        for case let url as URL in en {
            let r = try url.resourceValues(forKeys: Set(keys))
            if r.isSymbolicLink == true { continue }
            let canonical = url.resolvingSymlinksInPath().standardizedFileURL
            let relative = canonical.pathComponents.dropFirst(source.pathComponents.count).joined(separator: "/")
            guard safeRelative(relative) else { try fail("无法确定文件的相对路径：\(url.lastPathComponent)") }
            if r.isDirectory == true {
                if ["node_modules", "__pycache__", "cache", "caches"].contains(url.lastPathComponent.lowercased()) { en.skipDescendants(); continue }
                if projectCategory(url) != nil || r.isPackage == true {
                    if url.pathExtension.lowercased() == "app" { en.skipDescendants(); continue }
                    let category = projectCategory(url) ?? classify(relative).0
                    items.append(.init(source: url, relative: relative, category: category, reason: "完整工程 / 文件包，保留内部引用", wholeDirectory: true)); en.skipDescendants()
                }
                continue
            }
            let c = classify(relative)
            items.append(.init(source: url, relative: relative, category: c.0, reason: c.1))
        }
        if let e = scanError { throw e }
        return items.sorted { $0.relative.localizedStandardCompare($1.relative) == .orderedAscending }
    }
    static func ensureInside(_ url: URL, root: URL) throws {
        var ancestor = url.standardizedFileURL
        var missing: [String] = []
        while !fm.fileExists(atPath: ancestor.path), ancestor.path != "/" {
            if (try? fm.attributesOfItem(atPath: ancestor.path)[.type] as? FileAttributeType) == .typeSymbolicLink {
                try fail("目标目录包含不可用的链接，请选择普通文件夹。")
            }
            missing.insert(ancestor.lastPathComponent, at: 0)
            ancestor.deleteLastPathComponent()
        }
        var resolved = ancestor.resolvingSymlinksInPath().standardizedFileURL
        for component in missing { resolved.appendPathComponent(component) }
        let target = resolved.path
        let base = root.resolvingSymlinksInPath().standardizedFileURL.path
        guard target.hasPrefix(base + "/") else { try fail("目标目录包含指向项目外的链接，请换一个目标项目。") }
    }
    static func execute(_ items: [OrganizeItem], destination: URL, progress: (String) -> Void) throws -> String {
        var copied = 0, skipped = 0, failed = 0
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let logs = destination.appendingPathComponent("08_交付与发布/整理记录", isDirectory: true)
        try ensureInside(logs, root: destination)
        try fm.createDirectory(at: logs, withIntermediateDirectories: true)
        let report = logs.appendingPathComponent("素材归类_\(stamp)_\(UUID().uuidString.prefix(6)).md")
        var lines = ["# 素材归类记录", "", "方式：复制归类。原文件保留，保留原子文件夹结构；同名内容相同则跳过，不同则加序号。", ""]
        let selected = items.filter(\.selected)
        for (index, item) in selected.enumerated() {
            progress("正在整理 \(index + 1)/\(selected.count)：\(item.source.lastPathComponent)")
            do {
                guard safeRelative(item.category), safeRelative(item.relative) else { try fail("无效的目标路径。") }
                let base = destination.appendingPathComponent(item.category).appendingPathComponent(item.relative)
                try ensureInside(base, root: destination)
                var target = base
                var n = 2
                var duplicate = false
                while fm.fileExists(atPath: target.path) {
                    if fm.contentsEqual(atPath: item.source.path, andPath: target.path) { duplicate = true; break }
                    let stem = base.deletingPathExtension().lastPathComponent
                    let suffix = base.pathExtension.isEmpty ? "" : "." + base.pathExtension
                    target = base.deletingLastPathComponent().appendingPathComponent("\(stem)__\(n)\(suffix)")
                    n += 1
                }
                if duplicate { skipped += 1; lines.append("- 跳过相同内容：`\(item.source.path)` → `\(target.path)`") }
                else {
                    try ensureInside(target, root: destination)
                    try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.copyItem(at: item.source, to: target)
                    copied += 1; lines.append("- 已复制：`\(item.source.path)` → `\(target.path)`")
                }
            } catch { failed += 1; lines.append("- 失败：`\(item.source.path)`；\(error.localizedDescription)") }
            try lines.joined(separator: "\n").write(to: report, atomically: true, encoding: .utf8)
        }
        let summary = "完成：复制 \(copied) 项，跳过重复 \(skipped) 项，失败 \(failed) 项。"
        lines.append("\n" + summary)
        try lines.joined(separator: "\n").write(to: report, atomically: true, encoding: .utf8)
        return summary + "\n归类记录已保存在「08_交付与发布/整理记录」。"
    }
}
