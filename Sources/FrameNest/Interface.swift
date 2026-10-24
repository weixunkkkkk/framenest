import FrameNestCore
import SwiftUI
import AppKit

enum Palette {
    static let accent = Color(red: 0.28, green: 0.38, blue: 0.88)
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)
    static func icon(_ path: String) -> String {
        switch String(path.prefix(2)) {
        case "01": return "doc.text"
        case "02": return "video"
        case "03": return "waveform"
        case "04": return "photo.on.rectangle"
        case "05": return "captions.bubble"
        case "06": return "cube.transparent"
        case "07": return "arrow.up.right.video"
        case "08": return "paperplane"
        default: return "questionmark.folder"
        }
    }
}

struct Panel<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                if !subtitle.isEmpty { Text(subtitle).font(.callout).foregroundStyle(.secondary) }
            }
            content()
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary))
    }
}

struct AppMark: View {
    let size: CGFloat
    var body: some View {
        Group {
            if let icon = NSImage(contentsOf: Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/AppIcon.png")) {
                Image(nsImage: icon).resizable().interpolation(.high)
            } else {
                Image(systemName: "folder.badge.gearshape").resizable().scaledToFit().padding(6).foregroundStyle(Palette.accent)
            }
        }.frame(width: size, height: size)
    }
}

struct ContentView: View {
    @State private var model = HelperModel()
    var body: some View {
        HStack(spacing: 0) {
            Sidebar(model: model).frame(width: 202)
            Divider()
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(["新建项目", "素材归类", "分类规则"][model.tab]).font(.system(size: 27, weight: .bold))
                        Text(["按你的制作习惯，准备好每个项目。", "素材放进一个文件夹，点一次就能归类。", "针对科技评测、产品实拍与动画制作。"][model.tab]).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label("本地处理", systemImage: "internaldrive").font(.caption).foregroundStyle(.secondary)
                }
                Group {
                    switch model.tab {
                    case 0: NewProjectView(model: model)
                    case 1: ImportView(model: model)
                    default: RulesView()
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                StatusBar(model: model)
            }.padding(24).frame(minWidth: 800).background(Palette.canvas)
        }.tint(Palette.accent).frame(minWidth: 1050, minHeight: 740)
    }
}

struct Sidebar: View {
    @Bindable var model: HelperModel
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(spacing: 9) {
                AppMark(size: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text("FrameNest").font(.headline)
                    Text("影巢 · 视频项目助手").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.top, 12)
            VStack(spacing: 7) {
                nav("新建项目", icon: "folder.badge.plus", tag: 0)
                nav("素材归类", icon: "square.stack.3d.up", tag: 1)
                nav("分类规则", icon: "slider.horizontal.3", tag: 2)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 9) {
                Text("你的制作流程").font(.caption.bold()).foregroundStyle(.secondary)
                Label("文稿 → 拍摄 → 剪辑", systemImage: "video")
                Label("实测 → 动画 → 交付", systemImage: "chart.xyaxis.line")
            }.font(.caption).foregroundStyle(.secondary)
            Divider()
            Label("移动 / 复制可选", systemImage: "folder.badge.gearshape").font(.caption).foregroundStyle(.secondary)
            Text("1.4.0 · 开源视频项目助手").font(.caption2).foregroundStyle(.tertiary)
        }.padding(18).background(Palette.accent.opacity(0.045)).disabled(model.busy)
    }
    private func nav(_ title: String, icon: String, tag: Int) -> some View {
        Button { model.tab = tag } label: {
            Label(title, systemImage: icon).font(.system(size: 14, weight: model.tab == tag ? .semibold : .regular))
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 12)
                .foregroundStyle(model.tab == tag ? Palette.accent : .primary)
                .background(model.tab == tag ? Palette.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain).accessibilityAddTraits(model.tab == tag ? .isSelected : [])
    }
}

struct PathPicker: View {
    let title: String
    let url: URL?
    let action: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill").font(.title3).foregroundStyle(Palette.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(url.map { $0.path.replacingOccurrences(of: NSHomeDirectory(), with: "~", options: [.anchored]) } ?? "点击右侧选择文件夹").font(.callout).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button("选择…", action: action)
                .accessibilityLabel("选择" + title)
        }.padding(12).background(Palette.accent.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct NewProjectView: View {
    @Bindable var model: HelperModel
    @State private var editTemplate = false
    var body: some View {
        VStack(spacing: 16) {
            Panel(title: "1. 项目信息", subtitle: "使用“产品名_制作阶段”命名，方便按产品找到工程。") {
                HStack {
                    TextField("例如：产品X_开箱精剪", text: $model.name).textFieldStyle(.roundedBorder).controlSize(.large)
                    Toggle("加今天日期", isOn: $model.addDate).toggleStyle(.checkbox)
                }
                Text(model.projectName.isEmpty ? "文件夹名预览：产品名_制作阶段_日期" : "文件夹名预览：" + model.projectName)
                    .font(.caption).foregroundStyle(.secondary)
                PathPicker(title: "保存位置", url: model.parent) { model.pick(0) }
            }
            Panel(title: "2. 项目目录预览", subtitle: "文稿、实拍、实测、工程和交付各有位置。") {
                HStack {
                    Label("科技评测模板", systemImage: "square.grid.2x2").font(.callout)
                    Spacer()
                    Button("编辑模板…") { editTemplate = true }
                }
                FolderTree(template: model.template).frame(maxHeight: .infinity)
            }.frame(maxHeight: .infinity)
            HStack {
                Text("模板可以改名、增删，并保存为下次的默认目录。").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { model.create() } label: { Label("创建项目文件夹", systemImage: "folder.badge.plus") }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(model.projectName.isEmpty)
            }
        }.disabled(model.busy)
            .sheet(isPresented: $editTemplate) { TemplateEditor(model: model) }
    }
}

struct FolderTree: View {
    let template: String
    private var groups: [(String, [String])] {
        let paths = template.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let grouped = Dictionary(grouping: paths) { $0.components(separatedBy: "/")[0] }
        return grouped.keys.sorted().map { key in
            (key, grouped[key]!.compactMap { path in
                let parts = path.components(separatedBy: "/"); return parts.count > 1 ? parts.dropFirst().joined(separator: "/") : nil
            })
        }
    }
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(groups, id: \.0) { group in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: Palette.icon(group.0)).frame(width: 24).foregroundStyle(Palette.accent)
                        Text(group.0).font(.callout.weight(.medium)).frame(width: 158, alignment: .leading)
                        Text(group.1.isEmpty ? "独立目录" : group.1.joined(separator: "  /  ")).font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(.vertical, 10)
                    Divider()
                }
            }
        }
    }
}

struct TemplateEditor: View {
    @Bindable var model: HelperModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("编辑你的目录模板").font(.title2.bold())
            Text("每行一个目录，/ 表示子目录。修改只应用于之后新建的项目。").foregroundStyle(.secondary)
            TextEditor(text: $draft).font(.system(size: 13, design: .monospaced)).padding(8).border(.quaternary)
            HStack {
                Button("恢复默认模板") { draft = Organizer.defaultFolders }
                Spacer()
                Button("取消") { dismiss() }
                Button("保存模板") {
                    let paths = draft.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    guard !paths.isEmpty && paths.allSatisfy(Organizer.safeRelative) else { model.status = "模板路径无效，请使用“主目录/子目录”的格式。"; return }
                    model.template = paths.joined(separator: "\n")
                    UserDefaults.standard.set(model.template, forKey: "folderTemplate")
                    model.status = "模板已保存。"; dismiss()
                }.buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width: 660, height: 630).onAppear { draft = model.template }
    }
}

struct ImportView: View {
    @Bindable var model: HelperModel
    @State private var query = ""
    @State private var onlyUncertain = false
    @State private var dropTarget = false
    private var visible: [OrganizeItem] {
        model.items.filter { (!onlyUncertain || $0.category == "09_待确认") && (query.isEmpty || $0.relative.localizedCaseInsensitiveContains(query) || $0.category.localizedCaseInsensitiveContains(query)) }
    }
    private func binding(_ item: OrganizeItem) -> Binding<OrganizeItem> {
        Binding(get: { model.items.first(where: { $0.id == item.id }) ?? item }, set: { updated in
            if let i = model.items.firstIndex(where: { $0.id == item.id }) { model.items[i] = updated }
        })
    }
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "tray.and.arrow.down.fill").font(.title2).foregroundStyle(Palette.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("把素材文件夹拖到这里").font(.headline)
                    Text("或把文件放进项目的「00_待归类」，再点下方按钮。用途不明的文件进入「09_待确认」。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let source = model.source {
                    Button("打开素材文件夹") { NSWorkspace.shared.open(source) }
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.accent.opacity(dropTarget ? 0.14 : 0.05), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.accent.opacity(dropTarget ? 0.8 : 0.25), style: StrokeStyle(lineWidth: 1.5, dash: [6])))
                .dropDestination(for: URL.self) { urls, _ in
                    guard urls.count == 1 else { model.status = "请一次拖入一个素材文件夹。"; return false }
                    return model.useSource(urls[0])
                } isTargeted: { dropTarget = $0 }
            HStack(spacing: 12) {
                PathPicker(title: "素材来源", url: model.source) { model.pick(1) }
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                PathPicker(title: "目标项目", url: model.destination) { model.pick(2) }
            }
            HStack {
                Button { model.scan() } label: { Label("扫描并预览", systemImage: "magnifyingglass") }
                    .disabled(model.source == nil || model.destination == nil)
                Spacer()
                Picker("归类方式", selection: $model.mode) {
                    Text("移动素材").tag(OrganizationMode.move)
                    Text("复制素材").tag(OrganizationMode.copy)
                }.pickerStyle(.segmented).frame(width: 230)
            }
            if model.items.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "square.stack.3d.up.fill").font(.system(size: 48)).foregroundStyle(Palette.accent.opacity(0.7))
                    Text(model.reportURL == nil ? "文件夹已备好，素材一键归位" : "本次归类已完成").font(.title3.bold())
                    Text("点击“一键自动归类”，自动扫描并放入对应目录。\n也可以先扫描预览，逐项修改分类后再执行。").multilineTextAlignment(.center).foregroundStyle(.secondary)
                    HStack(spacing: 22) {
                        Label(model.mode == .move ? "素材移动到项目" : "保留来源素材", systemImage: model.mode == .move ? "arrow.right.doc.on.clipboard" : "doc.on.doc")
                        Label("工程整体保留", systemImage: "folder")
                        Label("同名自动处理", systemImage: "doc.on.doc")
                    }.font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
            } else {
                HStack(spacing: 12) {
                    Metric(value: model.items.count, title: "总项目", icon: "tray.full")
                    Metric(value: model.items.filter { $0.selected }.count, title: "已勾选", icon: "checkmark.circle")
                    Metric(value: model.items.filter { $0.category == "09_待确认" }.count, title: "待确认", icon: "questionmark.circle")
                }
                HStack {
                    TextField("搜索文件名或分类", text: $query).textFieldStyle(.roundedBorder).frame(maxWidth: 310)
                    Toggle("只看待确认", isOn: $onlyUncertain).toggleStyle(.checkbox)
                    Spacer()
                    Button("全选") { for i in model.items.indices { model.items[i].selected = true } }
                    Button("全不选") { for i in model.items.indices { model.items[i].selected = false } }
                }
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visible) { item in AssetRow(item: binding(item), categories: model.availableCategories) }
                    }
                }.background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
            }
            HStack {
                Text(model.mode == .move ? "移动归类 · 重复项留在来源 · 同名不同内容加序号" : "复制归类 · 保留来源 · 同名不同内容加序号").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    if model.items.isEmpty { model.scan(automatically: true) } else { model.execute() }
                } label: {
                    Label(model.items.isEmpty ? "一键自动归类" : "归类已选（\(model.items.filter { $0.selected }.count) 项）", systemImage: "tray.and.arrow.down")
                }.buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(model.source == nil || model.destination == nil || (!model.items.isEmpty && !model.items.contains { $0.selected }))
            }
        }.disabled(model.busy)
    }
}

struct Metric: View {
    let value: Int
    let title: String
    let icon: String
    var body: some View {
        HStack {
            Image(systemName: icon).foregroundStyle(Palette.accent)
            Text("\(value)").font(.title3.bold())
            Text(title).font(.caption).foregroundStyle(.secondary)
            Spacer()
        }.padding(12).background(Palette.card, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct AssetRow: View {
    @Binding var item: OrganizeItem
    let categories: [String]
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Toggle("选择 " + item.relative, isOn: $item.selected).labelsHidden()
                Image(systemName: item.typeInfo.icon).font(.title3).foregroundStyle(Palette.accent).frame(width: 26)
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.relative).font(.callout.weight(.medium)).lineLimit(2).textSelection(.enabled)
                    HStack(spacing: 8) {
                        Text(item.typeInfo.label).font(.caption2).padding(.horizontal, 6).padding(.vertical, 3).background(Palette.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 4))
                        Text(item.reason).font(.caption).foregroundStyle(item.category == "09_待确认" ? .orange : .secondary).lineLimit(1)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Picker("归类位置", selection: Binding(get: { item.category }, set: { value in
                    item.category = value
                    item.reason = "手动选择分类"
                })) { ForEach(categories, id: \.self) { Text($0).tag($0) } }
                    .labelsHidden().frame(width: 255).accessibilityLabel("\(item.source.lastPathComponent) 的归类位置")
            }.padding(12)
            Divider()
        }
    }
}

struct StatusBar: View {
    @Bindable var model: HelperModel
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if model.busy { ProgressView().controlSize(.small) }
            else { Image(systemName: model.finished ? "checkmark.circle.fill" : "info.circle").foregroundStyle(model.finished ? .green : Palette.accent) }
            Text(model.status).font(.callout).lineLimit(3).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            if let dest = model.destination {
                if let report = model.reportURL { Button("查看整理记录") { NSWorkspace.shared.open(report) }.disabled(model.busy) }
                Button("打开项目") { NSWorkspace.shared.activateFileViewerSelecting([dest]) }.disabled(model.busy)
                if model.finished && model.tab == 0 { Button("继续归类素材") { model.tab = 1 } }
            }
        }.padding(13).frame(minHeight: 58).background(Palette.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 11))
    }
}

struct RulesView: View {
    private let rules: [(String, String, String)] = [
        ("video", "口播与产品实拍", "A-roll、口播净版归口播；B-roll、空镜、补拍归产品实拍。审片版、精剪与成片按文件名优先判断。"),
        ("chart.xyaxis.line", "产品资料与实测", "规格书、产品 Brief、官方资料单独存放。识别 CSV、Excel、Parquet 等数据；防抖轨迹与测试实测数据分别归类。"),
        ("waveform", "配乐与证据音", "BGM、音效、人声与现场录音分开。啸叫、底噪采样、原声优先保留为证据音。"),
        ("cube.transparent", "动画、模型与 PCB", "Blender、AE、HyperFrames 与产品模型分开。补齐 STEP、GLB、STL、EasyEDA、KiCad 和字体格式。"),
        ("folder.fill", "完整工程保留", "识别 HyperFrames、Remotion、剪映、ChatCut、PR、达芬奇等工程标识，整个目录移动或复制，保留内部相对引用。"),
        ("questionmark.circle", "用途不清楚时", "先看文件名，再看最近的原目录。无用途依据的 PDF、表格和相机编号视频放待确认，可在预览中修改。")
    ]
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(rules, id: \.1) { rule in
                    HStack(alignment: .top, spacing: 15) {
                        Image(systemName: rule.0).font(.title2).foregroundStyle(Palette.accent).frame(width: 32)
                        VStack(alignment: .leading, spacing: 7) { Text(rule.1).font(.headline); Text(rule.2).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                        Spacer(minLength: 0)
                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
                }
                Text("分类依据是名称、目录和文件类型；不读取视频画面，也不调用云端 AI。").font(.caption).foregroundStyle(.secondary).padding(.vertical, 10)
            }
        }
    }
}

@main struct FrameNest: App {
    init() {
        if CommandLine.arguments.contains("--self-test") {
            do { try runSelfTests(); exit(0) } catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
        }
    }
    var body: some Scene {
        WindowGroup("FrameNest") { ContentView() }.defaultSize(width: 1180, height: 860)
            .commands { CommandGroup(replacing: .newItem) {} }
    }
}
