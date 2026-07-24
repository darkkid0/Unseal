import Foundation

/// Mounts a disk image at a private mount point and tears it down afterwards.
public final class DiskImageService: @unchecked Sendable {
    private let runner: any CommandRunning

    public init(runner: any CommandRunning) {
        self.runner = runner
    }

    public func validationFailure(for dmgURL: URL) -> DiagnosticInfo? {
        let fileManager = FileManager.default
        let standardized = dmgURL.standardizedFileURL
        guard standardized.isFileURL else {
            return invalidDiskImageDiagnostic(path: dmgURL.path)
        }

        var isDirectory = ObjCBool(false)
        let exists = fileManager.fileExists(atPath: standardized.path, isDirectory: &isDirectory)
        guard exists, !isDirectory.boolValue else {
            return invalidDiskImageDiagnostic(path: standardized.path)
        }

        let isDMG = standardized.pathExtension.caseInsensitiveCompare("dmg") == .orderedSame
        guard isDMG else {
            return invalidDiskImageDiagnostic(path: standardized.path)
        }

        let values: URLResourceValues
        do {
            values = try standardized.resourceValues(forKeys: [.isSymbolicLinkKey])
        } catch {
            return DiagnosticInfo(
                title: "无法读取磁盘镜像元数据",
                message: "读取 .dmg 属性失败，为安全起见已中止操作。",
                command: "检查 \(standardized.path.shellQuoted)",
                output: error.localizedDescription,
                suggestions: [
                    "确认对该路径有读取权限。",
                    "请直接从访达拖入完整的 .dmg 文件。"
                ]
            )
        }

        if values.isSymbolicLink == true {
            return invalidDiskImageDiagnostic(path: standardized.path)
        }

        return nil
    }

    /// Mounts the image, runs `work` with the mount-point URL, then always detaches.
    public func withMountedImage<T>(
        dmgURL: URL,
        work: (URL) -> T
    ) -> Result<T, DiagnosticInfo> {
        let fileManager = FileManager.default
        let mountPoint = fileManager.temporaryDirectory
            .appendingPathComponent("Unseal-Mount-\(UUID().uuidString)", isDirectory: true)

        do {
            try fileManager.createDirectory(
                at: mountPoint,
                withIntermediateDirectories: true
            )
        } catch {
            return .failure(
                DiagnosticInfo(
                    title: "无法创建挂载点",
                    message: "为磁盘镜像准备临时目录失败。",
                    command: "mkdir \(mountPoint.path.shellQuoted)",
                    output: error.localizedDescription,
                    suggestions: ["检查临时目录权限后重试。"]
                )
            )
        }

        let attach = runner.run(
            command: "/usr/bin/hdiutil",
            arguments: [
                "attach",
                "-nobrowse",
                "-readonly",
                "-mountpoint",
                mountPoint.path,
                dmgURL.path
            ]
        )

        guard attach.succeeded else {
            try? fileManager.removeItem(at: mountPoint)
            return .failure(
                DiagnosticInfo(
                    title: "无法挂载磁盘镜像",
                    message: "hdiutil 挂载失败，可能镜像已损坏或需要密码。",
                    command: "hdiutil attach -nobrowse -readonly \(dmgURL.path.shellQuoted)",
                    output: attach.combinedOutput,
                    suggestions: [
                        "在访达中双击该 .dmg 确认能否正常打开。",
                        "若镜像已加密，请先手动挂载后再拖入其中的 .app。"
                    ]
                )
            )
        }

        defer {
            _ = runner.run(
                command: "/usr/bin/hdiutil",
                arguments: ["detach", mountPoint.path, "-force"]
            )
            try? fileManager.removeItem(at: mountPoint)
        }

        return .success(work(mountPoint))
    }

    public func findApplicationBundles(in directory: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return contents.filter {
            $0.pathExtension.caseInsensitiveCompare("app") == .orderedSame
        }
    }

    /// Copies an app bundle to /Applications, falling back to ~/Applications.
    public func installApplication(from sourceApp: URL) -> Result<URL, DiagnosticInfo> {
        let fileManager = FileManager.default
        let appName = sourceApp.lastPathComponent
        let candidates: [URL] = [
            URL(fileURLWithPath: "/Applications", isDirectory: true)
                .appendingPathComponent(appName),
            fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true)
                .appendingPathComponent(appName)
        ]

        var lastError = "未知错误"
        for destination in candidates {
            let parent = destination.deletingLastPathComponent()
            do {
                try fileManager.createDirectory(
                    at: parent,
                    withIntermediateDirectories: true
                )
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.copyItem(at: sourceApp, to: destination)
                return .success(destination)
            } catch {
                lastError = error.localizedDescription
            }
        }

        return .failure(
            DiagnosticInfo(
                title: "无法安装应用",
                message: "已从磁盘镜像找到 \(appName)，但复制到应用程序目录失败。",
                command: "cp -R \(sourceApp.path.shellQuoted) /Applications/",
                output: lastError,
                suggestions: [
                    "确认对 /Applications 或 ~/Applications 有写入权限。",
                    "也可手动将镜像中的 .app 拖到应用程序文件夹，再拖入 Unseal。"
                ]
            )
        )
    }

    private func invalidDiskImageDiagnostic(path: String) -> DiagnosticInfo {
        DiagnosticInfo(
            title: "无效的磁盘镜像",
            message: "Unseal 仅处理本机真实存在且不是符号链接的 .dmg 文件。",
            command: "检查 \(path.shellQuoted)",
            output: path,
            suggestions: [
                "请从访达拖入完整的 .dmg 文件。",
                "也可先挂载镜像，再拖入其中的 .app 应用包。"
            ]
        )
    }
}
