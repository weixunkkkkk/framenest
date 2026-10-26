import Foundation
import FrameNestCore

@MainActor func runPerformanceSelfTests(base: URL, check: (Bool, String) throws -> Void) throws {
    let model = HelperModel()
    let values = (0..<10_000).map { index in
        OrganizeItem(source: base.appendingPathComponent("\(index).mp4"), relative: "\(index).mp4", category: "09_待确认", reason: "测试")
    }
    model.replaceItems(values)
    try check(model.selectedCount == 10_000 && model.uncertainCount == 10_000, "万项素材索引与计数初始化")
    var last = values.last!
    last.selected = false; last.category = "02_原始素材/产品实拍"
    model.updateItem(last)
    try check(model.item(last.id)?.category == last.category && model.selectedCount == 9999 && model.uncertainCount == 9999, "按稳定 ID 修改并增量更新计数")
    model.selectAll(false)
    try check(model.selectedCount == 0 && !model.items.contains(where: \.selected), "万项全不选保持计数一致")
    model.selectAll(true)
    try check(model.selectedCount == 10_000 && model.items.allSatisfy(\.selected), "万项全选保持计数一致")
    model.replaceItems([values[0]])
    model.updateItem(last)
    try check(model.items.count == 1 && model.item(last.id) == nil, "重新扫描后旧行标识不会写入新计划")

    let source = base.appendingPathComponent("cancel-source")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    for index in 1...3 { try Data("fixture \(index)".utf8).write(to: source.appendingPathComponent("字幕\(index).srt")) }
    let project = try Organizer.createProject(parent: base, name: "取消测试", folders: Organizer.defaultFolders)
    let stopped = OperationControl(); stopped.cancel()
    do {
        _ = try Organizer.scan(source, destination: project, control: stopped)
        throw HelperError.message("取消后扫描仍执行")
    } catch is CancellationError { try check(true, "扫描开始前可取消且不改写文件") }
    let plan = try Organizer.scan(source, destination: project)
    let control = OperationControl()
    var callbacks = 0
    let partial = try Organizer.executeDetailed(plan, destination: project, mode: .move, control: control) { _ in
        callbacks += 1
        if callbacks == 2 { control.cancel() }
    }
    try check(partial.cancelled && partial.moved == 1 && partial.failed == 0, "归类在文件边界停止且不误报失败")
    try check(try FileManager.default.contentsOfDirectory(atPath: source.path).count == 2, "停止后未处理素材仍保留在来源")
    let report = try String(contentsOf: partial.reportURL, encoding: .utf8)
    try check(report.components(separatedBy: "- 已移动：").count == 2 && report.contains("已停止"), "停止后增量记录包含已完成条目和状态")
    try check(FileManager.default.fileExists(atPath: project.appendingPathComponent("05_字幕/字幕1.srt").path), "停止后已归类文件保持完整")
    do {
        _ = try VisualClassifier.analyze(source.appendingPathComponent("字幕2.srt"), control: stopped)
        throw HelperError.message("已取消的识别仍执行")
    } catch is CancellationError { try check(true, "视觉识别尊重取消令牌") }
}
