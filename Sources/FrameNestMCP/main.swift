import Foundation
import CryptoKit
import CoreFoundation
import FrameNestCore

struct RPCError: Error {
    let code: Int
    let message: String
}

final class OrganizationPlan {
    let id = UUID().uuidString
    let created = Date()
    let source: URL
    let destination: URL
    let destinationIdentity: String
    let items: [OrganizeItem]
    let mode: OrganizationMode
    let fingerprints: [String: String]
    var result: [String: Any]?
    var executionKey: Data?
    init(source: URL, destination: URL, items: [OrganizeItem], mode: OrganizationMode) throws {
        self.source = source; self.destination = destination; self.items = items
        self.mode = mode
        destinationIdentity = try MCPServer.identity(destination)
        var snapshots: [String: String] = [:]
        for item in items { snapshots[item.relative] = try MCPServer.fingerprint(item.source) }
        fingerprints = snapshots
    }
}

final class MCPServer {
    static let versions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]
    static let ttl: TimeInterval = 3600
    var initialized = false
    var protocolVersion = versions[0]
    var plans: [String: OrganizationPlan] = [:]
    let fm = FileManager.default
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.5.0"

    static func json(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }
    func send(_ message: [String: Any]) {
        do {
            var data = try Self.json(message); data.append(0x0a)
            try FileHandle.standardOutput.write(contentsOf: data)
        } catch {
            try? FileHandle.standardError.write(contentsOf: Data("FrameNest MCP output error: \(error.localizedDescription)\n".utf8))
        }
    }
    func run() {
        while let line = readLine(strippingNewline: true) {
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            do {
                let decoded = try JSONSerialization.jsonObject(with: Data(line.utf8))
                guard let message = decoded as? [String: Any] else {
                    throw RPCError(code: -32600, message: "A JSON-RPC object is required.")
                }
                handle(message)
            } catch let error as RPCError {
                send(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": error.code, "message": error.message]])
            } catch {
                send(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Invalid JSON."]])
            }
        }
    }
    func handle(_ request: [String: Any]) {
        guard request["jsonrpc"] as? String == "2.0", let method = request["method"] as? String else {
            send(["jsonrpc": "2.0", "id": request["id"] ?? NSNull(), "error": ["code": -32600, "message": "Invalid JSON-RPC request."]]); return
        }
        guard let id = request["id"] else { return }
        guard id is String || (id is NSNumber && CFGetTypeID(id as CFTypeRef) != CFBooleanGetTypeID()) else {
            send(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32600, "message": "Invalid request ID."]]); return
        }
        do {
            let params: [String: Any]
            if let raw = request["params"] {
                guard let value = raw as? [String: Any] else { throw RPCError(code: -32602, message: "params must be an object.") }
                params = value
            } else { params = [:] }
            let result: [String: Any]
            switch method {
            case "initialize":
                guard !initialized else { throw RPCError(code: -32600, message: "Already initialized.") }
                let requested = params["protocolVersion"] as? String ?? ""
                protocolVersion = Self.versions.contains(requested) ? requested : Self.versions[0]
                initialized = true
                result = ["protocolVersion": protocolVersion, "capabilities": ["tools": ["listChanged": false]],
                          "serverInfo": ["name": "framenest", "title": "FrameNest · 影巢", "version": version],
                          "instructions": "Local video project organizer. Use preview_organize before execute_organize. Set preview mode to copy (default) or move (relocates source items). Plans expire after one hour and after this process exits. Review uncertain categories; execute only the requested files. Paths must be absolute or start with ~/."]
            case "ping": result = [:]
            case "tools/list":
                guard initialized else { throw RPCError(code: -32000, message: "Initialize first.") }
                result = ["tools": Self.tools]
            case "tools/call":
                guard initialized else { throw RPCError(code: -32000, message: "Initialize first.") }
                guard let name = params["name"] as? String, Self.tools.contains(where: { $0["name"] as? String == name }) else {
                    throw RPCError(code: -32602, message: "Unknown tool.")
                }
                let args: [String: Any]
                if let raw = params["arguments"] {
                    guard let dict = raw as? [String: Any] else { throw RPCError(code: -32602, message: "arguments must be an object.") }
                    args = dict
                } else { args = [:] }
                do {
                    let token = (params["_meta"] as? [String: Any])?["progressToken"]
                    let value = try call(name, args: args, progressToken: token)
                    let text = String(decoding: try Self.json(value), as: UTF8.self)
                    var wrapped: [String: Any] = ["content": [["type": "text", "text": text]], "isError": (value["failed"] as? Int ?? 0) > 0]
                    if !["2024-11-05", "2025-03-26"].contains(protocolVersion) { wrapped["structuredContent"] = value }
                    result = wrapped
                } catch {
                    let message = (error as? RPCError)?.message ?? error.localizedDescription
                    result = ["content": [["type": "text", "text": message]], "isError": true]
                }
            default: throw RPCError(code: -32601, message: "Method not found: \(method)")
            }
            send(["jsonrpc": "2.0", "id": id, "result": result])
        } catch let error as RPCError {
            send(["jsonrpc": "2.0", "id": id, "error": ["code": error.code, "message": error.message]])
        } catch {
            send(["jsonrpc": "2.0", "id": id, "error": ["code": -32603, "message": error.localizedDescription]])
        }
    }

    static func schema(_ properties: [String: Any], required: [String] = []) -> [String: Any] {
        ["type": "object", "properties": properties, "required": required, "additionalProperties": false]
    }
    static func tool(_ name: String, _ title: String, _ description: String, _ input: [String: Any], readOnly: Bool = true, idempotent: Bool = true, destructive: Bool = false) -> [String: Any] {
        ["name": name, "title": title, "description": description, "inputSchema": input,
         "annotations": ["readOnlyHint": readOnly, "destructiveHint": destructive, "idempotentHint": idempotent, "openWorldHint": false]]
    }
    static let tools: [[String: Any]] = [
        tool("get_template", "读取目录模板", "Return the saved GUI folder template, default template and available categories. Does not create folders or open the GUI.", schema([:])),
        tool("create_project", "创建视频项目", "Create a new project directory and Markdown project note. Existing projects are not overwritten. Uses the saved GUI template unless folders is provided.", schema([
            "parent_path": ["type": "string", "description": "Existing parent directory, absolute path or ~/ path."],
            "name": ["type": "string", "description": "Project folder name without path separators."],
            "add_date": ["type": "boolean", "default": false, "description": "Append local date as _yyyyMMdd."],
            "folders": ["type": "array", "items": ["type": "string"], "minItems": 1, "description": "Optional relative folder paths; / creates subfolders."]
        ], required: ["parent_path", "name"]), readOnly: false, idempotent: false),
        tool("classify_files", "判断文件分类", "Classify file names or relative paths without reading file contents. Returns suggested category, type and reason. Ambiguous items remain in 09_待确认.", schema([
            "paths": ["type": "array", "items": ["type": "string"], "minItems": 1, "maxItems": 200]
        ], required: ["paths"])),
        tool("analyze_media", "识别视频与图片画面", "Analyze local image contents or sample multiple video frames with Apple Vision on this Mac. Returns suggested category, evidence, object labels and frame times. No uploads. Stable portrait shots suggest talking-head footage; they do not prove speech. Mixed or unclear scenes remain for review. Absolute file paths are required.", schema([
            "paths": ["type": "array", "items": ["type": "string"], "minItems": 1, "maxItems": 20]
        ], required: ["paths"])),
        tool("preview_organize", "预览素材归类", "Scan a source folder and create a one-hour in-memory copy or move plan. Copy is the default; move relocates source items. The project inbox 00_待归类 is also supported. Preview does not write to the destination. Returns a plan_id, category totals and a bounded first page.", schema([
            "source_path": ["type": "string"], "destination_path": ["type": "string"],
            "mode": ["type": "string", "enum": ["copy", "move"], "default": "copy"],
            "analyze_contents": ["type": "boolean", "default": true, "description": "Analyze uncertain images and videos locally; explicit filename classifications are preserved."],
            "limit": ["type": "integer", "minimum": 1, "maximum": 200, "default": 50]
        ], required: ["source_path", "destination_path"])),
        tool("get_plan", "查看归类计划", "Read a page from an existing plan. Plans belong to this server process and expire after one hour. Does not rescan or change files.", schema([
            "plan_id": ["type": "string"], "offset": ["type": "integer", "minimum": 0, "default": 0],
            "limit": ["type": "integer", "minimum": 1, "maximum": 200, "default": 50]
        ], required: ["plan_id"])),
        tool("execute_organize", "执行素材归类", "Execute the reviewed plan using its frozen mode. Copy retains source files; move relocates them. Identical existing items are skipped and retained in the source even in move mode. Optionally restrict include_paths and override categories. Rejects changed source snapshots or destination identity. Identical repeat requests reuse the result.", schema([
            "plan_id": ["type": "string"],
            "include_paths": ["type": "array", "items": ["type": "string"], "minItems": 1, "description": "Exact relative paths from the plan; omitted means all plan items."],
            "overrides": ["type": "array", "items": schema([
                "relative_path": ["type": "string"], "category": ["type": "string", "description": "Safe relative category path."]
            ], required: ["relative_path", "category"])]
        ], required: ["plan_id"]), readOnly: false, destructive: true)
    ]

    func string(_ args: [String: Any], _ key: String) throws -> String {
        guard let value = args[key] as? String, !value.isEmpty, !value.contains("\0") else { throw HelperError.message("\(key) must be a non-empty string.") }
        return value
    }
    func integer(_ args: [String: Any], _ key: String, default fallback: Int, minimum: Int = 0, maximum: Int = 1_000_000) throws -> Int {
        guard let raw = args[key] else { return fallback }
        guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite,
              number.doubleValue >= Double(minimum), number.doubleValue <= Double(maximum), number.doubleValue.rounded() == number.doubleValue else {
            throw HelperError.message("\(key) must be an integer between \(minimum) and \(maximum).")
        }
        return number.intValue
    }
    func directory(_ path: String) throws -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/"), !expanded.contains("\0") else { throw HelperError.message("Use an absolute directory path or ~/ path.") }
        let url = URL(fileURLWithPath: expanded).resolvingSymlinksInPath().standardizedFileURL
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else { throw HelperError.message("Directory does not exist: \(path)") }
        return url
    }
    static func identity(_ url: URL) throws -> String {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attrs[.type] as? FileAttributeType != .typeSymbolicLink else { throw HelperError.message("A planned path became a symbolic link; preview again.") }
        return "\(url.resolvingSymlinksInPath().path)|\(attrs[.systemNumber] ?? "")|\(attrs[.systemFileNumber] ?? "")"
    }
    static func fingerprint(_ url: URL) throws -> String {
        let fm = FileManager.default
        var records: [String] = []
        func record(_ entry: URL) throws {
            let attrs = try fm.attributesOfItem(atPath: entry.path)
            let type = attrs[.type] as? FileAttributeType
            let relative = entry.pathComponents.dropFirst(url.pathComponents.count).joined(separator: "/")
            let modified = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970.bitPattern ?? 0
            let link = type == .typeSymbolicLink ? try fm.destinationOfSymbolicLink(atPath: entry.path) : ""
            let fields = [relative, type?.rawValue ?? "", String(describing: attrs[.size] ?? 0), String(modified), String(describing: attrs[.systemFileNumber] ?? 0), link]
            records.append(String(decoding: try json(fields), as: UTF8.self))
        }
        let attrs = try fm.attributesOfItem(atPath: url.path)
        guard attrs[.type] as? FileAttributeType != .typeSymbolicLink else { throw HelperError.message("A source item became a symbolic link; preview again.") }
        try record(url)
        if attrs[.type] as? FileAttributeType == .typeDirectory {
            var scanError: Error?
            guard let en = fm.enumerator(at: url, includingPropertiesForKeys: [], options: [], errorHandler: { _, error in scanError = error; return false }) else {
                throw HelperError.message("Cannot snapshot source directory.")
            }
            for case let child as URL in en { try record(child) }
            if let error = scanError { throw error }
        }
        return SHA256.hash(data: try json(records.sorted())).map { String(format: "%02x", $0) }.joined()
    }
    func currentTemplate() -> String {
        let saved = UserDefaults(suiteName: "io.github.weixunkkkkk.framenest")?.string(forKey: "folderTemplate")
        let legacy = Organizer.categories.prefix(20).joined(separator: "\n")
        return saved == nil || saved == legacy || saved == Organizer.categories.sorted().joined(separator: "\n") ? Organizer.defaultFolders : saved!
    }
    func plan(_ id: String) throws -> OrganizationPlan {
        guard let value = plans[id], Date().timeIntervalSince(value.created) < Self.ttl else {
            plans.removeValue(forKey: id)
            throw HelperError.message("Plan not found or expired. Run preview_organize again in this MCP session.")
        }
        return value
    }
    func itemJSON(_ item: OrganizeItem, destination: URL) -> [String: Any] {
        var result: [String: Any] = ["relative_path": item.relative, "category": item.category, "reason": item.reason,
         "file_type": item.typeInfo.label, "whole_directory": item.wholeDirectory,
         "needs_review": item.category == "09_待确认",
         "destination_path": destination.appendingPathComponent(item.category).appendingPathComponent(item.relative).path]
        if let analysis = item.visualAnalysis { result["visual_analysis"] = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(analysis)) }
        return result
    }
    func page(_ value: OrganizationPlan, offset: Int, limit: Int) -> [String: Any] {
        let end = min(value.items.count, offset + limit)
        let slice = offset < value.items.count ? Array(value.items[offset..<end]) : []
        var totals: [String: Int] = [:]
        for item in value.items { totals[item.category, default: 0] += 1 }
        return ["plan_id": value.id, "source_path": value.source.path, "destination_path": value.destination.path,
                "expires_at": ISO8601DateFormatter().string(from: value.created.addingTimeInterval(Self.ttl)),
                "total_items": value.items.count, "mode": value.mode.rawValue, "offset": offset, "returned_items": slice.count,
                "has_more": end < value.items.count, "executed": value.result != nil,
                "category_counts": totals, "items": slice.map { itemJSON($0, destination: value.destination) }]
    }
    func call(_ name: String, args: [String: Any], progressToken: Any?) throws -> [String: Any] {
        let definition = Self.tools.first { $0["name"] as? String == name }!
        let properties = ((definition["inputSchema"] as! [String: Any])["properties"] as! [String: Any])
        guard Set(args.keys).isSubset(of: Set(properties.keys)) else { throw HelperError.message("Unexpected arguments for \(name).") }
        switch name {
        case "get_template":
            return ["name": "FrameNest", "version": version, "folders": currentTemplate().components(separatedBy: .newlines).filter { !$0.isEmpty },
                    "default_folders": Organizer.defaultFolders.components(separatedBy: .newlines), "categories": Organizer.categories.sorted(),
                    "copy_mode": "copy", "supported_modes": OrganizationMode.allCases.map(\.rawValue), "inbox_folder": Organizer.inboxFolder,
                    "visual_engine": "Apple Vision (on-device)", "analyze_contents_default": true, "plan_ttl_seconds": Int(Self.ttl)]
        case "create_project":
            let parent = try directory(string(args, "parent_path"))
            var projectName = try string(args, "name")
            if let raw = args["add_date"] {
                guard let bool = raw as? NSNumber, CFGetTypeID(bool) == CFBooleanGetTypeID() else { throw HelperError.message("add_date must be a boolean.") }
                if bool.boolValue { let formatter = DateFormatter(); formatter.dateFormat = "yyyyMMdd"; projectName += "_" + formatter.string(from: Date()) }
            }
            let folders: String
            if let raw = args["folders"] {
                guard let list = raw as? [String], !list.isEmpty else { throw HelperError.message("folders must be a non-empty string array.") }
                folders = list.joined(separator: "\n")
            } else { folders = currentTemplate() }
            let root = try Organizer.createProject(parent: parent, name: projectName, folders: folders)
            return ["project_path": root.path, "project_name": root.lastPathComponent,
                    "folders": folders.components(separatedBy: .newlines).filter { !$0.isEmpty }, "note_path": root.appendingPathComponent("项目说明.md").path]
        case "classify_files":
            guard let paths = args["paths"] as? [String], !paths.isEmpty, paths.count <= 200,
                  paths.allSatisfy({ !$0.isEmpty && !$0.contains("\0") }) else { throw HelperError.message("paths must contain 1 to 200 non-empty file names or relative paths.") }
            let values = paths.map { path -> [String: Any] in
                let category = Organizer.classify(path)
                return ["path": path, "category": category.0, "reason": category.1,
                        "file_type": Organizer.fileType((path as NSString).pathExtension).label, "needs_review": category.0 == "09_待确认"]
            }
            return ["items": values]
        case "analyze_media":
            guard let paths = args["paths"] as? [String], !paths.isEmpty, paths.count <= 20 else {
                throw HelperError.message("paths must contain 1 to 20 absolute image/video file paths.")
            }
            let files: [URL] = try paths.map { path in
                let expanded = (path as NSString).expandingTildeInPath
                guard expanded.hasPrefix("/"), !expanded.contains("\0") else { throw HelperError.message("Use absolute file paths or ~/ paths.") }
                let file = URL(fileURLWithPath: expanded).resolvingSymlinksInPath()
                guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw HelperError.message("Not a regular file: \(path)") }
                return file
            }
            let values = try files.enumerated().map { index, file -> [String: Any] in
                let result = VisualClassifier.analyze(file)
                if let token = progressToken, token is String || token is NSNumber {
                    send(["jsonrpc": "2.0", "method": "notifications/progress", "params": ["progressToken": token, "progress": index + 1, "total": files.count, "message": "已识别：" + file.lastPathComponent]])
                }
                return ["path": file.path, "category": result.category ?? "09_待确认", "reason": result.reason,
                        "needs_review": result.category == nil, "visual_analysis": try JSONSerialization.jsonObject(with: JSONEncoder().encode(result))]
            }
            return ["items": values]
        case "preview_organize":
            let source = try directory(string(args, "source_path"))
            let destination = try directory(string(args, "destination_path"))
            let limit = try integer(args, "limit", default: 50, minimum: 1, maximum: 200)
            let mode: OrganizationMode
            if args["mode"] == nil { mode = .copy }
            else if let raw = args["mode"] as? String, let parsed = OrganizationMode(rawValue: raw) { mode = parsed }
            else { throw HelperError.message("mode must be copy or move.") }
            var analyze = true
            if let raw = args["analyze_contents"] {
                guard let bool = raw as? NSNumber, CFGetTypeID(bool) == CFBooleanGetTypeID() else { throw HelperError.message("analyze_contents must be a boolean.") }
                analyze = bool.boolValue
            }
            plans = plans.filter { Date().timeIntervalSince($0.value.created) < Self.ttl }
            guard plans.count < 32 else { throw HelperError.message("Too many active plans. Restart this MCP server or wait for plans to expire.") }
            var count = 0
            let items = try Organizer.scan(source, destination: destination, analyzeContents: analyze) { message in
                count += 1
                if let token = progressToken, token is String || token is NSNumber {
                    self.send(["jsonrpc": "2.0", "method": "notifications/progress", "params": ["progressToken": token, "progress": count, "message": message]])
                }
            }
            let value = try OrganizationPlan(source: source, destination: destination, items: items, mode: mode)
            plans[value.id] = value
            return page(value, offset: 0, limit: limit)
        case "get_plan":
            let value = try plan(string(args, "plan_id"))
            return page(value, offset: try integer(args, "offset", default: 0), limit: try integer(args, "limit", default: 50, minimum: 1, maximum: 200))
        case "execute_organize":
            let value = try plan(string(args, "plan_id"))
            let allPaths = Set(value.items.map(\.relative))
            let includes: Set<String>
            if let raw = args["include_paths"] {
                guard let list = raw as? [String], !list.isEmpty, Set(list).isSubset(of: allPaths) else { throw HelperError.message("include_paths must be a non-empty subset of plan relative paths.") }
                includes = Set(list)
            } else { includes = allPaths }
            var overrides: [String: String] = [:]
            if let raw = args["overrides"] {
                guard let entries = raw as? [[String: Any]] else { throw HelperError.message("overrides must be an array of relative_path/category objects.") }
                for entry in entries {
                    guard Set(entry.keys) == Set(["relative_path", "category"]) else { throw HelperError.message("Each override needs only relative_path and category.") }
                    let relative = try string(entry, "relative_path"), category = try string(entry, "category")
                    guard includes.contains(relative), Organizer.safeRelative(category), overrides[relative] == nil else { throw HelperError.message("Override paths must be selected plan items and categories must be safe relative paths.") }
                    overrides[relative] = category
                }
            }
            let key = try Self.json(["include_paths": includes.sorted(), "overrides": overrides])
            if let cached = value.result {
                guard value.executionKey == key else { throw HelperError.message("This plan was executed with different options. Preview again.") }
                var result = cached; result["reused_result"] = true; return result
            }
            guard try Self.identity(value.destination) == value.destinationIdentity else { throw HelperError.message("The destination changed. Preview again.") }
            var selected = value.items.filter { includes.contains($0.relative) }
            for index in selected.indices {
                guard try Self.fingerprint(selected[index].source) == value.fingerprints[selected[index].relative] else {
                    throw HelperError.message("Source changed after preview: \(selected[index].relative). Preview again.")
                }
                if let category = overrides[selected[index].relative] { selected[index].category = category; selected[index].reason = "MCP 手动指定分类" }
            }
            var count = 0
            let completed = try Organizer.executeDetailed(selected, destination: value.destination, mode: value.mode) { message in
                count += 1
                if let token = progressToken, token is String || token is NSNumber {
                    self.send(["jsonrpc": "2.0", "method": "notifications/progress", "params": ["progressToken": token, "progress": count, "total": selected.count, "message": message]])
                }
            }
            let result: [String: Any] = ["plan_id": value.id, "mode": value.mode.rawValue, "copied": completed.copied, "moved": completed.moved, "skipped": completed.skipped,
                                       "failed": completed.failed, "report_path": completed.reportURL.path,
                                       "summary": completed.summary, "reused_result": false]
            value.result = result; value.executionKey = key
            return result
        default: throw RPCError(code: -32602, message: "Unknown tool.")
        }
    }
}

if CommandLine.arguments.contains("--version") {
    print("FrameNestMCP 1.5.0")
} else {
    MCPServer().run()
}
