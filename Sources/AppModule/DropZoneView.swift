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
            let items = urls.filter { AppModel.isRepairableItem($0) }
            guard model.canAcceptDrop, !items.isEmpty else { return false }
            model.handleDrop(urls: items)
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
            return "拖入受限的 .app 或 .dmg"
        case let .processing(url):
            return "正在处理 \(url.lastPathComponent)"
        case let .success(url):
            return "\(url.lastPathComponent) 已解锁"
        case let .failure(url, _):
            return "\(url.lastPathComponent) 处理失败"
        }
    }

    private var statusDescription: String {
        switch model.dropStatus {
        case .idle:
            return "拖入可信来源的 .app，或浏览器下载的 .dmg（隔离标记常在镜像上）。每次一个。"
        case let .processing(url):
            if url.pathExtension.lowercased() == "dmg" {
                return "正在清除镜像隔离标记、挂载并安装应用…"
            }
            return "正在移除 com.apple.quarantine 隔离标记…"
        case let .success(url):
            if url.pathExtension.lowercased() == "dmg" {
                return "已清除隔离标记，并将镜像中的应用安装到应用程序文件夹。可从启动台打开。"
            }
            return "隔离标记已处理。可从访达重新打开该应用（仅处理可信来源软件）。"
        case .failure:
            return "查看下方诊断。Unseal 只处理隔离标记；.dmg 会安装其中的 .app，不能伪造签名。"
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
