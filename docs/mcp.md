# FrameNest MCP · 接入 Codex

[English ↓](#english)

FrameNest 1.3 起包含独立的本地 MCP 程序 `FrameNestMCP`。它与图形版共享 `FrameNestCore`，由 Codex 按需通过 stdio 启动；读取模板、发现工具和整理素材都不需要打开图形窗口。1.4 起支持项目内的 `00_待归类` 和移动归类；1.5 起支持本机画面识别。

## 安装与配置

将 1.3 或更新版本的 `FrameNest.app` 放入“应用程序”，然后运行：

```bash
codex mcp add framenest -- /Applications/FrameNest.app/Contents/MacOS/FrameNestMCP
codex mcp get framenest --json
```

也可以在 `~/.codex/config.toml` 中新增以下部分：

```toml
[mcp_servers.framenest]
command = "/Applications/FrameNest.app/Contents/MacOS/FrameNestMCP"
args = []
enabled = true
startup_timeout_sec = 15
tool_timeout_sec = 600
```

修改已有配置前保留备份，并核对其他配置项。新配置加载后，可在 Codex 的 `/mcp` 或 MCP 服务器设置中查看；已打开的客户端可能需要重启该服务器或新建会话。

源码方式可以执行 `swift build -c release --product FrameNestMCP`，再将 Codex 的 `command` 指向 `.build/release/FrameNestMCP` 的绝对路径。运行 MCP 不需要 Node.js、Python 或第三方 Swift 包。

## 可调用的工具

| 工具 | 用途 | 是否写入项目 |
|---|---|---|
| `get_template` | 读取图形版保存的目录模板、默认模板与分类列表 | 否 |
| `create_project` | 按模板创建项目目录和 Markdown 说明 | 是，新建目录 |
| `classify_files` | 根据文件名或相对路径批量建议分类 | 否，不读取文件内容 |
| `analyze_media` | 读取本地图片内容或视频多帧，返回建议、标签与抽帧时间 | 否，可能更新本机识别缓存 |
| `preview_organize` | 扫描来源目录，生成移动或复制计划和计划编号 | 否 |
| `get_plan` | 分页查看计划中的文件与建议去向 | 否 |
| `execute_organize` | 按计划移动或复制，可指定文件子集或覆盖分类 | 是，整理文件并记录结果 |

### 推荐说法

- “用 FrameNest 给我新建一个产品评测项目，放到我选的目录里。”
- “先预览这批素材会怎么归类，把待确认项列出来。”
- “把计划中的这些文件复制归类，原素材保留。”
- “这几个相机编号文件是产品实拍，按产品实拍分类再执行。”

### 调用示例

先生成预览，路径替换为实际存在的目录：

```json
{
  "source_path": "/path/to/source",
  "destination_path": "/path/to/project",
  "mode": "move",
  "analyze_contents": true,
  "limit": 50
}
```

`analyze_contents` 默认 `true`，仅对名称无法分类的视频与图片在本机识别画面；设为 `false` 可关闭。单文件内容识别使用 `analyze_media`，传入绝对文件路径数组 `paths`（最多 20 项）。识别不修改素材，不向网络发送数据，可能写入本机缓存。

`mode` 省略时默认为 `copy`；`move` 会将来源文件移到项目中。模式固定在预览计划里，执行时不能更换。来源可以是项目内的 `00_待归类`，也可以是与项目无重叠的外部文件夹。

使用 `preview_organize` 返回的 `plan_id` 执行，并按需要限定文件或调整分类：

```json
{
  "plan_id": "PLAN_ID_FROM_PREVIEW",
  "include_paths": ["相机A/C0001.mp4"],
  "overrides": [
    {
      "relative_path": "相机A/C0001.mp4",
      "category": "02_原始素材/产品实拍"
    }
  ]
}
```

省略 `include_paths` 表示计划中的全部项目。模板中的分类可直接使用，也可以指定有效的相对子目录。工具返回模式、移动、复制、跳过与失败数量，以及 Markdown 整理记录的实际路径。

## 计划行为与范围

- 计划保存在当前 MCP 进程内，一小时后过期；重连或重启后需要重新预览。
- 同一计划以相同参数重复执行会复用结果；参数改变时需要新的预览。
- 执行前核对来源文件及完整工程目录的元数据快照，并核对目标目录身份。预览后来源变化或目标被替换时，要求重新预览。
- 复制模式保留原素材；移动模式将成功条目移到目标。相同内容跳过并保留在来源，同名不同内容加序号。预览显示的目标文件名可能在执行时因同名冲突增加序号，实际去向以整理记录为准。
- 名称、近层目录与格式优先；未明确的视频与图片默认进行本地画面识别。视频抽取多个时间点综合判断，结果保存在计划条目的 `visual_analysis`；无法确定用途或读取失败时仍需人工判断。
- 服务使用 MCP 的 initialize/stdin/stdout 协议，支持 2025-11-25、2025-06-18、2025-03-26 和 2024-11-05 版本。协议外日志只写 stderr。

## 验证

```bash
bash Scripts/package_app.sh release
FrameNest.app/Contents/MacOS/FrameNest --self-test
python3 Scripts/test_mcp.py
```

协议测试使用独立临时目录，覆盖工具发现、模板读取、创建目录、分类、分页、按计划移动或复制、项目内部待归类、手动分类、重复执行、同名处理、来源变化和路径替换等情况。Python 3 仅用于开发测试。

配置参考：[OpenAI 官方 MCP 文档](https://learn.chatgpt.com/docs/extend/mcp?surface=cli)。协议参考：[MCP stdio](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports) 与 [MCP 工具规范](https://modelcontextprotocol.io/specification/2025-11-25/server/tools)。

---

## English

FrameNest 1.3 includes `FrameNestMCP`, a native local stdio MCP server sharing the same `FrameNestCore` engine as the GUI. Codex launches it on demand. Tool discovery and file operations do not open a graphical window. No Node.js, Python runtime, or third-party Swift packages are required to run it.

### Connect to Codex

Install the current `FrameNest.app` in Applications:

```bash
codex mcp add framenest -- /Applications/FrameNest.app/Contents/MacOS/FrameNestMCP
codex mcp get framenest --json
```

Alternatively, add the TOML configuration shown above to `~/.codex/config.toml`. Back up existing configuration and preserve unrelated entries. Reload the MCP server or start a new session when needed. Source builds can use the absolute path of `.build/release/FrameNestMCP` instead.

### Tools

| Tool | Purpose |
|---|---|
| `get_template` | Read the saved GUI template, defaults, and categories |
| `create_project` | Create a new project and Markdown note; existing projects are not overwritten |
| `classify_files` | Suggest categories for names or relative paths without reading file contents |
| `analyze_media` | Analyze image contents or multiple video frames locally; return evidence and frame times |
| `preview_organize` | Scan a source folder and return a move or copy plan and `plan_id` |
| `get_plan` | Read a bounded page of an existing plan |
| `execute_organize` | Execute a reviewed move or copy plan, optionally selecting items or overriding categories |

Ask Codex to create a video project, preview a batch of media, review uncertain items, or copy a reviewed selection. Preview first, then execute with the returned plan ID. The JSON examples above show selecting one item and overriding its category.

Plans are local to a server process and expire after one hour. Identical repeat executions reuse their result; changed options require a new preview. Source metadata snapshots and destination identity are checked before execution. File names may receive numeric suffixes on conflicts; the Markdown report records actual destinations. Copy mode retains source files. Set `mode: "move"` in the preview to relocate items; the execution uses the mode frozen in that plan. Identical existing items are skipped and left in the source even in move mode. Version 1.4 supports the project inbox `00_待归类` as a source; other source and destination roots must not overlap.

The server implements the initialize-based MCP stdio revisions listed above. It writes protocol messages to stdout and diagnostics to stderr. Explicit names, parent-folder hints, and formats take priority. Version 1.5 enables local content analysis of uncertain images and videos in previews (`analyze_contents: true`, the default). Set it to false for names only. `analyze_media` accepts 1–20 absolute image/video paths. It returns Apple Vision evidence and sampled frame times without uploads; private local caches may be updated. Unclear or unreadable files remain for review.

Run the build and check commands above to verify the GUI engine and MCP protocol. The end-to-end protocol checks use synthetic files in isolated temporary directories. Python 3 is only a development-test dependency.
