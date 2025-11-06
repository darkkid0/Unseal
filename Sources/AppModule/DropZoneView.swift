import SwiftUI

struct DropZoneView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(iconColor)

            Text(statusTitle)
                .font(.headline)

            Text(statusDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(borderColor, style: StrokeStyle(lineWidth: 2, dash: borderDash))
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(backgroundColor)
                )
        )
        .animation(.easeInOut(duration: 0.2), value: model.dropStatus)
        .animation(.easeInOut(duration: 0.2), value: isTargeted)
        .dropDestination(for: URL.self, action: { urls, _ in
            let apps = urls.filter { $0.pathExtension == "app" }
            guard !apps.isEmpty else { return false }
            model.handleDrop(urls: apps)
            return true
        }, isTargeted: { hovering in
            isTargeted = hovering
        })
    }

    private var iconName: String {
        switch model.dropStatus {
        case .idle:
            return "tray.and.arrow.down"
        case .processing:
            return "clock.arrow.circlepath"
        case .success:
            return "checkmark.circle.fill"
        case .failure:
            return "exclamationmark.triangle.fill"
        }
    }

    private var iconColor: Color {
        switch model.dropStatus {
        case .idle:
            return .accentColor
        case .processing:
            return .accentColor
        case .success:
            return .green
        case .failure:
            return .orange
        }
    }

    private var statusTitle: String {
        switch model.dropStatus {
        case .idle:
            return "拖入受限制的应用"
        case let .processing(url):
            return "正在修复 \(url.lastPathComponent)"
        case let .success(url):
            return "\(url.lastPathComponent) 已解锁"
        case let .failure(url, _):
            return "\(url.lastPathComponent) 修复失败"
        }
    }

    private var statusDescription: String {
        switch model.dropStatus {
        case .idle:
            return "将显示“已损坏”的应用从访达拖到此处，自动移除隔离标记。"
        case .processing:
            return "正在移除隔离标记并验证 Gatekeeper。"
        case .success:
            return "您可以直接从 Launchpad 或访达启动该应用。"
        case .failure:
            return "查看下方诊断信息，可尝试重试或按照建议处理。"
        }
    }

    private var borderColor: Color {
        if isTargeted {
            return .accentColor
        }
        switch model.dropStatus {
        case .success:
            return .green
        case .failure:
            return .orange
        default:
            return .accentColor.opacity(0.6)
        }
    }

    private var borderDash: [CGFloat] {
        isTargeted ? [8, 4] : []
    }

    private var backgroundColor: Color {
        switch model.dropStatus {
        case .success:
            return Color.green.opacity(0.1)
        case .failure:
            return Color.orange.opacity(0.1)
        default:
            return Color.accentColor.opacity(0.05)
        }
    }
}
