import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var launchAtLoginController: LaunchAtLoginController

    var body: some View {
        Form {
            Section("常驻运行") {
                Toggle(
                    "登录时自动启动 Unseal",
                    isOn: Binding(
                        get: { launchAtLoginController.isEnabled },
                        set: { launchAtLoginController.setEnabled($0) }
                    )
                )

                Text("Unseal 启动后仅驻留在菜单栏，不会显示 Dock 图标，也不会扫描磁盘。")
                    .font(.footnote)

                if let message = launchAtLoginController.statusMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if launchAtLoginController.requiresApproval {
                        Button("打开登录项设置") {
                            launchAtLoginController.openSystemSettings()
                        }
                    }
                }
            }

            Section("手动修复流程") {
                Text("1. 从访达打开“应用程序”目录。")
                Text("2. 将显示“已损坏”的应用拖入菜单栏弹出的修复窗口。")
                Text("3. 等待工具仅移除 `com.apple.quarantine` 并完成 Gatekeeper 校验。")
            }
            .font(.footnote)

            Section("常见问题") {
                Text("• 若修复失败，请确认应用路径正确并重新下载。")
                Text("• Unseal 不会清除隔离标记以外的扩展属性。")
                Text("• 遇到权限错误时，先确认应用位于当前用户可修改的目录。")
            }
            .font(.footnote)

            Section("关于") {
                Text("本应用会常驻菜单栏，但仅在用户拖入应用时执行命令，不扫描磁盘，也不会收集任何数据。")
                    .font(.footnote)
            }
        }
        .padding()
        .frame(width: 360)
    }
}
