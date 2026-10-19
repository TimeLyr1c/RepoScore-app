# RepoScore — Architecture

## 当前状态

M2 已实现文件夹层级、重命名、乐谱移动与单双页阅读，保留 M1 独立副本导入和曲库恢复。功能与模拟器验证完成；演出功能未实现，真机验收待完成。

## 技术选择

- 原生 Swift / SwiftUI，Xcode 工程直接纳入版本控制，不引入工程生成器或第三方依赖。
- 当前 deployment target 为 iPadOS 17.0，设备范围为 iPad，支持四种屏幕方向。最低版本是 bootstrap 技术选择，可在用户设备需求明确后调整。
- 工程使用 Swift 5 language mode；本轮验证环境为 Xcode 27.0。
- PDF 阅读使用系统 PDFKit。PageLayout 显式计算页组，UIViewRepresentable 包装最多两个单页 PDFView，统一处理左右点击、滑动与按钮翻页。见 [ADR 0004](decisions/0004-explicit-pdf-spreads.md)。
- 无后端、账户或网络服务。依据见 [ADR 0001](decisions/0001-native-ipad-foundation.md)。

## 工程结构

- `RepoScore.xcodeproj`：应用 target、构建设置和共享 scheme。
- `RepoScore/RepoScoreApp.swift`：应用入口。
- `RepoScore/LibraryView.swift`：分层曲库、文件夹编辑、导入入口、移动目标选择和错误提示。
- `RepoScore/LibraryStore.swift`：主线程可观察的加载/导入状态。
- `RepoScore/Score.swift`、`ScoreRepository.swift`：元数据及串行本地持久化。
- `RepoScore/PageLayout.swift`：单双页、封面偏移及前后页组规则。
- `RepoScore/ScoreReaderView.swift`：页组 PDF 渲染、阅读设置、适配和手势。
- `RepoScoreTests`、`RepoScoreUITests`：持久化行为测试和系统文件选择器检查。
- `docs/PRODUCT.md`：产品范围和 MVP 验收标准。
- `docs/ROADMAP.md`：实施顺序及验证状态。

## 已实现数据流与存储

系统文件选择器 → 临时安全作用域访问与协调读取 → 复制到 Staging → PDFKit 验证 → 保存 UUID 命名的 PDF → 原子提交 JSON 索引 → 曲库显示 → PDFKit 打开本地副本。

导入及索引操作在 repository actor 中串行执行，复制不占用 UI 主线程；LibraryStore 在主线程发布状态；App 持有一个共享 store，各窗口使用同一个 repository，避免分别写入过期索引。PDF 打开在后台加载，显示及页面事件由主线程 PDFView 处理。

Application Support/RepoScore/PDFs 保存副本；index.json 使用 version 2，保存乐谱 ID、标题、页数、导入时间、folderID，以及文件夹 ID、名称和 parentID。version 1 先备份原始字节再原子升级，见 [ADR 0003](decisions/0003-folder-index-migration.md)。索引损坏时显示读取失败并禁止继续导入，保留已有数据。写入失败回滚本次副本；下次成功加载时清理 Staging。完整选择及崩溃窗口限制见 [ADR 0002](decisions/0002-local-pdf-library.md)。

文件夹层级保存在索引中；PDF 物理路径仍由 ID 决定，重命名或移动只提交索引，不移动文件。同层名称唯一；验证 parentID、folderID、名称和循环引用。文件夹按创建顺序、乐谱按导入顺序显示。标签、乐器、专辑等未建模。

## 验证方式

Xcode XCTest 验证副本独立性、重启恢复、同名导入、无效来源、索引失败回滚、损坏索引保护、临时文件清理、索引迁移与文件夹层级。PageLayout 测试枚举单双页及两种封面方式，检查无遗漏/重复、边界和位置锚点；UI 测试验证文件选择器打开/取消、阅读与翻页、重新启动后的本地恢复，以及导入失败提示。精确命令与手动验收步骤见 README。

Debug 构建提供仅供 UI 测试的环境变量入口：有效的 REPOSCORE_UI_TEST_SESSION UUID 选择独立测试曲库，REPOSCORE_UI_TEST_PDF 可传入生成 PDF。种子经正常 repository 导入后删除来源；重新启动不再提供种子，以验证持久化。普通启动不启用此入口，Release 编译不包含它。PDF 种子测试绕过文件选择器，不能作为 Files 提供者真实导入验收。

真实 iPad 仍需验证 Files 提供者的权限/下载行为、断网后打开独立副本、触摸翻页及横竖屏阅读。模拟器与生成 PDF 的测试不替代真实乐谱或真机验收。

## 当前限制与后续决定

- 尚无应用图标和发布用资产；在发布准备阶段补齐。
- Bundle ID `com.timelyr1c.RepoScore` 是当前本地默认值，发布前需确认；未配置开发团队或真机签名。
- 删除、文件夹移动和持久阅读设置/进度尚未实现。缩放在翻页和旋转时恢复适配，真实大乐谱性能待测。
- 发布渠道与商业安排尚未确定，不影响本地 bootstrap。
