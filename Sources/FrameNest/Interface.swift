import FrameNestCore
import SwiftUI
import AppKit

enum Palette {
    static let accent = Color(red: 0.28, green: 0.38, blue: 0.88)
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)
    static func icon(_ path: String) -> String {
        switch String(path.prefix(2)) {
        case "00": return "tray.and.arrow.down"
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
    private static let icon = NSImage(contentsOf: Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/AppIcon.png"))
    var body: some View {
        Group {
            if let icon = Self.icon {
                Image(nsImage: icon).resizable().interpolation(.high)
            } else {
                Image(systemName: "folder.badge.gearshape").resizable().scaledToFit().padding(6).foregroundStyle(Palette.accent)
            }
        }.frame(width: size, height: size)
    }
}

struct ContentView: View {
    @Bindable var model: HelperModel
    var body: some View {
        NavigationSplitView {
            Sidebar(model: model).navigationSplitViewColumnWidth(min: 185, ideal: 210, max: 260)
        } detail: {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(["新建项目", "素材归类", "分类规则"][model.tab]).font(.title2.bold())
                        Text(["按你的制作习惯，准备好每个项目。", "素材放进一个文件夹，点一次就能归类。", "针对科技评测、产品实拍与动画制作。"][model.tab]).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Group {
                    switch model.tab {
                    case 0: NewProjectView(model: model)
                    case 1: ImportView(model: model)
                    default: RulesView()
                    }
                }.frame(maxWidth: .infinity, maxHeight: 760)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                StatusBar(model: model)
            }.padding(24).frame(minWidth: 740, maxWidth: 1140, maxHeight: .infinity)
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.canvas)
                .navigationTitle("FrameNest")
                .toolbar {
                    ToolbarItemGroup {
                        Button { model.tab = 1; model.pick(1) } label: { Label("导入素材", systemImage: "folder.badge.plus") }
                            .help("选择素材文件夹（⌘O）").keyboardShortcut("o").disabled(model.busy)
                        if let destination = model.destination {
                            Button { NSWorkspace.shared.activateFileViewerSelecting([destination]) } label: { Label("在 Finder 中显示项目", systemImage: "folder") }
                        }
                    }
                }
        }.navigationSplitViewStyle(.balanced).tint(Palette.accent).frame(minWidth: 950, minHeight: 680)
    }
}

struct Sidebar: View {
    @Bindable var model: HelperModel
    private var selection: Binding<Int?> {
        Binding(get: { model.tab }, set: { if let page = $0 { model.tab = page } })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                AppMark(size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text("FrameNest").font(.headline)
                    Text("影巢 · 视频项目助手").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 16).padding(.top, 16)
            List(selection: selection) {
                Section("工作区") {
                    Label("新建项目", systemImage: "folder.badge.plus").tag(0)
                    Label("素材归类", systemImage: "square.stack.3d.up").tag(1)
                    Label("分类规则", systemImage: "slider.horizontal.3").tag(2)
                }
            }.listStyle(.sidebar)
            VStack(alignment: .leading, spacing: 8) {
                Label("本地画面识别", systemImage: "eye")
                Label("移动 / 复制可选", systemImage: "folder.badge.gearshape")
                Text("1.6.0 · 开源视频项目助手").font(.caption2).foregroundStyle(.tertiary)
            }.font(.caption).foregroundStyle(.secondary).padding(16)
        }
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
                Toggle("识别画面内容", isOn: $model.analyzeContents).toggleStyle(.checkbox)
                    .help("对名称和目录无法判断用途的视频与图片进行本地画面识别，不上传素材。")
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
                    Metric(value: model.selectedCount, title: "已勾选", icon: "checkmark.circle")
                    Metric(value: model.uncertainCount, title: "待确认", icon: "questionmark.circle")
                }
                HStack {
                    Toggle("只看待确认", isOn: $onlyUncertain).toggleStyle(.checkbox)
                    Spacer()
                    Button("全选") { model.selectAll(true) }
                    Button("全不选") { model.selectAll(false) }
                }
                AssetTable(model: model, items: visible, categories: model.availableCategories)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 10))
            }
            HStack {
                Text(model.mode == .move ? "移动归类 · 重复项留在来源 · 同名不同内容加序号" : "复制归类 · 保留来源 · 同名不同内容加序号").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    if model.items.isEmpty { model.scan(automatically: true) } else { model.execute() }
                } label: {
                    Label(model.items.isEmpty ? "一键自动归类" : "归类已选（\(model.selectedCount) 项）", systemImage: "tray.and.arrow.down")
                }.buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(model.source == nil || model.destination == nil || (!model.items.isEmpty && model.selectedCount == 0))
            }
        }.disabled(model.busy)
            .searchable(text: $query, prompt: "搜索素材名称或分类")
    }
}

struct AssetTable: View {
    @Bindable var model: HelperModel
    let items: [OrganizeItem]
    let categories: [String]
    @State private var selection = Set<UUID>()
    private func binding(_ item: OrganizeItem) -> Binding<OrganizeItem> {
        Binding(get: { model.item(item.id) ?? item }, set: { model.updateItem($0) })
    }
    var body: some View {
        Table(items, selection: $selection) {
            TableColumn("素材") { item in
                HStack(spacing: 9) {
                    Toggle("包含 " + item.relative, isOn: binding(item).selected).labelsHidden()
                    Image(systemName: item.typeInfo.icon).foregroundStyle(Palette.accent).frame(width: 22)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.relative).lineLimit(2)
                        Text(item.typeInfo.label + (item.visualAnalysis.map { " · \($0.framesAnalyzed) 帧" } ?? ""))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 5)
            }.width(min: 180, ideal: 250)
            TableColumn("归类位置") { item in
                Picker("\(item.relative) 的归类位置", selection: Binding(get: { model.item(item.id)?.category ?? item.category }, set: { category in
                    var updated = model.item(item.id) ?? item
                    updated.category = category; updated.reason = "手动选择分类"; model.updateItem(updated)
                })) {
                    ForEach(categories, id: \.self) { Text($0).tag($0) }
                }.labelsHidden()
            }.width(min: 180, ideal: 225)
            TableColumn("判断依据") { item in
                Text(item.reason).font(.callout).lineLimit(2).help(item.reason)
                    .foregroundStyle(item.category == "09_待确认" ? .orange : .secondary)
            }.width(min: 160, ideal: 250)
        }.tableStyle(.inset(alternatesRowBackgrounds: true))
            .contextMenu(forSelectionType: UUID.self) { ids in
                Button("包含所选素材") { model.setSelected(ids, selected: true) }.disabled(ids.isEmpty)
                Button("排除所选素材") { model.setSelected(ids, selected: false) }.disabled(ids.isEmpty)
                Divider()
                Button("在 Finder 中显示") {
                    NSWorkspace.shared.activateFileViewerSelecting(ids.compactMap { model.item($0)?.source })
                }.disabled(ids.isEmpty)
            } primaryAction: { ids in
                NSWorkspace.shared.activateFileViewerSelecting(ids.compactMap { model.item($0)?.source })
            }
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

struct StatusBar: View {
    @Bindable var model: HelperModel
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if model.busy {
                if let progress = model.workProgress, let total = progress.total, total > 0 {
                    ProgressView(value: Double(progress.completed), total: Double(total)).progressViewStyle(.linear)
                } else { ProgressView().progressViewStyle(.linear) }
            }
            HStack(spacing: 12) {
                Image(systemName: model.hasError ? "exclamationmark.triangle.fill" : model.finished ? "checkmark.circle.fill" : "info.circle")
                    .foregroundStyle(model.hasError ? .red : model.finished ? .green : Palette.accent)
                Text(model.status).font(.callout).lineLimit(3).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                if model.busy {
                    Button(model.stopping ? "正在停止…" : "停止", action: model.cancel).disabled(model.stopping).keyboardShortcut(.cancelAction)
                } else if let dest = model.destination {
                    if let report = model.reportURL { Button("查看整理记录") { NSWorkspace.shared.open(report) } }
                    Button("打开项目") { NSWorkspace.shared.activateFileViewerSelecting([dest]) }
                }
            }
        }.padding(13).frame(minHeight: 64).background(Palette.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 11))
    }
}

struct RulesView: View {
    private let rules: [(String, String, String)] = [
        ("video", "口播与产品实拍", "A-roll、口播净版归口播；B-roll、空镜、补拍归产品实拍。审片版、精剪与成片按文件名优先判断。"),
        ("chart.xyaxis.line", "产品资料与实测", "规格书、产品 Brief、官方资料单独存放。识别 CSV、Excel、Parquet 等数据；防抖轨迹与测试实测数据分别归类。"),
        ("waveform", "配乐与证据音", "BGM、音效、人声与现场录音分开。啸叫、底噪采样、原声优先保留为证据音。"),
        ("cube.transparent", "动画、模型与 PCB", "Blender、AE、HyperFrames 与产品模型分开。补齐 STEP、GLB、STL、EasyEDA、KiCad 和字体格式。"),
        ("folder.fill", "完整工程保留", "识别 HyperFrames、Remotion、剪映、ChatCut、PR、达芬奇等工程标识，整个目录移动或复制，保留内部相对引用。"),
        ("eye", "本地画面识别", "相机默认命名的视频抽取多个时间点，图片直接识别。结合物体、文字与人像构图，建议口播、产品实拍、录屏、截图或封面；依据不足时放待确认。")
    ]
    var body: some View {
        GeometryReader { geometry in
          ScrollView {
            VStack(spacing: 12) {
              LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                ForEach(rules, id: \.1) { rule in
                    HStack(alignment: .center, spacing: 15) {
                        Image(systemName: rule.0).font(.title2).foregroundStyle(Palette.accent).frame(width: 32)
                        VStack(alignment: .leading, spacing: 7) { Text(rule.1).font(.headline); Text(rule.2).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                        Spacer(minLength: 0)
                    }.padding(18).frame(maxWidth: .infinity, minHeight: 132, alignment: .leading).background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
                }
              }
                Text("明确名称优先；未知视频与图片可在本机识别画面。人物近景仅作为口播建议，不分析声音，也不上传素材。").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.vertical, 10)
            }.frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .center)
          }
        }
    }
}

@main struct FrameNest: App {
    @State private var model = HelperModel()
    init() {
        if CommandLine.arguments.contains("--self-test") {
            do { try runSelfTests(); exit(0) } catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
        }
    }
    var body: some Scene {
        Window("FrameNest", id: "main") { ContentView(model: model) }.defaultSize(width: 1120, height: 820)
            .windowToolbarStyle(.unified)
            .commands {
                CommandGroup(replacing: .newItem) {
                    Button("新建项目") { model.tab = 0 }.keyboardShortcut("n").disabled(model.busy)
                }
                CommandMenu("工作区") {
                    Button("新建项目") { model.tab = 0 }.keyboardShortcut("1")
                    Button("素材归类") { model.tab = 1 }.keyboardShortcut("2")
                    Button("分类规则") { model.tab = 2 }.keyboardShortcut("3")
                }
            }
    }
}
