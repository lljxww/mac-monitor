import AppKit
import MonitorCore
import SwiftUI

struct PopoverView: View {
    @ObservedObject var store: MonitorStore
    @ObservedObject var preferences: MonitorPreferences
    let height: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            header
            switch store.route {
            case .overview: overview
            case let .processes(metric): fullList(metric)
            case .settings: settings
            }
            footer
        }
        .frame(width: 410, height: height)
        .background(.regularMaterial)
        .environment(\.defaultMinListRowHeight, 0)
        .environment(\.controlActiveState, .active)
        .focusEffectDisabled()
    }

    private var header: some View {
        HStack(spacing: 10) {
            if store.route == .overview {
                StatusItemPreview(snapshot: store.snapshot, layout: preferences.statusItemMetrics,
                                  visibleMetrics: preferences.visibleMetrics, size: 26)
                .frame(width: 34, height: 34)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Mac Monitor").font(.system(size: 16, weight: .semibold))
                    Text("\(store.snapshot.chipName) · \(store.snapshot.coreCount) 核")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            } else {
                IconButton(symbol: "chevron.left", label: "返回资源概览") { store.route = .overview }
                VStack(alignment: .leading, spacing: 3) {
                    Text(routeTitle).font(.system(size: 16, weight: .semibold))
                    Text(store.route == .settings ? "按你的习惯显示" : "全部进程 · 实时排序")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if store.route != .settings {
                IconButton(symbol: "slider.horizontal.3", label: "设置") { store.route = .settings }
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
    }

    private var routeTitle: String {
        switch store.route { case .overview: "Mac Monitor"; case .settings: "设置"; case let .processes(metric): "\(metric.title) 进程" }
    }

    private var overview: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack {
                    Text("资源概览").font(.system(size: 11, weight: .medium))
                    Spacer()
                    Text("TOP 5").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.5)
                }
                .foregroundStyle(.secondary).padding(.horizontal, 2).padding(.bottom, 1)
                ForEach(preferences.orderedMetrics) { metric in metricCard(metric) }
            }
            .padding(.horizontal, 16).padding(.bottom, 16)
        }
        .scrollIndicators(.never)
    }

    private func metricCard(_ metric: Metric) -> some View {
        let processes = store.snapshot.rankedProcesses(for: metric)
        let top = Array(processes.prefix(5))
        let maximum = max(processes.first?.value(for: metric) ?? 0, 0.001)
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: metric.symbol).font(.system(size: 14, weight: .medium)).foregroundStyle(metric.color)
                    .frame(width: 21)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(metric.title).font(.system(size: 12, weight: .semibold))
                        Text(DisplayFormat.percent(store.snapshot.percent(for: metric)))
                            .font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit()
                    }
                    Text(metricSubtitle(metric)).font(.system(size: 9)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 2)
                MiniHistory(history: store.history, metric: metric).frame(width: 48, height: 24).padding(.trailing, 6)
                Button { store.route = .processes(metric) } label: {
                    HStack(spacing: 3) {
                        Text("更多").font(.system(size: 10, weight: .medium))
                        Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold))
                    }
                    .foregroundStyle(.secondary).padding(.vertical, 8).padding(.leading, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(QuietButtonStyle()).focusable(false)
                .accessibilityLabel("显示全部\(metric.title)进程")
            }
            Rectangle().fill(Color.primary.opacity(0.055)).frame(height: 1)
            if let message = emptyMessage(metric: metric, processes: top) {
                VStack(spacing: 6) {
                    Image(systemName: metric == .gpu && store.snapshot.gpuProcessState == .unavailable ? "info.circle" : "waveform.path")
                        .font(.system(size: 17)).foregroundStyle(metric.color.opacity(0.7))
                    Text(message).font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).frame(height: 115)
            } else {
                VStack(spacing: 0) {
                    ForEach(top) { process in ProcessRow(process: process, metric: metric, maximum: maximum) }
                }
                .frame(minHeight: 115, alignment: .top)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.065), lineWidth: 0.5))
    }

    private func fullList(_ metric: Metric) -> some View {
        let processes = store.snapshot.rankedProcesses(for: metric)
        let maximum = max(processes.first?.value(for: metric) ?? 0, 0.001)
        return VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: metric.symbol).font(.system(size: 24)).foregroundStyle(metric.color)
                    .frame(width: 42, height: 42).background(metric.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text(DisplayFormat.percent(store.snapshot.percent(for: metric)))
                        .font(.system(size: 28, weight: .medium, design: .rounded)).monospacedDigit()
                    Text(metricSubtitle(metric)).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                MiniHistory(history: store.history, metric: metric).frame(width: 90, height: 35)
            }
            .padding(.horizontal, 20).padding(.bottom, 14)
            if metric == .memory, let memory = store.snapshot.memory {
                memoryBreakdown(memory).padding(.horizontal, 20).padding(.bottom, 12)
            }
            Text(metric.explanation).font(.system(size: 10)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.bottom, 14)
            HStack {
                Text("进程 / PID"); Spacer(); Text("\(processes.count) 个进程"); Text(metric.valueTitle).frame(width: 76, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary)
            .padding(.horizontal, 26).padding(.vertical, 8)
            Divider().padding(.horizontal, 16)
            if let message = emptyMessage(metric: metric, processes: processes) {
                Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(processes) { process in
                            ProcessRow(process: process, metric: metric, maximum: maximum, detailed: true)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 6)
                }
                .id(metric)
                .scrollIndicators(.automatic)
            }
            if store.snapshot.unreadableProcesses > 0 && metric != .gpu {
                Text("\(store.snapshot.unreadableProcesses) 个受系统保护的进程无法读取，标为 —。")
                    .font(.system(size: 9)).foregroundStyle(.tertiary).padding(.vertical, 6)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func memoryBreakdown(_ memory: MemoryUsage) -> some View {
        HStack(spacing: 14) {
            memoryLabel("应用", value: memory.app, opacity: 1)
            memoryLabel("有线", value: memory.wired, opacity: 0.7)
            memoryLabel("已压缩", value: memory.compressed, opacity: 0.4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func memoryLabel(_ title: String, value: UInt64, opacity: Double) -> some View {
        HStack(spacing: 4) {
            Circle().fill(Metric.memory.color.opacity(opacity)).frame(width: 4, height: 4)
            Text("\(title) \(DisplayFormat.bytes(value))").font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }

    private var settings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    settingTitle("菜单栏布局", subtitle: "选择每个位置的指标，颜色随指标变化。")
                    HStack(spacing: 16) {
                        StatusItemPreview(snapshot: store.snapshot, layout: preferences.statusItemMetrics,
                                          visibleMetrics: preferences.visibleMetrics)
                            .frame(width: 64)
                        VStack(spacing: 0) {
                            ForEach(StatusItemPosition.allCases) { position in
                                HStack(spacing: 8) {
                                    Circle().fill(preferences.metric(for: position).color).frame(width: 6, height: 6)
                                    Text(position.title).font(.system(size: 12, weight: .medium))
                                    Spacer(minLength: 8)
                                    Picker(position.title, selection: Binding(
                                        get: { preferences.metric(for: position) },
                                        set: { preferences.setMetric($0, for: position) })) {
                                        ForEach(Metric.allCases) { metric in
                                            Text(metric.title + (preferences.visibleMetrics.contains(metric) ? "" : "（已隐藏）")).tag(metric)
                                        }
                                    }
                                    .labelsHidden().pickerStyle(.menu).controlSize(.small).focusable(false)
                                    .frame(width: 112)
                                    .accessibilityLabel("\(position.title)显示的指标")
                                }
                                .padding(.vertical, 7)
                                if position != .center { Divider() }
                            }
                        }
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                    Text("选择已占用的指标会交换位置；中心始终显示数字。")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                VStack(alignment: .leading, spacing: 10) {
                    settingTitle("监控维度", subtitle: "同时控制菜单栏图标和资源概览的显示。")
                    VStack(spacing: 0) {
                        ForEach(Metric.allCases) { metric in
                            HStack(spacing: 10) {
                                Image(systemName: metric.symbol).foregroundStyle(metric.color).frame(width: 24)
                                Text(metric.title).font(.system(size: 12, weight: .medium))
                                Spacer()
                                Toggle("显示\(metric.title)", isOn: Binding(
                                    get: { preferences.visibleMetrics.contains(metric) },
                                    set: { preferences.setVisible(metric, visible: $0) }))
                                    .labelsHidden().toggleStyle(.switch).tint(metric.color).controlSize(.small)
                                    .focusable(false)
                                    .disabled(preferences.visibleMetrics.count == 1 && preferences.visibleMetrics.contains(metric))
                            }
                            .padding(12)
                            if metric != .memory { Divider().padding(.leading, 46) }
                        }
                    }
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                    Text("至少保留一个维度。设置会自动保存。")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                VStack(alignment: .leading, spacing: 10) {
                    settingTitle("刷新间隔", subtitle: "弹窗关闭时仅采样整机数据，不扫描进程。")
                    HStack(spacing: 8) {
                        ForEach([1.0, 2.0, 3.0, 5.0], id: \.self) { interval in
                            Button { preferences.setInterval(interval) } label: {
                                Text("\(Int(interval)) 秒").font(.system(size: 12, weight: .medium))
                                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                                    .foregroundStyle(preferences.refreshInterval == interval ? Color.accentColor : .secondary)
                                    .background(preferences.refreshInterval == interval ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
                            }
                            .buttonStyle(QuietButtonStyle()).focusable(false)
                            .accessibilityAddTraits(preferences.refreshInterval == interval ? .isSelected : [])
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    settingTitle("菜单栏数值", subtitle: "圆环保留完整底轨，亮色弧线表示已用比例。")
                    Toggle("在圆环旁显示百分比", isOn: Binding(
                        get: { preferences.showPercentages }, set: { preferences.setShowPercentages($0) }))
                        .font(.system(size: 12)).toggleStyle(.switch).controlSize(.small).focusable(false)
                        .padding(12).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("轻驻菜单栏").font(.system(size: 12, weight: .medium))
                    Text("原生 Apple Silicon · 没有主窗口\n所有数据仅在本机采样，无需管理员权限。")
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(5)
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 24)
        }
        .scrollIndicators(.never)
    }

    private func settingTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 12, weight: .semibold))
            Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Circle().fill(Color.green.opacity(0.85)).frame(width: 5, height: 5)
            Text("每 \(Int(preferences.refreshInterval)) 秒更新").font(.system(size: 10)).foregroundStyle(.secondary)
            Spacer()
            Text("APPLE SILICON").font(.system(size: 8, weight: .medium, design: .monospaced))
                .tracking(1).foregroundStyle(.tertiary)
            IconButton(symbol: "power", label: "退出 Mac Monitor") { NSApplication.shared.terminate(nil) }
        }
        .padding(.leading, 20).padding(.trailing, 12).padding(.vertical, 6)
        .overlay(alignment: .top) { Divider().opacity(0.6) }
    }

    private func metricSubtitle(_ metric: Metric) -> String {
        switch metric {
        case .cpu: "\(store.snapshot.coreCount) 个核心 · 整机占用"
        case .gpu: "Apple GPU · 整机占用"
        case .memory:
            store.snapshot.memory.map { "\(DisplayFormat.bytes($0.used)) / \(DisplayFormat.bytes($0.total))" } ?? "统一内存"
        }
    }

    private func emptyMessage(metric: Metric, processes: [ProcessUsage]) -> String? {
        if metric == .gpu {
            switch store.snapshot.gpuProcessState {
            case .unavailable: return "当前系统未提供逐进程 GPU 数据"
            case .warmingUp: return "正在采样 GPU 进程…"
            case .available: if processes.isEmpty { return "暂无可读取的 GPU 进程" }
            }
        }
        if metric == .cpu && store.snapshot.cpuProcessState == .warmingUp { return "正在采样 CPU 进程…" }
        if processes.isEmpty { return "暂无可读取的进程" }
        return nil
    }
}
