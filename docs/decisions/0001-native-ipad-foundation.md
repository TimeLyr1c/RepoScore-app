# 使用原生 iPad 应用基础

## Status
Accepted — 2026-10-12

## Context

RepoScore 面向 iPad，管理应用内的 PDF 副本，并提供离线阅读及文件夹组织。用户授权进入 bootstrap，目前只需最小可运行基础。

## Decision

使用 Swift / SwiftUI 和直接纳入 Git 的 Xcode 工程。最低系统暂设为 iPadOS 17.0，仅支持 iPad；计划使用系统 PDFKit 阅读 PDF。不引入第三方依赖、后端或工程生成工具。

## Reasons

原生系统能力与文件导入、PDF 阅读及 iPad 使用场景相符。直接打开 Xcode 工程即可构建，避免为两个入口视图增加额外工具和生成步骤。

## Consequences

M0 只实现曲库空状态。PDFKit 的实际阅读行为在 M1 验证；持久化细节在实现独立副本导入时决定。iPadOS 17.0 是可调整的初始技术选择，不是已确认的用户设备限制。后续系统版本调整需更新工程及当前文档。

## Alternatives considered

- 跨平台应用：目前只有 iPad 产品范围，额外的平台层缺少实际收益。
- 第三方 PDF SDK：MVP 不包含标注和 PDF 内容编辑，先验证系统能力，无需现在增加依赖。
- 工程生成器：当前工程很小，额外安装和生成步骤没有必要。
