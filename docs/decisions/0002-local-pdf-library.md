# 本地 PDF 副本与 JSON 曲库索引

## Status
Accepted — 2026-10-12

## Context

M1 需要可靠保存用户导入的 PDF，并在外部原文件移除及应用重启后继续阅读。当前只有根目录中的乐谱，不需要关系查询或同步。

## Decision

在 Application Support/RepoScore 中保存 `PDFs/<UUID>.pdf` 和版本为 1 的 `index.json`。索引只包含 ID、显示标题、页数及导入时间；路径由 ID 推导，不保存外部 URL 或持续访问书签。

repository 用 actor 串行处理加载及导入。导入期间临时取得安全作用域访问，用 NSFileCoordinator 读取来源到 Staging，使用 PDFKit 检查副本，再移到 PDFs 并原子写入完整索引。索引写入失败时回滚本次副本，内存记录不更新。来源文件保持不变。

## Reasons

少量 Codable 元数据和独立文件足以完成当前用例，无第三方依赖或数据库维护成本。UUID 避免同名文件覆盖；复制后无需外部文件的持续权限。系统文件选择器的安全作用域访问与释放遵循 [Apple fileImporter 文档](https://developer.apple.com/documentation/swiftui/view/fileimporter(ispresented:allowedcontenttypes:oncompletion:))。

## Consequences

- 同名或重复导入保留为不同项目；本阶段不做去重或重命名交互。
- 暂不支持需要密码解锁的 PDF，导入时明确报错；已有 PDF 内的静态标注可能由 PDFKit 显示，但应用不新增或编辑标注。
- 无效索引会阻止导入并保留原文件，避免以空曲库覆盖已有资料。丢失副本保留记录，打开时提示失败。
- 正常失败清理临时文件；再次加载时清理中断的 Staging。若进程在副本移入 PDFs 后、索引提交前中断，可能留下未索引的副本；为避免误删数据，本阶段保留，不自动清除或宣称两文件事务具有崩溃原子性。
- 使用系统沙箱存储，未实现导出、备份或恢复 UI；不改变系统备份策略。删除应用可能删除本地曲库。
- 文件夹层级在 M2 扩展索引时设计迁移；不提前加入标签等未实现数据。

## Alternatives considered

- 外部文件引用或持续书签：不能满足独立副本的产品要求。
- SwiftData/SQLite：当前没有需要数据库的查询和关系，先用小索引；若后续数据规模或关系需求证明有必要，再迁移。

## M2 扩展

版本 1 是 M1 的初始格式。M2 使用版本 2 保存文件夹关系，原始版本 1 索引在迁移前保留为副本，见 [ADR 0003](0003-folder-index-migration.md)。UUID 命名的 PDF 及原子提交原则继续使用；当前结构以 ARCHITECTURE 为准。
