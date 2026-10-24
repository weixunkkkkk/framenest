# 视频与图片画面识别

[English ↓](#english)

FrameNest 1.5 可在本机读取图片内容，并抽取视频的多个时间点辅助归类。使用 macOS 自带的 Apple Vision 和 AVFoundation，无需 API Key、额外模型下载或网络连接。素材不会上传。

## 使用方式

创建或选择项目，把素材放入 `00_待归类` 或选择外部素材文件夹。“素材归类”中的“识别画面内容”默认开启。点击“一键自动归类”即可扫描、识别并整理，也可以先扫描预览。

明确的文件名和原目录优先，例如 `口播精剪.mp4` 仍作为成片，不会因画面中有人而变成口播原片。`C0001.mp4`、`IMG_0001.png` 等用途不明确的文件才会进入画面识别。完整工程目录保持整体处理，不展开识别内部资源。

| 画面依据 | 分类建议 |
|---|---|
| 多帧稳定、较近且朝向镜头的人像构图 | 原始素材 / 口播 |
| 多帧以数码设备为主体 | 原始素材 / 产品实拍 |
| 多帧为屏幕界面 | 原始素材 / 屏幕录制 |
| 数码设备为主体的图片 | 图片与封面 / 产品原图 |
| 屏幕界面、带测试读数的截图 | 图片与封面 / 截图 |
| 人像或产品搭配较大的标题文字 | 图片与封面 / 封面 |
| 混合场景、依据不足、文件无法读取 | 待确认 |

预览中会显示“画面”标记、实际分析帧数和归类依据。可以逐项改分类或取消勾选。整理记录保存实际去向及归类依据。

## 判断范围

- 视频尝试在约 5%、25%、50%、75%、95% 处抽取画面，并处理旋转信息；成功抽取的真实时间记录在结果中。若有效帧不足，则保留待确认。
- 归类结合物体标签、OCR 文字和人脸构图。视频需要大多数抽样画面支持同一用途，混合场景通常保留待确认。
- 稳定人像只能支持“建议作为口播”，不能证明人在说话；当前不分析音轨。产品标签也不能证明具体品牌、型号或镜头用途。
- 本地视觉模型对微小设备、抽象动画、暗光、遮挡和特殊构图可能识别不足。默认命名不意味着一定能自动分类。
- 不支持或损坏的媒体保留待确认，不因识别失败删除或改写素材。BRAW、R3D、INSV 等专有格式仍可按名称归类，暂不承诺画面解码。

## 本机缓存

识别结果缓存在 `~/Library/Caches/io.github.weixunkkkkk.framenest/VisualAnalysis/`，不保存抽出的原图和完整 OCR 文本。缓存按路径、文件大小、修改时间、文件身份、系统版本与识别算法版本失效。它只用于减少重复识别，不代表人工确认。

## MCP

- `analyze_media`：传入 1–20 个绝对文件路径，直接分析画面，返回建议分类、依据、模型标签、成功抽帧时间与缓存状态。
- `preview_organize`：`analyze_contents` 默认为 `true`，对未能按名称分类的图片和视频识别内容。设为 `false` 可关闭。
- `classify_files`：仍只分析名字，不读取文件，方便快速对比。

模型标签的置信度是系统模型输出，不是项目分类准确率。分类仍允许在预览中人工修改。

## 验证

本机使用同一批画面生成中性文件名的受控样本：稳定人像、数码产品、应用界面、混合画面、纯色画面，以及产品图片、截图和封面。9 项分类符合预期，通过 MCP 完成移动归类，失败 0 项，文件 SHA-256 保持一致。视频样本由真实素材原帧生成，用于验证抽帧和分类流程，不是对任意真实拍摄素材的准确率评估。

核心自检 123 项、MCP 协议检查 57 项通过。Codex 实际连接到 7 个工具，通过 `analyze_media`、预览和执行完成 9 项归类；真实 GUI 也完成相同 9 项扫描与移动，各失败 0 项。三个页面已在实际窗口检查统一边距、卡片对齐和居中布局。

核心及 MCP 检查另覆盖真实视觉模型读图、原图不修改、纯色和损坏文件、缓存以外的预览开关、路径验证及原有整理行为。真实素材只在本机读取与复制用于验收，没有上传到仓库。

参考：[Apple Vision 图像分类](https://developer.apple.com/documentation/vision/classifying-images-for-categorization-and-search)、[文字识别](https://developer.apple.com/documentation/vision/recognizing-text-in-images)、[AVAssetImageGenerator](https://developer.apple.com/documentation/avfoundation/avassetimagegenerator)。

---

## English

FrameNest 1.5 uses Apple Vision and AVFoundation to analyze image contents and multiple video frames entirely on this Mac. No API key, extra model download, network connection, or media upload is required. The content toggle is enabled by default on the organization page.

Explicit names and nearby directories take priority. Only uncertain media names enter visual analysis; recognized engineering folders remain intact. Suggested categories include talking-head footage, consumer-electronics shots, screen recordings, product images, screenshots, and covers. Mixed, unclear, unsupported, or damaged media remains for review.

Videos attempt samples near 5%, 25%, 50%, 75%, and 95% of their duration, with orientation applied. Results record successful frame times. Most sampled frames must support the same use. Stable portrait framing suggests a talking-head shot but does not establish speech; audio is not analyzed. Object labels cannot establish a specific brand or model. Local-model confidence is not project-classification accuracy.

Private caches store results, not sampled images or full OCR text, under the path shown above. They are invalidated by path, size, modification time, file identity, OS version, and algorithm revision.

MCP adds `analyze_media` for 1–20 absolute media paths. `preview_organize` enables content recognition by default through `analyze_contents`; false restores names-only classification. `classify_files` remains names-only. Previews include the analysis evidence and can be overridden before organizing.

A local controlled acceptance run used neutral camera-style names across nine image/video fixtures. All nine expected decisions matched, including review outcomes for mixed and plain frames. MCP moving completed with zero failures and matching file hashes. Videos were generated from real source frames to test the pipeline, not to estimate accuracy across arbitrary footage. Source media stayed local and was not published.
