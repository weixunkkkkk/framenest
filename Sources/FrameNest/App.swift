import FrameNestCore
import SwiftUI
import AppKit
import Observation

@Observable @MainActor final class HelperModel {
    var name = ""
    var addDate = true
    var parent = HelperModel.defaultParent()
    var source: URL?
    var destination: URL?
    var mode: OrganizationMode = .move
    var analyzeContents = true
    var reportURL: URL?
    var template = HelperModel.loadTemplate()
    var items: [OrganizeItem] = []
    var status = "准备好了。先创建项目，或直接选择已有项目整理素材。"
    var busy = false
    var tab = 0
    var finished = false
    var operation = UUID()
    static func defaultParent() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [home.appendingPathComponent("Documents/video"), home.appendingPathComponent("Movies"), home.appendingPathComponent("Documents"), home]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) } ?? home
    }
    static func loadTemplate() -> String {
        let saved = UserDefaults.standard.string(forKey: "folderTemplate")
        let legacy = Array(Organizer.categories.prefix(20)).joined(separator: "\n")
        return saved == nil || saved == legacy || saved == Organizer.categories.sorted().joined(separator: "\n") ? Organizer.defaultFolders : saved!
    }
    var availableCategories: [String] {
        let custom = template.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { Organizer.safeRelative($0) }
        return Array(Set(Organizer.categories + custom)).filter { $0 != Organizer.inboxFolder && !$0.hasPrefix(Organizer.inboxFolder + "/") }.sorted()
    }
    var projectName: String {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd"
        return n.isEmpty ? "" : n + (addDate ? "_" + f.string(from: Date()) : "")
    }
    func pick(_ kind: Int) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false; panel.canCreateDirectories = true
        panel.prompt = "选择文件夹"
        panel.message = kind == 0 ? "新项目保存在哪里？" : kind == 1 ? "选择要归类的素材文件夹" : "选择接收素材的项目文件夹"
        panel.directoryURL = parent
        if panel.runModal() == .OK, let url = panel.url {
            switch kind {
            case 0: parent = url
            case 1: _ = useSource(url)
            default:
                destination = url; items = []; reportURL = nil; finished = false
                let inbox = url.appendingPathComponent(Organizer.inboxFolder)
                if source == nil && FileManager.default.fileExists(atPath: inbox.path) { source = inbox }
            }
        }
    }
    @discardableResult func useSource(_ url: URL) -> Bool {
        guard !busy, url.isFileURL, (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            status = "请拖入一个装有素材的文件夹。"; return false
        }
        source = url; items = []; reportURL = nil; finished = false
        status = "素材文件夹已选好。点击“一键自动归类”，或先扫描预览。"
        return true
    }
    func create() {
        do {
            destination = try Organizer.createProject(parent: parent, name: projectName, folders: template)
            items = []
            let inbox = destination!.appendingPathComponent(Organizer.inboxFolder)
            source = FileManager.default.fileExists(atPath: inbox.path) ? inbox : nil
            reportURL = nil
            status = "项目已创建：\(destination!.lastPathComponent)\n把素材放入「00_待归类」，或拖入素材文件夹，再点“一键自动归类”。"
            UserDefaults.standard.set(template, forKey: "folderTemplate")
            finished = true
            tab = 1
        } catch { status = error.localizedDescription }
    }
    func scan(automatically: Bool = false) {
        guard let source, let destination else { status = "请先选择素材来源和目标项目。"; return }
        let selectedMode = mode
        let recognize = analyzeContents
        let token = UUID(); operation = token
        busy = true; finished = false; reportURL = nil; status = "正在读取文件名与目录结构……"; items = []
        Task {
            do {
                let found = try await Task.detached {
                    try Organizer.scan(source, destination: destination, analyzeContents: recognize) { message in
                        Task { @MainActor in if self.busy && self.operation == token { self.status = message } }
                    }
                }.value
                operation = UUID()
                items = found
                if found.isEmpty { status = "素材文件夹是空的。把文件放进去后，再点击“一键自动归类”。" }
                else if automatically { try await perform(found, destination: destination, mode: selectedMode) }
                else { status = "已扫描 \(found.count) 项。可修改归类位置，再点击“归类已选”。" }
            } catch { status = error.localizedDescription }
            busy = false
        }
    }
    func execute() {
        guard let destination else { return }
        let plan = items
        guard plan.contains(where: \.selected) else { return }
        let selectedMode = mode
        busy = true; finished = false; reportURL = nil
        Task {
            do { try await perform(plan, destination: destination, mode: selectedMode) }
            catch { status = error.localizedDescription }
            busy = false
        }
    }
    private func perform(_ plan: [OrganizeItem], destination: URL, mode: OrganizationMode) async throws {
        let token = UUID(); operation = token
        let result = try await Task.detached {
            try Organizer.executeDetailed(plan, destination: destination, mode: mode) { message in
                Task { @MainActor in if self.busy && self.operation == token { self.status = message } }
            }
        }.value
        operation = UUID()
        status = result.summary; reportURL = result.reportURL
        finished = result.failed == 0; items = []
    }
}
