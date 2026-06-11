# LiveNote 初始化实施计划

## 1. 产品目标

LiveNote 是一款面向 macOS 26 的原生实时语音笔记应用，使用 Swift 开发，并优先采用 macOS 26 最新系统 API 完成实时语音识别、实时翻译、摘要总结和思维导图生成。

第一版目标是让用户可以快速开始录音，并在会议结束后得到可编辑的原文、译文、摘要、行动项和思维导图。

## 2. MVP 范围

### 第一版包含

- 麦克风实时转写
- 实时翻译
- 会后摘要
- 会后思维导图
- Markdown / TXT 导出
- 本地会话管理
- macOS 原生 UI

### 第一版暂不包含

- 系统音频捕获
- 说话人分离
- 云同步
- 团队协作
- 日历 / Reminders 集成
- 多端同步
- 复杂模板系统

## 3. 工程原则

### 项目创建方式

项目应优先通过命令生成，而不是手动创建大量源码文件和配置文件。

建议方式：

1. 使用 Xcode 命令或 XcodeGen 创建 macOS SwiftUI 项目骨架。
2. 使用 Swift Package Manager 管理内部模块或后续依赖。
3. 使用命令生成 `.xcodeproj`，避免手写复杂 Xcode 配置。
4. 源码目录在项目生成后再按模块逐步添加。

推荐初始化路径：

```bash
xcodegen generate
open LiveNote.xcodeproj
```

如果后续决定不使用 XcodeGen，也应优先使用 Xcode 或 SwiftPM 的标准命令创建项目结构，再进行少量必要修改。

### 代码组织原则

- 保持 macOS 26 原生能力优先。
- 不在 MVP 阶段引入不必要的第三方依赖。
- 先跑通技术 Spike，再扩展完整业务模块。
- 所有 AI 生成内容都需要保留来源段落，方便用户回溯。
- 用户编辑过的内容不能被自动生成结果直接覆盖。

## 4. 目标平台与技术栈

- 平台：macOS 26+
- 语言：Swift 6.2+
- UI：SwiftUI，必要时结合 AppKit
- 数据持久化：SwiftData
- 音频：AVFoundation
- 语音识别：Speech framework，重点验证 `SpeechAnalyzer` 与 `SpeechTranscriber`
- 翻译：Translation framework
- 摘要与思维导图：Foundation Models framework
- 并发：Swift Concurrency
- 工程生成：优先 XcodeGen 或 Xcode 标准项目生成流程

## 5. 核心用户路径

```text
打开 App
→ 首次权限检查
→ 点击录音
→ 实时看到转写和翻译
→ 停止录音
→ 自动生成摘要和思维导图
→ 编辑 / 搜索 / 导出
```

## 6. 核心页面

### 首次启动页

- 检查麦克风权限
- 检查语音识别资源
- 检查翻译能力
- 检查 Apple Intelligence / Foundation Models 可用性

### 主工作台空状态

- 中央显示开始录音入口
- 可选择源语言和目标语言
- 左侧显示最近会话
- 右侧智能面板为空状态

### 录音中页面

- 顶部胶囊 Status Bar
- 中央实时原文
- 右侧实时翻译 / 摘要预览
- 支持暂停、停止、标记重点

### 会后总结页

- 左侧会话列表
- 中间完整转写
- 右侧摘要、行动项、关键问题

### 思维导图页

- 画布展示会议结构
- 节点可展开、折叠、编辑
- 点击节点定位原文

### 导出弹窗

- 支持 Markdown
- 支持 TXT
- 可选择是否包含原文、译文、摘要、行动项、思维导图大纲

## 7. Status Bar 设计规则

Status Bar 是横向椭圆胶囊，只放有限的高优先级状态数据。

### 完整状态

```text
● 录音中   12:48   中文 → 英文   本机
```

### 空间不足

```text
● 12:48   中→英   本机
```

### 极窄状态

```text
● 12:48
```

### 信息优先级

1. 录音状态
2. 时长
3. 语言方向
4. 处理模式
5. 错误警告

### 不应放入 Status Bar 的信息

- 麦克风完整名称
- 语音模型名称
- 翻译模型详情
- 摘要生成进度详情
- 当前说话人
- 导出按钮
- 长错误提示
- 多个快捷操作按钮

点击 Status Bar 后，可以展开详情浮层，显示输入源、语言包、模型状态、AI 可用性等信息。

## 8. 数据模型 v1

### NoteSession

- id
- title
- createdAt
- updatedAt
- sourceLocale
- targetLocale
- duration
- status
- transcriptVersion
- summaryVersion
- mindMapVersion

### TranscriptSegment

- id
- sessionID
- startTime
- endTime
- originalText
- translatedText
- isFinal
- isEdited
- isHighlighted
- createdAt
- updatedAt

### SummaryRecord

- id
- sessionID
- title
- overview
- keyPoints
- decisions
- actionItems
- openQuestions
- sourceSegmentIDs
- generatedAt
- basedOnTranscriptVersion

### MindMapRecord

- id
- sessionID
- rootNode
- generatedAt
- basedOnTranscriptVersion

### MindMapNode

- id
- title
- summary
- type
- children
- sourceSegmentIDs
- isUserEdited

## 9. 建议模块拆分

```text
LiveNoteApp
├─ App
│  ├─ LiveNoteApp.swift
│  ├─ AppState.swift
│  └─ PermissionCoordinator.swift
│
├─ Features
│  ├─ Onboarding
│  ├─ Recording
│  ├─ Transcript
│  ├─ Translation
│  ├─ Summary
│  ├─ MindMap
│  └─ Export
│
├─ Services
│  ├─ AudioCaptureService
│  ├─ SpeechPipelineActor
│  ├─ TranslationService
│  ├─ SummaryService
│  ├─ MindMapService
│  └─ ExportService
│
├─ Persistence
│  ├─ SwiftDataModels
│  └─ SessionRepository
│
├─ DesignSystem
│  ├─ StatusCapsule
│  ├─ SegmentRow
│  ├─ SmartPanel
│  └─ MindMapCanvas
│
└─ Utilities
   ├─ LocaleSupport
   ├─ Versioning
   └─ ErrorPresenter
```

## 10. 技术 Spike 清单

### Spike 1：SpeechAnalyzer 实时转写

目标：

- 验证麦克风采集
- 验证 `SpeechAnalyzer` 输入流
- 验证 `SpeechTranscriber` 实时结果
- 验证中文 / 英文识别延迟

交付：

- 可以点击录音
- 可以看到实时原文
- 可以区分临时文本和稳定文本

### Spike 2：Translation 实时翻译

目标：

- 检查语言对可用性
- 对 finalized segment 翻译
- 验证实时翻译延迟
- 验证翻译失败状态

交付：

- 原文稳定后自动出现译文
- 支持重新翻译当前段

### Spike 3：Foundation Models 摘要与思维导图

目标：

- 生成结构化摘要
- 生成结构化思维导图节点
- 验证结构化输出稳定性
- 验证 Apple Intelligence 不可用时的降级状态

交付：

- 停止录音后生成摘要
- 停止录音后生成思维导图大纲

## 11. 六周实施计划

每个阶段都必须包含：

- 自动化测试：单元测试或集成测试，覆盖该阶段新增的核心逻辑。
- E2E 验收：至少一条用户路径验收，优先自动化 UI 测试；系统权限、麦克风输入、模型资源下载等无法稳定自动化的部分，需要记录人工验收步骤。
- 构建验证：阶段结束必须执行 `xcodebuild` 构建。
- 验收记录：阶段完成后把测试命令、结果和未覆盖风险写回本文档。

### 第 1 周：基础工程 + 权限 + 音频转写

- 用命令创建 macOS SwiftUI 项目骨架
- 搭建基础目录结构
- 搭建 SwiftData
- 完成首次启动检查页
- 完成麦克风权限
- 完成 AudioCaptureService
- 完成 SpeechAnalyzer 实时转写 Spike
- 添加单元测试与 E2E 启动验收

交付物：

- 可以录音并看到实时原文
- 自动化测试通过
- E2E 验收记录完成

### 第 2 周：会话与转写体验

- 会话列表
- 转写分段
- 临时文本 / 确认文本状态
- 段落编辑
- 高亮重点
- 时间戳
- 转写分段与编辑逻辑测试
- 录音页面 E2E 验收

交付物：

- 可用的实时会议记录页面

### 第 3 周：实时翻译

- TranslationService
- 语言选择
- 语言可用性检查
- 双语段落显示
- 重翻译当前段
- 翻译失败状态
- 翻译服务测试
- 双语显示 E2E 验收

交付物：

- 原文和译文可以稳定双栏显示

### 第 4 周：摘要与行动项

- SummaryService
- chunk summary
- 会后完整摘要
- 行动项提取
- 摘要来源段落回溯
- 编辑后版本过期提示
- 摘要结构化输出测试
- 会后总结 E2E 验收

交付物：

- 停止录音后自动生成会议总结

### 第 5 周：思维导图 + 导出

- MindMapService
- 思维导图数据结构
- SwiftUI 画布
- 节点展开 / 折叠 / 编辑
- Markdown / TXT 导出
- 思维导图节点模型测试
- 导出文件 E2E 验收

交付物：

- 可查看结构化会议思维导图并导出

### 第 6 周：打磨与稳定性

- 长会议性能优化
- 错误状态补齐
- Status Bar 溢出规则
- 空状态、加载状态、权限状态
- 本地数据清理
- UI 细节 polish
- 本地打包准备
- 回归测试
- 完整 MVP E2E 验收

交付物：

- MVP 可内测版本

## 12. 下一步执行建议

下一步先执行 Spike 1。

优先顺序：

1. 用命令生成 macOS SwiftUI 工程。
2. 添加最小权限配置。
3. 跑通麦克风音频输入。
4. 接入 `SpeechAnalyzer` 与 `SpeechTranscriber`。
5. 在最小 SwiftUI 页面展示实时转写结果。

Spike 1 成功后，再进入 Translation、Summary、MindMap 的实现。

## 13. 初始化执行记录

已完成：

- 使用 XcodeGen 作为命令式项目生成器。
- 创建最小 macOS 26 SwiftUI App 骨架。
- 生成 `LiveNote.xcodeproj`。
- 添加麦克风与语音识别权限说明。
- 添加 App Sandbox 音频输入 entitlements。
- 添加胶囊 Status Bar 的最小 SwiftUI 组件。
- 使用 `xcodebuild` 验证 Debug 构建成功。

已执行的关键命令：

```bash
mkdir -p LiveNote/App LiveNote/Features/Recording LiveNote/DesignSystem LiveNote/Supporting
xcodegen generate
xcodebuild -project LiveNote.xcodeproj -scheme LiveNote -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

下一步：

- 进入 Spike 1：接入麦克风实时音频流。
- 验证 `SpeechAnalyzer` 与 `SpeechTranscriber` 的最小实时转写链路。

## 14. Spike 1 执行记录

已完成：

- 添加麦克风权限协调器。
- 添加录音状态 ViewModel。
- 添加实时转写段落模型。
- 添加 `SpeechTranscriptionService`。
- 使用 `AVAudioEngine` 从麦克风采集音频。
- 使用 `SpeechAnalyzer.bestAvailableAudioFormat` 选择分析格式。
- 使用 `SpeechTranscriber` 输出临时文本与稳定文本。
- 在主界面显示实时识别结果。
- 对未安装但支持的语音资源尝试调用系统安装请求。
- 使用 `xcodebuild` 验证 Debug 构建成功。
- 添加单元测试 target。
- 添加 UI 测试 target。
- 将 macOS 右上角状态项从普通 `MenuBarExtra` 调整为 `NSStatusItem + NSPopover`，用于承载横向胶囊状态条与点击展开卡片。

已执行的验证命令：

```bash
xcodegen generate
xcodebuild -project LiveNote.xcodeproj -scheme LiveNote -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

阶段验收要求：

- 自动化构建必须通过。
- 单元测试必须通过。
- UI smoke test 必须通过。
- E2E 验收必须执行；如果命令行 UI 自动化受 macOS 权限或测试运行器限制，需要执行人工 E2E 并记录结果。
- 人工 E2E：运行 App，点击开始，授权麦克风，确认中文语音能产生临时文本和稳定文本。

当前测试记录：

- `xcodebuild ... build`：通过。
- `LiveNoteTests` 单元测试：通过。
- 默认 `LiveNote` scheme 测试命令通过：

  ```bash
  xcodebuild test -project LiveNote.xcodeproj -scheme LiveNote -configuration Debug -destination 'platform=macOS'
  ```

- 独立 `LiveNoteE2E` scheme UI smoke test 通过：

  ```bash
  xcodebuild test -project LiveNote.xcodeproj -scheme LiveNoteE2E -configuration Debug -destination 'platform=macOS'
  ```

- 自动截图验收暂未覆盖：当前自动化环境执行 `screencapture` 返回 `could not create image from display`，菜单栏胶囊需要人工视觉确认；详见 `e2e_spike1.md`。

下一步：

- 在本机运行 App，授予麦克风权限。
- 验证中文实时转写是否能产生临时文本和稳定文本。
- 人工确认 macOS 右上角 LiveNote 横向胶囊与点击展开状态卡片是否符合参考图。
- 根据运行结果调整音频格式转换、语言资源安装、错误提示和菜单栏胶囊视觉细节。
- Spike 1 运行验证通过后，进入 Spike 2：实时翻译。

## 15. Spike 2 执行记录

已完成：

- 扩展 `TranscriptSegment`，支持译文和翻译状态。
- 添加 `TranslationStatus`，区分未请求、翻译中、已翻译、不可用和失败。
- 添加 `TranslationServiceProtocol`。
- 添加基于 macOS Translation framework 的 `SystemTranslationService`。
- 使用本机 macOS 26 SDK 验证 `LanguageAvailability` 与 `TranslationSession` API 形态。
- 在稳定转写段落生成后自动触发中文到英文翻译。
- 临时识别文本不触发翻译。
- 中间转写区显示每个稳定段落的翻译状态与译文。
- 右侧 Smart Panel 添加翻译面板，显示稳定段落的原文和译文。
- 添加翻译行为单元测试。
- 扩展 UI smoke test，覆盖翻译面板初始状态。

已执行的验证命令：

```bash
xcodegen generate
xcodebuild test -project LiveNote.xcodeproj -scheme LiveNote -configuration Debug -destination 'platform=macOS'
xcodebuild test -project LiveNote.xcodeproj -scheme LiveNoteE2E -configuration Debug -destination 'platform=macOS'
```

当前测试记录：

- `LiveNote` 单元测试：通过，4 tests。
- `LiveNoteE2E` UI smoke test：通过，1 test。
- 真实麦克风语音转写和系统翻译资源下载需要人工 E2E；详见 `e2e_spike2.md`。

下一步：

- 人工验证中文实时转写到英文翻译链路。
- 根据真实运行结果调整翻译资源准备、错误提示和状态展示。
- 进入第 2 周会话与转写体验：会话列表、转写分段、段落编辑、高亮重点、时间戳。

## 16. 第 2 周转写体验执行记录

已完成：

- 添加 `NoteSession` 会话模型和会话状态。
- 扩展 `TranscriptSegment`，支持编辑标记、重点标记、更新时间和翻译状态。
- 左侧加入当前会话、最近会话和 `新建记录` 入口。
- 会话行改为可点击列表行，为后续会话切换做准备。
- 稳定转写段落支持编辑、保存、取消和重新翻译。
- 稳定转写段落支持标记重点，并同步更新当前会话统计。
- 停止录音后将当前会话归档到最近会话。
- 新建记录时归档已有会话、清空当前转写并恢复空状态。
- 启动时强制 `NavigationSplitView` 展开，保证侧边栏、工作区、智能面板在 E2E 中可见。
- 扩展单元测试覆盖编辑、重新翻译、重点统计和新建会话归档。
- 扩展 UI/E2E 覆盖会话侧边栏、新建记录入口、当前会话和最近会话。

已执行的验证命令：

```bash
xcodegen generate
xcodebuild test -project LiveNote.xcodeproj -scheme LiveNote -configuration Debug -destination 'platform=macOS'
xcodebuild test -project LiveNote.xcodeproj -scheme LiveNoteE2E -configuration Debug -destination 'platform=macOS'
```

当前测试记录：

- `LiveNote` 单元测试：通过，7 tests。
- `LiveNoteE2E` UI smoke test：通过，1 test。
- 人工麦克风转写、段落编辑、重点标记、停止归档和新建记录验收需要在真实 App 中执行；详见 `e2e_week2_transcript.md`。

下一步：

- 接入 SwiftData，持久化会话、转写段落、译文和用户编辑状态。
- 为会话切换补充选择态、详情读取和空数据恢复。
- 进入摘要 Spike：验证 macOS 26 Foundation Models 生成摘要、行动项和关键问题。

## 17. 第 3 周 SwiftData 持久化执行记录

已完成：

- 添加 SwiftData 存储模型，用于保存会话和转写段落。
- 添加 `NoteSessionStoreProtocol` 与 `NoteSessionStore`，把 SwiftData 访问封装在持久化层。
- App 启动时创建 SwiftData `ModelContainer`，并将 store 注入 `RecordingViewModel`。
- `RecordingViewModel` 支持启动加载已保存会话、保存当前会话、保存转写段落、保存译文、保存编辑状态和重点状态。
- 侧边栏会话行从占位点击变成真实会话切换入口。
- 会话切换时会读取对应段落，并恢复已保存译文与编辑状态。
- 为测试提取共用 `MockTranslationService`。
- 添加 ViewModel 持久化契约测试，覆盖保存后重启加载、编辑状态、重点状态和译文状态。

已执行的验证命令：

```bash
xcodegen generate
xcodebuild build -project LiveNote.xcodeproj -scheme LiveNote -configuration Debug -destination 'platform=macOS'
xcodebuild test -project LiveNote.xcodeproj -scheme LiveNote -configuration Debug -destination 'platform=macOS'
xcodebuild test -project LiveNote.xcodeproj -scheme LiveNoteE2E -configuration Debug -destination 'platform=macOS'
```

当前测试记录：

- `LiveNote` 单元测试：通过，9 tests。
- `LiveNoteE2E` UI smoke test：通过，1 test。
- SwiftData in-memory 容器在当前 Xcode/macOS 测试宿主中对 `@Model` 元数据触发系统级 `SIGTRAP`，因此本阶段单测覆盖持久化协议契约与 ViewModel 行为，生产 SwiftData 接线由 Debug build 与 E2E 启动测试覆盖。

下一步：

- 增加历史会话选择态和空历史体验。
- 人工验证真实 App 重启后可恢复转写、译文、编辑状态和重点标记。
- 进入摘要 Spike：验证 macOS 26 Foundation Models 生成摘要、行动项和关键问题。

## 18. 开始录音状态加固执行记录

已完成：

- 加固开始、暂停、停止、新建和切换会话的状态转换，处理中状态会禁用冲突操作。
- 开始录音时先进入处理中，转写服务真正启动成功后才进入录音中，避免启动失败后显示假录音状态。
- 转写服务错误回调会回到就绪状态并停止计时，避免菜单栏和主窗口状态残留。
- 菜单栏弹窗按钮复用主窗口的开始/停止可用性规则。
- 将音频 tap 的转换和 `AnalyzerInput` 推送移到非 MainActor helper，避免音频线程触发主 actor 队列断言。
- UI 测试启动时隔离 macOS 状态恢复，并改用稳定 accessibility identifier，避免持久化会话标题导致 E2E 脆弱。

已执行的验证命令：

```bash
xcodebuild test -project LiveNote.xcodeproj -scheme LiveNote -configuration Debug -destination 'platform=macOS'
xcodebuild test -project LiveNote.xcodeproj -scheme LiveNoteE2E -configuration Debug -destination 'platform=macOS'
```

当前测试记录：

- `LiveNote` 单元测试：通过，11 tests。
- `LiveNoteE2E` UI smoke test：通过，1 test。
- 真实麦克风 `SpeechAnalyzer` 点击开始仍需要在 Xcode 中人工复测，重点确认不再出现 `_dispatch_assert_queue_fail`，且菜单栏状态项不会因崩溃消失。

## 19. 历史空状态与摘要 Spike 执行记录

已完成：

- 最近会话默认改为空数组，移除 demo 历史数据。
- 侧边栏增加“暂无历史记录”空状态，并为当前会话增加“当前”标记。
- UI 测试模式改用 SwiftData in-memory 容器，避免本机历史数据污染 E2E。
- 新增 `MeetingSummary`、`SummaryGenerationStatus` 和 `SummaryServiceProtocol`。
- 验证 macOS 26 SDK 可 import `FoundationModels`，并接入 `SystemLanguageModel.default`、`LanguageModelSession` 和 `@Generable` 结构化摘要输出。
- `FoundationModelsSummaryService` 支持生成总览、行动项和关键问题，并显式处理无转写、设备不支持、Apple Intelligence 未开启和模型未就绪。
- 停止录音后自动触发摘要生成，右侧智能面板新增摘要状态页。
- 摘要生成支持手动重试；切换会话、新建会话、编辑原文或新增稳定段落时会取消/失效旧摘要，避免异步结果写入错误会话。
- 新增摘要 ViewModel 测试，覆盖生成、空转写不可用、编辑后摘要失效和新建会话取消挂起摘要。
- E2E smoke test 固定启动时不再出现 demo 最近会话。

已执行的验证命令：

```bash
xcodegen generate
xcodebuild test -project LiveNote.xcodeproj -scheme LiveNote -configuration Debug -destination 'platform=macOS'
xcodebuild test -project LiveNote.xcodeproj -scheme LiveNoteE2E -configuration Debug -destination 'platform=macOS'
```

当前测试记录：

- `LiveNote` 单元测试：通过，19 tests。
- `LiveNoteE2E` UI smoke test：通过，1 test。
- Foundation Models 真实摘要内容仍需要在 Apple Intelligence 可用设备上人工验收；当前自动化覆盖接口接线、状态转换、错误状态和取消逻辑。

下一步：

- 为摘要结果增加 SwiftData 持久化和历史会话恢复。
- 接入思维导图大纲生成，并复用摘要的可用性、取消和会话隔离规则。
- 人工验证停止录音后摘要面板在 Apple Intelligence 未开启、模型未就绪和可用三种环境下的 UI 表现。

## 20. 摘要持久化与思维导图 Spike 执行记录

已完成：

- 新增 `SummaryRecord`，记录摘要内容、来源段落、生成时间和基于转写版本。
- SwiftData schema 增加 `PersistentSummaryRecord`，并把摘要与会话关联保存。
- `NoteSessionStoreProtocol` 增加摘要读取、保存和删除接口；真实 SwiftData store 与测试 in-memory store 均已实现。
- 摘要生成成功后自动持久化；重启或切换历史会话时会恢复仍匹配当前转写版本的摘要。
- 新增摘要版本校验；转写段落新增或编辑后会清除旧摘要，避免展示过期内容。
- 新增 `MindMap`、`MindMapNode`、`MindMapGenerationStatus` 和 `MindMapServiceProtocol`。
- `FoundationModelsMindMapService` 接入 `SystemLanguageModel.default`，支持生成结构化会议导图大纲，并处理无转写、设备不支持、Apple Intelligence 未开启和模型未就绪。
- 停止录音后会同时触发摘要与思维导图生成；右侧智能面板新增思维导图 tab、生成按钮、空状态、加载状态、错误状态和树形大纲展示。
- 思维导图生成复用摘要的异步防串会话规则：切换会话、新建会话、编辑原文或新增稳定段落时会取消/失效旧结果。
- 新增摘要持久化、SwiftData 摘要存取、思维导图 ViewModel 测试，覆盖生成、空转写不可用、编辑失效和新建会话取消挂起任务。

已执行的验证命令：

```bash
xcodegen generate
xcodebuild test -project LiveNote.xcodeproj -scheme LiveNote -configuration Debug -destination 'platform=macOS'
xcodebuild test -project LiveNote.xcodeproj -scheme LiveNoteE2E -configuration Debug -destination 'platform=macOS'
```

当前测试记录：

- `LiveNote` 单元测试：通过，26 tests。
- `LiveNoteE2E` UI smoke test：通过，1 test。
- 期间 `LiveNoteE2E` 曾因一个挂在 `debugserver` 下的残留 `LiveNote` 测试进程无法终止而失败；清理残留进程后重跑通过，失败点不是应用断言。
- Foundation Models 真实摘要与思维导图内容仍需要在 Apple Intelligence 可用设备上人工验收。

下一步：

- 为思维导图结果增加 SwiftData 持久化和历史会话恢复。
- 进入思维导图画布交互：节点展开 / 折叠 / 编辑。
- 开始 Markdown / TXT 导出路径，并覆盖导出文件 E2E。

## 21. 思维导图持久化与历史恢复执行记录

已完成：

- 新增 `MindMapRecord`，记录根节点、来源段落、生成时间和基于转写版本。
- `MindMap` 与 `MindMapNode` 支持 `Codable`，SwiftData 通过 JSON `Data` 保存完整树结构。
- SwiftData schema 增加 `PersistentMindMapRecord`，并把思维导图与会话关联保存。
- `NoteSessionStoreProtocol` 增加思维导图读取、保存和删除接口；真实 SwiftData store 与测试 in-memory store 均已实现。
- 思维导图生成成功后自动持久化；重启或切换历史会话时会恢复仍匹配当前转写版本的导图。
- 新增导图版本校验；转写段落新增或编辑后会删除旧导图，避免展示过期结构。
- 新增 SwiftData 思维导图存取测试和 ViewModel 恢复/失效测试。

已执行的验证命令：

```bash
xcodegen generate
xcodebuild test -project LiveNote.xcodeproj -scheme LiveNote -configuration Debug -destination 'platform=macOS'
xcodebuild test -project LiveNote.xcodeproj -scheme LiveNoteE2E -configuration Debug -destination 'platform=macOS'
```

当前测试记录：

- `LiveNote` 单元测试：通过，29 tests。
- `LiveNoteE2E` UI smoke test：通过，1 test。
- Foundation Models 真实思维导图内容仍需要在 Apple Intelligence 可用设备上人工验收。

下一步：

- 进入思维导图画布交互：节点展开 / 折叠 / 编辑。
- 节点编辑后持久化用户修改，并避免后台生成覆盖用户编辑。
- 开始 Markdown / TXT 导出路径，并覆盖导出文件 E2E。

## 22. 思维导图交互与 Markdown / TXT 导出执行记录

已完成：

- 思维导图节点支持展开、折叠、编辑标题和摘要。
- 节点折叠和编辑都会标记 `isUserEdited`，并通过现有 SwiftData 思维导图记录持久化。
- 历史会话恢复时会恢复用户编辑后的节点标题、摘要和折叠状态。
- 新增独立 `SessionExportBuilder`，支持 Markdown 和 TXT 输出。
- 导出选项支持选择原文、译文、摘要与行动项、思维导图大纲。
- 导出内容会过滤未确认的临时转写段落，避免把识别中的 volatile 内容写入文件。
- 导出入口挂到主工具栏，使用系统保存面板选择位置；取消导出、空选择、空内容、写入失败都会显示状态信息，不改变录音状态。
- App Sandbox 增加用户选择文件读写权限，保证保存面板选择的导出路径可写。
- E2E smoke test 增加导出弹窗打开 / 取消覆盖，确认点击导出后主窗口仍可回到录音入口。

已执行的验证命令：

```bash
xcodegen generate
xcodebuild test -project LiveNote.xcodeproj -scheme LiveNote -configuration Debug -destination 'platform=macOS'
xcodebuild test -project LiveNote.xcodeproj -scheme LiveNoteE2E -configuration Debug -destination 'platform=macOS'
```

当前测试记录：

- `LiveNote` 单元测试：通过，36 tests。
- `LiveNoteE2E` UI smoke test：通过，1 test。
- E2E 覆盖启动工作区、导出按钮、导出弹窗打开、取消导出和回到录音按钮。
- 真实保存面板写入路径仍建议人工验收一次，单元测试已覆盖 ViewModel 写入临时文件。

下一步：

- 增加导出文件人工 / 自动 E2E 的真实保存路径覆盖。
- 继续第 6 周打磨与稳定性：完整 MVP E2E、异常状态提示、空状态和权限路径复核。

## 23. 第 6 周打磨与完整 MVP 验收执行记录

已完成：

- 转写工作区增加原文 / 译文搜索、匹配计数、清除搜索和段落定位；摘要来源与思维导图节点支持回溯定位到原文段落。
- 翻译面板增加目标语言选择、全部重新翻译和单段重新翻译，切换目标语言后会重新生成稳定段落译文。
- 会话状态转换继续加固：处理中状态会阻止开始、停止、切换、编辑、删除等冲突操作，避免点击后进入不一致状态。
- 本地数据清理完成：持久化层支持删除单条会话和清空全部会话，清空会同步删除转写、摘要和思维导图产物。
- 导出 E2E 增加真实文件写入路径覆盖，UI 测试模式下可绕过保存面板写入指定 Markdown 文件并校验文件内容。
- 导出弹窗状态提升到根视图，避免工具栏按钮触发 sheet 时主窗口和工具栏状态不稳定。
- 完成包含已完成会话的 UI 测试 fixture，用于覆盖摘要、思维导图、导出和清空记录的完整路径。

已执行的验证命令：

```bash
xcodegen generate
xcodebuild test -project LiveNote.xcodeproj -scheme LiveNote -configuration Debug -destination 'platform=macOS'
xcodebuild test -project LiveNote.xcodeproj -scheme LiveNoteE2E -configuration Debug -destination 'platform=macOS'
```

当前测试记录：

- `xcodegen generate`：通过。
- `LiveNote` 单元测试：通过，42 tests。
- `LiveNoteE2E` UI 测试：通过，2 tests。
- E2E 覆盖启动工作区、Status Capsule、工具栏开始 / 停止 / 导出入口、已完成会话 fixture、Markdown 文件真实写入、导出内容校验和清空本地记录。

仍需人工验收：

- 真实麦克风输入下点击开始、暂停、继续、停止，确认不会崩溃，且 macOS 右上角菜单栏状态项不会消失。
- 中文语音实时转写、系统语音资源安装提示和 Translation framework 资源下载流程。
- Apple Intelligence / Foundation Models 在可用、未开启、模型未就绪等真实系统状态下的摘要与思维导图表现。
- 非 UI 测试模式下通过系统保存面板选择用户目录并导出 Markdown / TXT 文件。
- 长会议真实场景性能，包括大量段落滚动、搜索定位、翻译重试和历史会话恢复。

阶段结论：

- 第 6 周自动化范围内的打磨和完整 MVP 回归已完成。
- 当前版本达到 MVP 内测候选状态；剩余风险集中在系统权限、真实麦克风、系统模型资源和真实保存面板这类无法稳定自动化的 macOS 外部状态。
