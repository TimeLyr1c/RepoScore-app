# RepoScore

面向 iPad 的轻量乐谱 PDF 阅读与管理工具。导入后保存独立副本，离线阅读，用文件夹收纳；完整范围见 [产品定义](docs/PRODUCT.md)。

## 当前状态

M2：支持独立 PDF 副本导入、文件夹及子文件夹、重命名、乐谱移动、单双页阅读和可选独立封面。阅读支持边缘点击、左右滑动和按钮翻页；演出功能、删除及持久阅读进度未实现。见 [路线图](docs/ROADMAP.md)、[架构](docs/ARCHITECTURE.md) 和 [技术决策](docs/decisions/0001-native-ipad-foundation.md)。

## 开发环境

- macOS 和完整 Xcode（本轮验证使用 Xcode 27.0）。
- iPadOS 17.0 或更新版本；运行模拟器需安装对应的 iOS Simulator runtime。
- 无第三方依赖，无需包管理器、后端或工程生成工具。

打开 `RepoScore.xcodeproj`，选择 `RepoScore` scheme 和一个 iPad 模拟器，执行 Run。真机运行需自行选择开发团队并配置签名；工程未保存团队信息。

## 命令行构建

如果系统 `xcode-select` 指向 Command Line Tools，可只为当前命令指定完整 Xcode，不必修改系统设置：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project RepoScore.xcodeproj -scheme RepoScore \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

产物：`build/DerivedData/Build/Products/Debug-iphonesimulator/RepoScore.app`。这是未签名模拟器构建，不适用于直接安装到真实 iPad。

## 模拟器启动验证

先查看可用 iPad：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl list devices available
```

用实际 iPad 模拟器 UUID 替换下面的 `<IPAD_UUID>`。若设备已经启动，跳过 boot：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl boot <IPAD_UUID>
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl bootstatus <IPAD_UUID> -b
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl install <IPAD_UUID> build/DerivedData/Build/Products/Debug-iphonesimulator/RepoScore.app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl launch <IPAD_UUID> com.timelyr1c.RepoScore
```

首次运行应出现 RepoScore 标题及“曲库为空”，可点击“导入乐谱”选择 PDF。当前目录导入后从列表打开，滑动、点击左右边缘或使用上一页/下一页按钮阅读。阅读为全屏，点按中间显示或隐藏工具栏，点击边缘或滑动翻页时工具栏自动隐藏。右上角“阅读设置”可切换自动/单页/双页及封面方式（自动为横屏双页、竖屏单页）；阅读会话内保持选项和当前物理页。返回曲库使用导航栏返回按钮。需要密码解锁的 PDF 暂不支持；同名导入会保留不同副本。

## 自动化测试

将 `<IPAD_UUID>` 替换为可用 iPad 模拟器 UUID：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project RepoScore.xcodeproj -scheme RepoScore \
  -destination 'platform=iOS Simulator,id=<IPAD_UUID>' \
  -derivedDataPath build/DerivedData -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO test
```

RepoScoreTests 使用独立临时目录测试导入和索引，不改动实际曲库；RepoScoreUITests 使用隔离的测试曲库，检查文件选择器打开/取消、PDF 阅读与重启恢复和错误弹窗。生成 PDF 通过 Debug 专用入口交给正常 repository 导入；该路径不验证 Files 提供者权限。普通启动不会导入测试数据，Release 不包含测试入口。M2 还检查索引迁移、层级及写入失败、配对、移动/重启、阅读模式、边缘点击和旋转。具体运行结果见 ROADMAP。

## 手动验收（真实 iPad 待验证）

1. 通过 Files 导入一份多页 PDF，从曲库打开并翻页。
2. 关闭应用、删除外部原文件并断网，重新打开应用及已导入乐谱。
3. 导入同名不同内容的 PDF，确认两个副本都可打开。
4. 尝试无效 PDF，确认错误提示且没有新增曲库记录；取消选择不报错。
5. 创建文件夹及子文件夹，长按或左滑文件夹行重命名，长按或左滑乐谱行选择“移动”，进入目标文件夹并确认；根目录也是合法目标。重启后核对层级和归属。
6. 横屏打开乐谱，确认默认双页且两页占满屏幕、中缝无间隙；翻页后工具栏隐藏，点按中间恢复。在阅读设置中选择双页，分别检查独立封面和从第一页配对；末尾剩余一页应居中独立显示。切换模式、封面选项或旋转后当前物理页仍可见。
7. 验证真实乐谱清晰度、左右边缘点击和滑动、双击/捏合缩放及放大后平移。翻页和旋转会恢复页面适配；设置/进度不跨次打开持久保存。

文件夹名去除首尾空白；同一层级忽略大小写比较，不允许同名。已有 version 1 曲库先保留 index-v1-backup-<UUID>.json，再升级为 version 2；PDF 路径不变。这是索引迁移备份，不是完整曲库备份。

曲库副本与索引保存在应用的 Application Support/RepoScore 中，不依赖外部文件或登录。尚无导出/备份/恢复界面；卸载应用可能删除本地曲库。模拟器检查不代替真实 iPad 验收。

## 协作约定

遵循 [AGENTS.md](AGENTS.md)。产品范围记录在 PRODUCT，当前实现记录在 ARCHITECTURE，进度记录在 ROADMAP，重要技术选择记录在 `docs/decisions/`。保留 `.template.md` 作为参考；模板内容不代表已实现设计。

采用小而完整的 Conventional Commits；未经授权不推送或发布。
