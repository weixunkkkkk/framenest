# FrameNest 1.4 流程验收

[English ↓](#english)

验收日期：2026-10-24。使用本机已安装的 FrameNest 1.4.0（build 5）。

## 实际流程

| 入口 | 操作 | 结果 |
|---|---|---|
| macOS 图形界面 | 输入项目名 → 创建项目 → 自动进入归类页 → 向 `00_待归类` 放入测试素材 → 点击“一键自动归类” | 移动 19 项、跳过 0 项、失败 0 项 |
| Codex MCP | 读取模板 → 创建项目 → 文件分类 → 预览移动计划 → 分页查看 → 执行计划 | 移动 19 项、跳过 0 项、失败 0 项 |
| Codex MCP 重复执行 | 用相同计划再次执行 | 返回同一结果与记录，没有再次移动 |
| Codex MCP 再扫描 | 重新扫描项目待归类文件夹 | 0 项待处理 |

每条主流程使用 19 个归类条目，包含一个有 3 个内部文件的完整动画工程，共 21 个文件。移动后逐个核对 SHA-256，21 个文件内容一致；原位置不再有这些文件。两条主流程各自生成 Markdown 整理记录。

素材均为自动生成的可解码短视频、WAV 音频、PNG 图片、Markdown 文稿、CSV 数据、SRT 字幕、OBJ 模型和工程目录，没有整理用户原始素材。工程验收只证明内部文件及引用路径被保留，没有测试动画渲染。

## 分类抽查

| 测试条目 | 归类结果 |
|---|---|
| `口播/口播净版.mov` | `02_原始素材/口播` |
| `产品实拍/开箱.mp4` | `02_原始素材/产品实拍` |
| `BGM/啸叫原声.wav` | `03_音频/配音与现场声`，文件名优先于 BGM 父目录 |
| `产品原图.png` / `参数截图.png` / `封面V1.png` | 产品原图、截图、封面分别归类 |
| `KM003C_功率测试.csv` | `01_文稿与资料/实测数据` |
| `相机A/C0001.mp4` | `09_待确认`，不根据扩展名推断镜头用途 |
| `HyperFrames演示` | `06_工程/动画`，完整目录整体移动 |

核心自检 **115 项通过**，MCP 协议及文件操作检查 **52 项通过**。检查包含复制兼容、移动、内部待归类、工程整体处理、相同内容保留来源、同名不同内容加序号、路径边界和来源变化。

## English

Verified on 2026-10-24 using the installed FrameNest 1.4.0 (build 5).

The GUI flow was exercised by creating a project, placing generated fixtures in its inbox, and clicking the one-click organization button. A separate run used Codex's real MCP tool-call API for template discovery, project creation, classification, paginated preview, and move execution. Each flow moved 19 items (21 files, including a complete engineering directory) with zero skipped or failed items. Every output file matched its original SHA-256, and the originals left the inbox.

Repeating the MCP execution returned the cached result and original report. A fresh scan found zero remaining items. Core checks passed 115 cases; MCP protocol and filesystem checks passed 52 cases, including duplicate handling and same-name conflicts.

All media and documents were synthetic fixtures. The engineering check verifies file and relative-path preservation, not rendered animation output. Classification uses names, nearby directories, and formats; an ambiguous camera-numbered clip correctly remained in the review category.
