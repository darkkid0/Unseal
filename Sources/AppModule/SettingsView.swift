import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Section("手动修复流程") {
                Text("1. 从访达打开“应用程序”目录。")
                Text("2. 将显示“已损坏”的应用拖入菜单栏弹出的修复窗口。")
                Text("3. 等待工具完成 `xattr -cr` 与 Gatekeeper 校验。")
            }
            .font(.footnote)

            Section("常见问题") {
                Text("• 若修复失败，请确认应用路径正确并重新下载。")
                Text("• Unseal 不会修改无问题应用的状态。")
                Text("• 完全磁盘访问权限并非必需，仅在修复失败时可尝试开启。")
            }
            .font(.footnote)

            Section("关于") {
                Text("本应用仅在用户拖入时执行命令，不常驻扫描，也不会收集任何数据。")
                    .font(.footnote)
            }
        }
        .padding()
        .frame(width: 360)
    }
}
