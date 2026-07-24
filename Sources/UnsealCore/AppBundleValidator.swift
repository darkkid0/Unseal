import Foundation

/// Validates that a URL is a local, non-symlink application bundle before mutation.
public struct AppBundleValidator: Sendable {
    public init() {}

    public func validationFailure(for appURL: URL) -> DiagnosticInfo? {
        let standardized = appURL.standardizedFileURL

        guard standardized.isFileURL else {
            return invalidBundleDiagnostic(path: appURL.path)
        }

        var isDirectory = ObjCBool(false)
        let exists = FileManager.default.fileExists(
            atPath: standardized.path,
            isDirectory: &isDirectory
        )
        guard exists, isDirectory.boolValue else {
            return invalidBundleDiagnostic(path: standardized.path)
        }

        let isApplication = standardized.pathExtension.caseInsensitiveCompare("app") == .orderedSame
        guard isApplication else {
            return invalidBundleDiagnostic(path: standardized.path)
        }

        let values: URLResourceValues
        do {
            values = try standardized.resourceValues(forKeys: [
                .isSymbolicLinkKey,
                .isDirectoryKey,
                .isPackageKey
            ])
        } catch {
            return DiagnosticInfo(
                title: "无法读取应用包元数据",
                message: "读取应用包属性失败，为安全起见已中止操作。",
                command: "检查 \(standardized.path.shellQuoted)",
                output: error.localizedDescription,
                suggestions: [
                    "确认对该路径有读取权限。",
                    "请直接从访达拖入完整的 .app 应用包。"
                ]
            )
        }

        if values.isSymbolicLink == true {
            return invalidBundleDiagnostic(path: standardized.path)
        }

        let infoPlistURL = standardized
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Info.plist", isDirectory: false)
        guard FileManager.default.fileExists(atPath: infoPlistURL.path) else {
            return DiagnosticInfo(
                title: "无效的应用包",
                message: "目标缺少 Contents/Info.plist，不是完整的 macOS 应用包。",
                command: "检查 \(standardized.path.shellQuoted)",
                output: standardized.path,
                suggestions: [
                    "请直接从访达拖入完整的 .app 应用包。",
                    "不要拖入普通文件夹或已损坏的应用包。"
                ]
            )
        }

        return nil
    }

    private func invalidBundleDiagnostic(path: String) -> DiagnosticInfo {
        DiagnosticInfo(
            title: "无效的应用包",
            message: "Unseal 仅处理本机文件系统中真实存在且不是符号链接的 .app 应用包。",
            command: "检查 \(path.shellQuoted)",
            output: path,
            suggestions: [
                "请直接从访达拖入完整的 .app 应用包。",
                "不要拖入应用内部文件、快捷方式或符号链接。"
            ]
        )
    }
}
