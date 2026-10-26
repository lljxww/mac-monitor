import AppKit
import MonitorCore
import SwiftUI

extension Metric {
    var nsColor: NSColor {
        switch self {
        case .cpu: NSColor(srgbRed: 0.20, green: 0.69, blue: 0.91, alpha: 1)
        case .gpu: NSColor(srgbRed: 0.64, green: 0.47, blue: 0.94, alpha: 1)
        case .memory: NSColor(srgbRed: 0.91, green: 0.61, blue: 0.22, alpha: 1)
        }
    }
    var color: Color { Color(nsColor: nsColor) }
    var symbol: String {
        switch self { case .cpu: "cpu"; case .gpu: "square.3.layers.3d"; case .memory: "memorychip" }
    }
    var valueTitle: String {
        switch self { case .cpu: "% CPU"; case .gpu: "% GPU"; case .memory: "内存占用" }
    }
    var explanation: String {
        switch self {
        case .cpu: "进程 CPU 100% 表示占满一个核心，多核进程可超过 100%。"
        case .gpu: "根据驱动的累计 GPU 执行时间计算；并行任务可超过 100%。"
        case .memory: "按物理内存占用排序；受保护进程以 ≈ 标记常驻内存（RSS）。"
        }
    }
}

enum DisplayFormat {
    static func percent(_ value: Double?, decimals: Bool = false) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: decimals ? "%.1f%%" : "%.0f%%", value)
    }
    static func bytes(_ value: UInt64?) -> String {
        guard let value else { return "—" }
        let gb = Double(value) / 1_073_741_824
        if gb >= 1 { return String(format: "%.2f GB", gb) }
        return String(format: "%.0f MB", Double(value) / 1_048_576)
    }
    static func process(_ process: ProcessUsage, metric: Metric) -> String {
        metric == .memory ? (process.memoryIsResidentFallback ? "≈" : "") + bytes(process.memoryBytes)
            : percent(process.value(for: metric), decimals: true)
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.55 : 1)
    }
}

struct IconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(hovering ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(QuietButtonStyle())
        .focusable(false)
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

struct MiniHistory: View {
    let history: [SystemHistoryPoint]
    let metric: Metric
    var body: some View {
        Canvas { context, size in
            let points = history.suffix(40).compactMap { snapshot -> (Date, Double)? in
                snapshot.percent(for: metric).map { (snapshot.date, $0) }
            }
            guard points.count > 1, let first = points.first, let last = points.last else { return }
            let elapsed = max(1, last.0.timeIntervalSince(first.0))
            var path = Path()
            for (index, item) in points.enumerated() {
                let point = CGPoint(x: item.0.timeIntervalSince(first.0) / elapsed * size.width,
                                    y: size.height - min(100, max(0, item.1)) / 100 * (size.height - 3) - 1.5)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            context.stroke(path, with: .color(metric.color.opacity(0.85)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

@MainActor
private enum ProcessIcons {
    static let cache = NSCache<NSString, NSImage>()
    static func icon(for process: ProcessUsage) -> NSImage {
        guard let path = process.executablePath else {
            return NSImage(systemSymbolName: "terminal", accessibilityDescription: nil) ?? NSImage()
        }
        let iconPath: String
        if let range = path.range(of: ".app/") { iconPath = String(path[..<range.lowerBound]) + ".app" }
        else { iconPath = path }
        if let icon = cache.object(forKey: iconPath as NSString) { return icon }
        let icon = NSWorkspace.shared.icon(forFile: iconPath)
        cache.countLimit = 256
        cache.setObject(icon, forKey: iconPath as NSString)
        return icon
    }
}

struct ProcessRow: View {
    let process: ProcessUsage
    let metric: Metric
    let maximum: Double
    var detailed = false
    @State private var hovering = false
    private var fraction: Double {
        guard maximum > 0, let value = process.value(for: metric) else { return 0 }
        return min(1, max(0, value / maximum))
    }
    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: ProcessIcons.icon(for: process))
                .resizable().scaledToFit().frame(width: detailed ? 24 : 16, height: detailed ? 24 : 16)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(process.name).font(.system(size: detailed ? 12 : 11))
                    .lineLimit(1).truncationMode(.middle)
                if detailed { Text("PID \(String(process.pid))").font(.system(size: 10)).foregroundStyle(.tertiary) }
            }
            Spacer(minLength: 6)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(metric.color.opacity(0.10))
                    Capsule().fill(metric.color.opacity(0.70)).frame(width: geometry.size.width * fraction)
                }
            }
            .frame(width: detailed ? 66 : 44, height: 3)
            .accessibilityHidden(true)
            Text(DisplayFormat.process(process, metric: metric))
                .font(.system(size: detailed ? 12 : 11, weight: .medium, design: .monospaced))
                .foregroundStyle(process.value(for: metric) == nil ? .tertiary : .primary)
                .frame(width: detailed ? 76 : 68, alignment: .trailing)
        }
        .padding(.horizontal, detailed ? 10 : 2)
        .frame(height: detailed ? 44 : 23)
        .background(hovering ? Color.primary.opacity(0.045) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .onHover { hovering = $0 }
        .help("\(process.name)\nPID \(process.pid)\(process.executablePath.map { "\n" + $0 } ?? "")")
        .accessibilityElement(children: .combine)
    }
}
