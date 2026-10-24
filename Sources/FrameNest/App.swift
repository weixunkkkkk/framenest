import SwiftUI
import AppKit
import Observation

@Observable @MainActor final class HelperModel {
    var name = ""
    var addDate = true
    var parent = HelperModel.defaultParent()
    var source: URL?
    var destination: URL?
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
        return saved == nil || saved == legacy ? Organizer.defaultFolders : saved!
    }
    var availableCategories: [String] {
        let custom = template.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { Organizer.safeRelative($0) }
        return Array(Set(Organizer.categories + custom)).sorted()
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
            switch kind { case 0: parent = url; case 1: source = url; items = []; default: destination = url; items = [] }
        }
    }
    func create() {
        do {
            destination = try Organizer.createProject(parent: parent, name: projectName, folders: template)
            items = []
            status = "项目已创建：\(destination!.lastPathComponent)\n可以切换到「素材归类」，把素材复制到这个项目。"
            UserDefaults.standard.set(template, forKey: "folderTemplate")
            finished = true
        } catch { status = error.localizedDescription }
    }
    func scan() {
        guard let source, let destination else { status = "请先选择素材来源和目标项目。"; return }
        busy = true; finished = false; status = "正在读取文件名与目录结构……"; items = []
        Task {
            do {
                let found = try await Task.detached { try Organizer.scan(source, destination: destination) }.value
                items = found
                status = "已扫描 \(found.count) 项。检查或修改归类位置后，点击“复制归类”。"
            } catch { status = error.localizedDescription }
            busy = false
        }
    }
    func execute() {
        guard let destination else { return }
        let plan = items
        busy = true; finished = false
        let token = UUID(); operation = token
        Task {
            do {
                status = try await Task.detached {
                    try Organizer.execute(plan, destination: destination) { message in
                        Task { @MainActor in if self.busy && self.operation == token { self.status = message } }
                    }
                }.value
            } catch { status = error.localizedDescription }
            busy = false; finished = true
        }
    }
}
