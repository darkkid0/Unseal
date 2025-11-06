import AppKit
import UnsealCore
import SwiftUI

struct MenuContent: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DropZoneView()

            if let diagnostic = model.lastDiagnostic {
                DiagnosticPanel(diagnostic: diagnostic) {
                    model.retryLastFailure()
                }
            }

            HStack {
                Spacer()
                Button("清空记录") {
                    model.clearState()
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .disabled(model.dropStatus == .idle)
                .opacity(model.dropStatus == .idle ? 0.5 : 1.0)
            }

            HStack {
                Spacer()
                Button("查看帮助文档") {
                    if let url = URL(string: "https://support.apple.com/zh-cn/guide/mac-help/mh40616/mac") {
                        openURL(url)
                    }
                }
                .buttonStyle(.link)
            }
        }
    }
}

private struct DiagnosticPanel: View {
    let diagnostic: DiagnosticInfo
    let retryAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(diagnostic.title)
                    .font(.headline)
            }
            Text(diagnostic.message)
                .font(.subheadline)

            VStack(alignment: .leading, spacing: 4) {
                Text("命令")
                    .font(.footnote.bold())
                    .foregroundStyle(.secondary)
                Text(diagnostic.command)
                    .font(.footnote.monospaced())
            }

            if !diagnostic.output.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("系统反馈")
                        .font(.footnote.bold())
                        .foregroundStyle(.secondary)
                    ScrollView {
                        Text(diagnostic.output)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 90)
                }
            }

            if !diagnostic.suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("建议步骤")
                        .font(.footnote.bold())
                        .foregroundStyle(.secondary)
                    ForEach(diagnostic.suggestions, id: \.self) { suggestion in
                        Text("• \(suggestion)")
                            .font(.footnote)
                    }
                }
            }

            HStack {
                Spacer()
                Button("重试") {
                    retryAction()
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        )
    }
}
