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
    private(set) var items: [OrganizeItem] = []
    private(set) var selectedCount = 0
    private(set) var uncertainCount = 0
    @ObservationIgnored private var itemIndices: [UUID: Int] = [:]
    @ObservationIgnored private var control: OperationControl?
    var workProgress: WorkProgress?
    var stopping = false
    var hasError = false
    var status = "准备好了。先创建项目，或直接选择已有项目整理素材。"
    var busy = false
    var tab = 0
    var finished = false
    var operation = UUID()
    func replaceItems(_ values: [OrganizeItem]) {
        items = values
        itemIndices = Dictionary(uniqueKeysWithValues: values.enumerated().map { ($0.element.id, $0.offset) })
        selectedCount = values.filter(\.selected).count
        uncertainCount = values.filter { $0.category == "09_待确认" }.count
    }
    func item(_ id: UUID) -> OrganizeItem? { itemIndices[id].map { items[$0] } }
    func updateItem(_ value: OrganizeItem) {
        guard let index = itemIndices[value.id] else { return }
        let old = items[index]
        selectedCount += (value.selected ? 1 : 0) - (old.selected ? 1 : 0)
        uncertainCount += (value.category == "09_待确认" ? 1 : 0) - (old.category == "09_待确认" ? 1 : 0)
        items[index] = value
    }
    func selectAll(_ selected: Bool) {
        var updated = items
        for index in updated.indices { updated[index].selected = selected }
        items = updated; selectedCount = selected ? items.count : 0
    }
    func setSelected(_ ids: Set<UUID>, selected: Bool) {
        for id in ids { if var value = item(id) { value.selected = selected; updateItem(value) } }
    }
    func cancel() {
        guard busy else { return }
        stopping = true; control?.cancel()
        status = workProgress?.phase == .organizing ? "正在停止，当前文件处理完成后结束；已归类的文件会保留。" : "正在停止识别与扫描……"
    }
    private func beginOperation(_ message: String) -> OperationControl {
        busy = true; finished = false; hasError = false; stopping = false; workProgress = nil; reportURL = nil; status = message
        let token = UUID(); operation = token
        let worker = OperationControl { [weak self] progress in
            Task { @MainActor in
                guard let self, self.busy, self.operation == token, !self.stopping else { return }
                self.workProgress = progress; self.status = progress.message
            }
        }
        control = worker
        return worker
    }
    private func finishOperation() { operation = UUID(); busy = false; control = nil; workProgress = nil; stopping = false }
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
                destination = url; replaceItems([]); reportURL = nil; finished = false
                let inbox = url.appendingPathComponent(Organizer.inboxFolder)
                if source == nil && FileManager.default.fileExists(atPath: inbox.path) { source = inbox }
            }
        }
    }
    @discardableResult func useSource(_ url: URL) -> Bool {
        guard !busy, url.isFileURL, (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            status = "请拖入一个装有素材的文件夹。"; return false
        }
        source = url; replaceItems([]); reportURL = nil; finished = false; hasError = false
        status = "素材文件夹已选好。点击“一键自动归类”，或先扫描预览。"
        return true
    }
    func create() {
        do {
            destination = try Organizer.createProject(parent: parent, name: projectName, folders: template)
            replaceItems([])
            let inbox = destination!.appendingPathComponent(Organizer.inboxFolder)
            source = FileManager.default.fileExists(atPath: inbox.path) ? inbox : nil
            reportURL = nil
            status = "项目已创建：\(destination!.lastPathComponent)\n把素材放入「00_待归类」，或拖入素材文件夹，再点“一键自动归类”。"
            UserDefaults.standard.set(template, forKey: "folderTemplate")
            finished = true
            tab = 1
        } catch { status = error.localizedDescription; hasError = true; finished = false }
    }
    func scan(automatically: Bool = false) {
        guard let source, let destination else { status = "请先选择素材来源和目标项目。"; return }
        let selectedMode = mode
        let recognize = analyzeContents
        let worker = beginOperation("正在读取文件名与目录结构……")
        replaceItems([])
        Task {
            do {
                let found = try await Task.detached {
                    try Organizer.scan(source, destination: destination, analyzeContents: recognize, control: worker)
                }.value
                try worker.checkpoint()
                replaceItems(found)
                if found.isEmpty { status = "素材文件夹是空的。把文件放进去后，再点击“一键自动归类”。" }
                else if automatically { try await perform(found, destination: destination, mode: selectedMode, control: worker) }
                else { status = "已扫描 \(found.count) 项。可修改归类位置，再点击“归类已选”。" }
            } catch is CancellationError { status = "已停止扫描，素材文件没有改动。" }
            catch { status = error.localizedDescription; hasError = true }
            finishOperation()
        }
    }
    func execute() {
        guard let destination else { return }
        let plan = items
        guard plan.contains(where: \.selected) else { return }
        let selectedMode = mode
        let worker = beginOperation("正在准备归类……")
        Task {
            do { try await perform(plan, destination: destination, mode: selectedMode, control: worker) }
            catch is CancellationError { status = "已停止归类，尚未处理的文件保留在来源。" }
            catch { status = error.localizedDescription; hasError = true }
            finishOperation()
        }
    }
    private func perform(_ plan: [OrganizeItem], destination: URL, mode: OrganizationMode, control: OperationControl) async throws {
        let result = try await Task.detached {
            try Organizer.executeDetailed(plan, destination: destination, mode: mode, control: control) { _ in }
        }.value
        status = result.summary; reportURL = result.reportURL
        finished = result.failed == 0 && !result.cancelled; hasError = result.failed > 0; replaceItems([])
    }
}
