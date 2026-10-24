import FrameNestCore
import Foundation

func runSelfTests() throws {
    let fm = FileManager.default
    let base = fm.temporaryDirectory.appendingPathComponent("framenest-check-" + UUID().uuidString)
    try fm.createDirectory(at: base, withIntermediateDirectories: false)
    defer { try? fm.removeItem(at: base) }
    var checks = 0
    func check(_ value: Bool, _ name: String) throws {
        guard value else { throw HelperError.message("检查失败：" + name) }; checks += 1; print("PASS " + name)
    }
    func mustFail(_ name: String, _ body: () throws -> Void) throws {
        do { try body() } catch { checks += 1; print("PASS " + name); return }
        throw HelperError.message("应拒绝但未拒绝：" + name)
    }
    let project = try Organizer.createProject(parent: base, name: "测试项目_20261024", folders: Organizer.defaultFolders)
    try check(Organizer.categories.allSatisfy { fm.fileExists(atPath: project.appendingPathComponent($0).path) }, "全部项目目录生成")
    try mustFail("重名项目不覆盖") { _ = try Organizer.createProject(parent: base, name: project.lastPathComponent, folders: Organizer.defaultFolders) }
    try mustFail("拒绝项目路径穿越") { _ = try Organizer.createProject(parent: base, name: "../outside", folders: Organizer.defaultFolders) }
    try mustFail("拒绝模板路径穿越") { _ = try Organizer.createProject(parent: base, name: "bad", folders: "../outside") }
    let fixtures: [(String, String)] = [
        ("Aroll/口播净版.mov", "02_原始素材/口播"), ("产品Broll/补拍.MP4", "02_原始素材/产品实拍"),
        ("录屏_设置.mp4", "02_原始素材/屏幕录制"), ("啸叫原声片段.wav", "03_音频/配音与现场声"),
        ("BGM重选V12/试听.mp3", "03_音频/BGM"), ("转场音效.wav", "03_音频/音效"),
        ("纹波_透明.mov", "06_工程/动画"), ("热成像_4K.mp4", "06_工程/动画"),
        ("客户反馈修订.md", "08_交付与发布/交付记录"), ("补录口播稿.md", "01_文稿与资料/口播与分镜"),
        ("发布文案.md", "08_交付与发布/发布文案"), ("未知镜头_001.mp4", "09_待确认"),
        ("封面/封面V2.png", "04_图片与封面/封面"), ("字幕V12.srt", "05_字幕"),
        ("功率测试.csv", "01_文稿与资料/实测数据"), ("审片版V2.mp4", "07_导出/预览"),
        ("产品说明书.pdf", "01_文稿与资料/产品资料"),
        ("口播文件夹/审片版V2.mp4", "07_导出/预览"),
        ("口播精剪.mp4", "07_导出/成片"),
        ("BGM/啸叫原声.wav", "03_音频/配音与现场声"),
        ("实拍/纹波_透明.mov", "06_工程/动画"),
        ("发布资料/产品说明书.pdf", "01_文稿与资料/产品资料"),
        ("产品资料/附件.pdf", "01_文稿与资料/产品资料"),
        ("未知用途.pdf", "09_待确认"),
        ("预算.xlsx", "09_待确认"),
        ("KM003C_烤机60W.parquet", "01_文稿与资料/实测数据"),
        ("标准防抖.csv", "06_工程/剪辑"),
        ("Demo_USB-C电源小板.epro2", "06_工程/产品模型与PCB"),
        ("外壳.step", "06_工程/产品模型与PCB"),
        ("充电器.glb", "06_工程/产品模型与PCB"),
        ("SourceHanSansSC-Heavy.otf", "06_工程/字体与设计素材"),
        ("封面V2.psd", "04_图片与封面/封面"),
        ("布局.afdesign", "06_工程/字体与设计素材"),
        ("时间轴.json", "06_工程/动画"),
        ("asr.json", "05_字幕"),
        ("未知.json", "09_待确认"),
        ("render.py", "06_工程/动画"),
        ("verify-seek.cjs", "06_工程/脚本与工具"),
        ("USB_Type-C_Spec_R2.5.zip", "01_文稿与资料/产品资料"),
        ("USB-C电源小板_原生3D.zip", "06_工程/产品模型与PCB"),
        ("素材包.zip", "09_待确认"),
        ("P1002149.wav.txt", "05_字幕"),
        ("产品介绍.pptx", "01_文稿与资料/产品资料")
    ]
    for (name, expected) in fixtures { try check(Organizer.classify(name).0 == expected, name) }
    let source = base.appendingPathComponent("source")
    try fm.createDirectory(at: source, withIntermediateDirectories: false)
    for (name, _) in fixtures {
        let file = source.appendingPathComponent(name)
        try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try ("fixture: " + name).write(to: file, atomically: true, encoding: .utf8)
    }
    let engine = source.appendingPathComponent("HyperFrames数据动画")
    try fm.createDirectory(at: engine, withIntermediateDirectories: false)
    try "{}".write(to: engine.appendingPathComponent("hyperframes.json"), atomically: true, encoding: .utf8)
    try "referenced asset".write(to: engine.appendingPathComponent("asset.png"), atomically: true, encoding: .utf8)
    try fm.createSymbolicLink(at: source.appendingPathComponent("外部链接"), withDestinationURL: base)
    let plan = try Organizer.scan(source, destination: project)
    try check(plan.count == fixtures.count + 1, "工程整体识别且不跟随外部链接")
    try check(plan.allSatisfy { Organizer.safeRelative($0.relative) }, "规范化系统路径后相对路径有效")
    let summary = try Organizer.execute(plan, destination: project) { _ in }
    try check(summary.contains("失败 0 项"), "实际复制成功")
    for item in plan {
        try check(fm.contentsEqual(atPath: item.source.path, andPath: project.appendingPathComponent(item.category).appendingPathComponent(item.relative).path), "原文件保留且复制一致：" + item.relative)
    }
    let second = try Organizer.execute(plan, destination: project) { _ in }
    try check(second.contains("复制 0 项"), "重复执行不重复复制")
    let changed = source.appendingPathComponent("字幕V12.srt")
    try "changed".write(to: changed, atomically: true, encoding: .utf8)
    _ = try Organizer.execute(plan.filter { $0.relative == "字幕V12.srt" }, destination: project) { _ in }
    try check(fm.fileExists(atPath: project.appendingPathComponent("05_字幕/字幕V12__2.srt").path), "同名不同内容加序号")
    let third = try Organizer.execute(plan.filter { $0.relative == "字幕V12.srt" }, destination: project) { _ in }
    try check(third.contains("复制 0 项"), "已加序号的相同副本也跳过")
    try mustFail("拒绝目标嵌套在来源中") { _ = try Organizer.scan(source, destination: source.appendingPathComponent("nested")) }
    try mustFail("拒绝来源嵌套在目标中") { _ = try Organizer.scan(source, destination: base) }
    let linkedRoot = base.appendingPathComponent("linked-project")
    try fm.createDirectory(at: linkedRoot, withIntermediateDirectories: false)
    try fm.createSymbolicLink(at: linkedRoot.appendingPathComponent("08_交付与发布"), withDestinationURL: source)
    try mustFail("拒绝目标链接逃出项目") { _ = try Organizer.execute(plan, destination: linkedRoot) { _ in } }
    let node = base.appendingPathComponent("普通Node工具")
    try fm.createDirectory(at: node, withIntermediateDirectories: false)
    try "{\"name\":\"notes\"}".write(to: node.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
    try check(Organizer.projectCategory(node) == "06_工程/脚本与工具", "普通 Node 项目不误判成剪辑")
    try "{\"dependencies\":{\"remotion\":\"4\"}}".write(to: node.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
    try check(Organizer.projectCategory(node) == "06_工程/动画", "Remotion 项目按清单识别")
    let docPackage = base.appendingPathComponent("产品说明书.pages")
    try fm.createDirectory(at: docPackage, withIntermediateDirectories: false)
    try check(Organizer.projectCategory(docPackage) == "01_文稿与资料/产品资料", "文档包不误判为剪辑工程")
    let cut = base.appendingPathComponent("评测.chatcutproject")
    try fm.createDirectory(at: cut, withIntermediateDirectories: false)
    try check(Organizer.projectCategory(cut) == "06_工程/剪辑", "ChatCut 工程包识别")
    try check(Organizer.fileType("PARQUET").label.contains("PARQUET"), "文件类型标签忽略扩展名大小写")
    let inbox = project.appendingPathComponent(Organizer.inboxFolder)
    try check(fm.fileExists(atPath: inbox.path), "新项目提供待归类入口")
    let incoming = inbox.appendingPathComponent("移动字幕.srt")
    try "1\n00:00:00,000 --> 00:00:01,000\n测试\n".write(to: incoming, atomically: true, encoding: .utf8)
    let intact = inbox.appendingPathComponent("HyperFrames移动工程")
    try fm.createDirectory(at: intact, withIntermediateDirectories: false)
    try "{}".write(to: intact.appendingPathComponent("hyperframes.json"), atomically: true, encoding: .utf8)
    try "asset".write(to: intact.appendingPathComponent("asset.png"), atomically: true, encoding: .utf8)
    let movePlan = try Organizer.scan(inbox, destination: project)
    try check(movePlan.count == 2 && movePlan.contains(where: \.wholeDirectory), "支持项目内部待归类并保留完整工程")
    let moved = try Organizer.executeDetailed(movePlan, destination: project, mode: .move) { _ in }
    try check(moved.moved == 2 && moved.copied == 0 && moved.failed == 0, "移动模式实际移动素材与工程")
    try check(!fm.fileExists(atPath: incoming.path) && !fm.fileExists(atPath: intact.path), "移动成功后来源条目消失")
    try check(fm.fileExists(atPath: project.appendingPathComponent("06_工程/动画/HyperFrames移动工程/asset.png").path), "移动工程包含内部资源")
    let movedTarget = project.appendingPathComponent("05_字幕/移动字幕.srt")
    try fm.copyItem(at: movedTarget, to: incoming)
    let duplicateMove = try Organizer.executeDetailed(Organizer.scan(inbox, destination: project), destination: project, mode: .move) { _ in }
    try check(duplicateMove.skipped == 1 && duplicateMove.moved == 0 && fm.fileExists(atPath: incoming.path), "移动模式重复项跳过并保留来源")
    try "changed caption".write(to: incoming, atomically: true, encoding: .utf8)
    let conflictMove = try Organizer.executeDetailed(Organizer.scan(inbox, destination: project), destination: project, mode: .move) { _ in }
    try check(conflictMove.moved == 1 && !fm.fileExists(atPath: incoming.path) && fm.fileExists(atPath: project.appendingPathComponent("05_字幕/移动字幕__2.srt").path), "移动模式同名不同内容加序号")
    try check((try String(contentsOf: movedTarget, encoding: .utf8)).contains("测试"), "同名冲突不改动已有文件")
    try "source stays".write(to: incoming, atomically: true, encoding: .utf8)
    var unsafePlan = try Organizer.scan(inbox, destination: project)
    unsafePlan[0].category = Organizer.inboxFolder
    let unsafeMove = try Organizer.executeDetailed(unsafePlan, destination: project, mode: .move) { _ in }
    try check(unsafeMove.failed == 1 && fm.fileExists(atPath: incoming.path), "拒绝移动到来源自身且保留文件")
    try check((try String(contentsOf: moved.reportURL, encoding: .utf8)).contains("已移动"), "移动结果写入 Markdown 记录")
    try runVisualSelfTests(base: base, check: check)
    print("ALL \(checks) CHECKS PASSED")
}
