# Mac Monitor

[![CI](https://github.com/mac-fantasy/mac-monitor/actions/workflows/ci.yml/badge.svg)](https://github.com/mac-fantasy/mac-monitor/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/mac-fantasy/mac-monitor)](https://github.com/mac-fantasy/mac-monitor/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A native Apple Silicon menu bar monitor for CPU, GPU, memory, and per-process usage.

原生 Apple Silicon 菜单栏资源监控。使用 Swift 6、AppKit 和 SwiftUI，最低支持 macOS 14；构建产物仅包含 arm64。

## 使用

通过组织的 [统一 Homebrew tap](https://github.com/mac-fantasy/homebrew-tap) 安装：

```bash
brew install --cask mac-fantasy/tap/mac-monitor
```

仅支持 Apple Silicon、macOS 14+。tap 每 6 小时同步最新稳定版 Release；应用当前没有内置更新器，通过以下命令升级：

```bash
brew update
brew upgrade --cask mac-fantasy/tap/mac-monitor
```

普通卸载使用 `brew uninstall --cask mac-fantasy/tap/mac-monitor`，保留设置；加 `--zap` 会清理设置。若已手动安装 `MacMonitor.app`，先退出并移走旧应用后再通过 Homebrew 安装。

从 [GitHub Releases](https://github.com/mac-fantasy/mac-monitor/releases/latest) 下载 DMG 或 ZIP。DMG 中将应用拖入 Applications 即可安装；同页提供 SHA-256 校验文件。当前自动构建为 **ad-hoc 签名，未经 Developer ID 签名和公证**，系统可能限制首次打开；也可以从源码构建：

```bash
./scripts/build-app.sh --run
```

应用生成在 `dist/MacMonitor.app`，可以直接双击运行，也可以拖入「应用程序」文件夹。运行后只出现在菜单栏，不显示 Dock 图标和主窗口。

界面预览：[浅色概览](docs/overview-light.png) · [深色概览](docs/overview-dark.png) · [设置](docs/settings.png)。

- 默认显示 **同心圆图标**：外环为内存（橙色），内环为 CPU（蓝色），中心小数字为 GPU（紫色）。圆环保留完整的淡色底轨，亮色弧线表示已用比例；中心数字以百分比为单位，省略 `%` 符号。
- 点击菜单栏图标，查看三个维度各自的 **Top 5 进程**，包含实际占用和相对分布。
- 点击任一区块右侧的「更多」，在同一个弹窗中查看完整进程列表；列表可以滚动，左上角返回概览。
- 右上角设置可为外环、内环和中心数字分别选择 CPU、GPU 或内存，并实时预览。选择其他位置已有的指标时，两者交换位置，颜色跟随指标。
- 设置也可以隐藏任意维度、选择 1/2/3/5 秒刷新间隔、开启圆环旁的百分比。至少保留一个维度；隐藏的指标不在菜单栏和概览显示，其位置分配仍会保留。
- 设置自动保存在本机，关闭并重新运行后仍然有效。
- 弹窗没有文本输入框，不会自动聚焦按钮或输入控件；点击外部关闭，底部电源按钮退出应用。
- 适配系统浅色和深色外观，小屏幕中概览可以滚动。

## 开发

项目同时提供 Swift Package 和 Xcode 工程，均无需第三方运行时依赖。

```bash
# 编译和测试
swift build --arch arm64
swift test --arch arm64

# 实际采样两次，打印系统指标和三个 Top 5
swift run --arch arm64 MonitorProbe

# 重新生成 Xcode 工程（需要 XcodeGen）
xcodegen generate
open MacMonitor.xcodeproj

# 用 Xcode 命令行验证
xcodebuild -project MacMonitor.xcodeproj -scheme MacMonitor \
  -configuration Debug -derivedDataPath .build/xcode \
  CODE_SIGNING_ALLOWED=NO build

# 构建可运行的 .app，自动生成图标并进行本机 ad-hoc 签名
./scripts/build-app.sh
```

应用内渲染和状态诊断仅包含在 Debug 构建中，不进入 Release 应用：

```bash
swift build --arch arm64
"$(swift build --arch arm64 --show-bin-path)/MacMonitor" \
  --ui-self-test "$PWD/.build/ui-checks"
```

诊断生成概览、CPU/GPU/内存完整列表、设置页的 PNG 和 `ui-report.json`。诊断使用隔离的偏好设置，不修改日常设置，不需要辅助功能或录屏权限。它直接验证应用内部状态，不替代真实鼠标点击的交互验收。

## 数据口径

| 指标 | 实现与口径 |
| --- | --- |
| 整机 CPU | Mach `host_statistics(HOST_CPU_LOAD_INFO)`，以两次 tick 差计算所有核心的平均忙碌比例，范围 0–100%。 |
| 进程 CPU | `proc_pid_rusage` 累计 CPU 时间的增量，经 `mach_timebase_info` 转为纳秒；100% 表示一个核心，多核进程可超过 100%。 |
| 受保护进程 | 使用系统 `/bin/ps` 读取基础 CPU 时间和 RSS，无 shell、无 sudo、无自建特权助手。CPU 仍按采样间隔求差；RSS 在界面加 `≈`，与物理内存 footprint 区分。 |
| 整机 GPU | IOKit `IOAccelerator` 的 `PerformanceStatistics["Device Utilization %"]`。 |
| 进程 GPU | 读取驱动客户端 `IOUserClientCreator` 和 `AppUsage[].accumulatedGPUTime`，按客户端标识求差后按 PID 汇总；显示驱动能提供计数的进程。 |
| 整机内存 | `HOST_VM_INFO64`：应用内存（internal − purgeable）＋ wired ＋压缩器实际占用，以物理内存总量为分母。文件缓存不计入已用。 |
| 进程内存 | `ri_phys_footprint`；系统限制读取时退回 RSS，并明确标记。不同进程存在共享、内核和统计口径差异，不能直接相加作为整机内存。 |

CPU 和 GPU 的逐进程百分比与整机百分比口径不同，不应把 Top 5 的百分比相加后与菜单栏数字比较。首次打开弹窗需要约 0.8 秒建立进程增量基线，期间显示采样状态。驱动未提供逐进程 GPU 计数时，显示不可用状态；读取失败的进程显示 `—`。

## 性能与验证

每次采样的排序只计算一次；菜单栏图像仅在整数百分比、布局、显示数字或外观变化时更新。曲线历史只保存最近两分钟的整机数值，不保留进程数组。隐藏的维度不做整机查询；单一维度的进程页只查询相应进程数据，设置页及弹窗关闭时不扫描进程。GPU 注册表句柄、客户端归属和短期权限拒绝结果会复用，同时处理失效和 PID 重用。

基准命令和本机测量结果见 [性能记录](docs/performance.md)。13 项核心测试和应用内界面检查覆盖计数回绕、进程替换、排序、显示设置及采样范围。CI 在原生 arm64 的 macOS 15 和 26 上执行测试与应用构建。

## 自动发布

推送版本 tag 即触发 [Release workflow](.github/workflows/release.yml)，无需手工上传安装包：

```bash
git tag -a v0.2.0 -m "Mac Monitor v0.2.0"
git push origin v0.2.0
```

流程会测试、构建 arm64 应用、将 tag 版本写入 Info.plist、验证签名和配置、生成 DMG / ZIP / SHA-256，上传后再正式发布 GitHub Release。`v0.2.0-beta.1` 等 tag 会创建预发布版本。也接受 `0.2.0`、`v0.2` 格式，包内版本统一为三段数字；其他非版本 tag 会被校验拒绝。已发布版本在重跑时保持不变；未完成的草稿可以继续上传发布。

`VERSION` 为本地构建的默认版本，发布构建使用 tag 的版本。只给发布任务 `contents: write` 权限，普通 CI 只读；使用固定提交的官方 Actions。工作流也支持输入已存在的 tag 后手动重跑。

GPU 属性由 Apple 驱动提供，未作为稳定的公开 API 承诺，未来 macOS 版本可能调整字段。实现没有把整机利用率按进程猜测分配。参考：[Apple XNU 的进程资源统计实现](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/bsd_kern.c)、[AGX 累计 GPU 时间的公开实现示例](https://github.com/longbridge/gpui-kit/blob/main/crates/fps/src/gpu/macos.rs)、[NSPopover 文档](https://developer.apple.com/documentation/appkit/nspopover)。

## 结构

```text
Sources/MonitorCore/       系统采样、计数差分、排序和受保护进程基础统计
Sources/MacMonitor/        菜单栏绘制、NSPopover、SwiftUI 界面和偏好设置
Sources/MonitorProbe/      与应用共用采样器的命令行诊断
Tests/MonitorCoreTests/    时间差、计数回绕、PID 重用、GPU 客户端退出等测试
Resources/                Info.plist、应用图标
scripts/                  打包和原生矢量绘制图标的脚本
project.yml               XcodeGen 工程定义
```

采样在独立 actor 中完成，界面在 MainActor 更新。应用不访问网络，也不上传采样数据。为了读取其他进程，本项目不开启 App Sandbox。

当前产物采用本机 ad-hoc 签名。向其他 Mac 分发时，应使用自己的 Developer ID 签名并进行 notarization；Xcode 中的 Signing 设置可用于配置证书。

本项目以 [MIT License](LICENSE) 开源。欢迎提交 Issue 或 Pull Request，开发约定见 [CONTRIBUTING.md](CONTRIBUTING.md)。
