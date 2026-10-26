# FrameNest 1.6 性能与 macOS 设计调整

[English](#english)

## 实测性能

2026-10-26，在同一台 16 GB Apple Silicon Mac 上，通过真实 stdio MCP 的 `analyze_media` 比较 1.5 和 1.6。样本为 5 段受控短视频与 4 张图片，共 9 项；每个版本各测 3 轮。每轮启动新服务进程、复制到新路径以避开结果缓存；未清空系统模型或磁盘缓存。计时不包含服务启动。

| 指标 | 1.5 | 1.6 | 说明 |
|---|---:|---:|---|
| 首次识别中位耗时 | 6.2649 秒 | 2.0436 秒 | 本次样本约 3.07 倍速度 |
| 缓存命中中位耗时 | 2.9 毫秒 | 2.7 毫秒 | 毫秒级，差异不作实质改善解读 |
| 识别服务 RSS 峰值采样 | 289.6 MB | 177.4 MB | 每 150 毫秒采样，下降 38.7% |
| 分类结果 | 9 项 | 9 项 | 6 轮结果一致，含 3 项待确认 |

这些数字针对本次受控样本，不代表任意 4K 长片、专有格式或整个 GUI 的速度和内存。

## 实施的优化

- 视频五个时间点合并为一次抽帧请求，按原有时间顺序综合判断；逐帧复用 Vision 请求。
- 画面已经满足明确的视频判断，且文字不会改变当前规则时，跳过额外 OCR。图片仍保留文字识别，封面判断不降级。
- 每份素材使用独立自动释放池，及时释放 Vision 和图像临时对象。
- GUI 按稳定素材 ID 建索引，行修改直接定位；选择与待确认计数增量更新，全选批量更新一次。
- 进度反馈在工作线程节流到约 150 毫秒，避免每份文件都排队更新主线程。
- 整理记录逐条追加，避免每处理一个文件就重写此前全部记录。
- 可停止扫描、识别与归类；等待抽帧时定期检查停止请求，归类在完整文件边界停止，并保留已完成条目和记录。

## 对照 Apple 设计规范

| 依据 | 改动 |
|---|---|
| [macOS 设计](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos) / [侧栏](https://developer.apple.com/design/human-interface-guidelines/sidebars) | 原生 NavigationSplitView、可调侧栏、系统选择反馈、单主窗口；保留三个工作区 |
| [工具栏](https://developer.apple.com/design/human-interface-guidelines/toolbars) | 将导入、Finder 操作放到窗口工具栏；搜索使用原生搜索控件 |
| [列表与表格](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables) | 原生 Table 展示素材、归类位置与依据，列可调整，支持多选和上下文操作 |
| [进度指示](https://developer.apple.com/design/human-interface-guidelines/progress-indicators) | 固定位置显示线性进度；数量已知时显示确定进度，提供停止与 Esc，停止后清楚记录已完成内容 |

快捷键：⌘N 新建项目，⌘O 导入素材，⌘1 / ⌘2 / ⌘3 切换页面，Esc 停止当前任务。沿用 macOS 14 最低版本，不额外定制 Liquid Glass。

## 验证与边界

核心自检 134 项通过，MCP 协议与文件操作检查 57 项通过。新增检查覆盖万项素材计数、稳定 ID 更新、旧行失效、开始前取消、移动中停止、原文件与完成记录保留。构建无新增警告。

基准可复现命令：

```bash
python3 Scripts/benchmark_mcp.py --binary /path/to/FrameNestMCP --fixtures /path/to/fixtures --trials 3 --output /path/to/results.json
```

2026-10-26：Mac 处于锁屏，尚未完成真实窗口、缩放与视觉检查。1.6 已在本机安装，安装后的 MCP 实际识别通过；草稿 PR 保留此待验收项，未据此发布稳定版。源码构建和逻辑检查不等于人工视觉验收。

## English

Version 1.6 batches video sampling, reuses Vision requests, avoids OCR where it cannot change a decisive video rule, scopes temporary objects per asset, indexes GUI rows by stable ID, throttles progress, and appends operation logs incrementally. Cancellation preserves complete files and partial operation reports.

Three real MCP trials per version used the same nine controlled image/video fixtures on a 16 GB Apple Silicon Mac. Median uncached analysis fell from 6.2649s to 2.0436s. Sampled peak service RSS fell from 289.6 MB to 177.4 MB. All classification results matched. These are service measurements on short fixtures, not guarantees for arbitrary footage or the entire GUI.

The GUI adopts native sidebar navigation, toolbar actions, search and tables, with consistent progress and cancellation, following the Apple HIG links above. Core checks passed 134 cases; MCP checks passed 57 cases. The Mac was locked during this run, so actual window interaction, resizing, and visual acceptance remain pending. The installed MCP binary passed actual analysis. The PR remains a draft pending visual checks.
