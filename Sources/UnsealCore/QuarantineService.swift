import Foundation

public enum RepairResult: Sendable {
    /// Quarantine was removed from an app/dmg, or a DMG app was installed after clearing quarantine.
    case success
    case failure(DiagnosticInfo)
}

/// Removes `com.apple.quarantine` from a user-selected `.app` or `.dmg`.
///
/// For `.dmg` files the quarantine is usually on the image itself (not the nested `.app`).
/// Unseal clears the image attribute, mounts it, installs the app to Applications, and
/// clears quarantine on the installed copy — matching the real-world “download DMG → damaged”
/// workflow.
///
/// Gatekeeper signature rejection alone is not a failure after quarantine is cleared.
/// `repair` retains the service until the completion handler is invoked.
public protocol QuarantineRepairing: Sendable {
    func repair(appURL: URL, completion: @escaping @Sendable (RepairResult) -> Void)
}

public final class QuarantineService: QuarantineRepairing, @unchecked Sendable {
    private let queue = DispatchQueue(
        label: "io.github.darkkid0.Unseal.QuarantineService",
        qos: .userInitiated
    )
    private let runner: any CommandRunning
    private let validator: AppBundleValidator
    private let attributes: QuarantineAttributeClient
    private let assessor: GatekeeperAssessor
    private let diskImages: DiskImageService

    public init(runner: any CommandRunning = SystemCommandRunner()) {
        self.runner = runner
        self.validator = AppBundleValidator()
        self.attributes = QuarantineAttributeClient(runner: runner)
        self.assessor = GatekeeperAssessor(runner: runner)
        self.diskImages = DiskImageService(runner: runner)
    }

    public func repair(appURL: URL, completion: @escaping @Sendable (RepairResult) -> Void) {
        queue.async {
            completion(self.performRepair(itemURL: appURL))
        }
    }

    public func assess(appURL: URL) async -> QuarantineAssessment {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.assessor.assess(appURL: appURL))
            }
        }
    }

    private func performRepair(itemURL: URL) -> RepairResult {
        let targetURL = itemURL.standardizedFileURL
        let ext = targetURL.pathExtension.lowercased()

        if ext == "dmg" {
            return repairDiskImage(dmgURL: targetURL)
        }

        return repairApplication(appURL: targetURL)
    }

    private func repairApplication(appURL: URL) -> RepairResult {
        if let validationFailure = validator.validationFailure(for: appURL) {
            return .failure(validationFailure)
        }

        return clearQuarantineOrExplain(at: appURL, kind: .application)
    }

    private func repairDiskImage(dmgURL: URL) -> RepairResult {
        if let validationFailure = diskImages.validationFailure(for: dmgURL) {
            return .failure(validationFailure)
        }

        // Quarantine almost always sits on the .dmg from the browser download.
        if case let .failed(result) = attributes.probe(appURL: dmgURL) {
            return .failure(
                DiagnosticInfo(
                    title: "无法读取隔离标记",
                    message: "探测磁盘镜像的 com.apple.quarantine 失败，未修改文件。",
                    command: "xattr -p com.apple.quarantine \(dmgURL.path.shellQuoted)",
                    output: result.combinedOutput,
                    suggestions: [
                        "确认对该 .dmg 有读写权限。",
                        "在终端手动执行上述命令查看具体错误。"
                    ]
                )
            )
        }

        let dmgRemove = attributes.remove(appURL: dmgURL)
        if !dmgRemove.succeeded,
           !QuarantineAttributeClient.isMissingAttribute(result: dmgRemove) {
            return .failure(
                DiagnosticInfo(
                    title: "移除磁盘镜像隔离标记失败",
                    message: "无法从 .dmg 删除 com.apple.quarantine。",
                    command: "xattr -dr com.apple.quarantine \(dmgURL.path.shellQuoted)",
                    output: dmgRemove.combinedOutput,
                    suggestions: [
                        "确认文件未被占用，且当前用户可修改「下载」目录中的文件。"
                    ]
                )
            )
        }

        // Install must run while the image is still mounted.
        let mountResult = diskImages.withMountedImage(dmgURL: dmgURL) { mountPoint -> RepairResult in
            let apps = diskImages.findApplicationBundles(in: mountPoint)
            if apps.isEmpty {
                return .failure(
                    DiagnosticInfo(
                        title: "镜像中未找到应用",
                        message: "已清除 .dmg 隔离标记并完成挂载，但未在卷根目录发现 .app。",
                        command: "hdiutil attach \(dmgURL.path.shellQuoted)",
                        output: dmgURL.path,
                        suggestions: [
                            "打开镜像确认应用是否在子文件夹中，若是请直接拖入该 .app。",
                            "部分软件需要先运行安装包（.pkg），Unseal 不处理安装器。"
                        ]
                    )
                )
            }

            if apps.count > 1 {
                let names = apps.map(\.lastPathComponent).joined(separator: "\n")
                return .failure(
                    DiagnosticInfo(
                        title: "镜像中有多个应用",
                        message: "检测到 \(apps.count) 个 .app。请打开镜像后单独拖入要处理的应用。",
                        command: "列出 \(dmgURL.lastPathComponent)",
                        output: names,
                        suggestions: [
                            "双击 .dmg 打开，将需要的 .app 拖到应用程序文件夹，再拖入 Unseal。"
                        ]
                    )
                )
            }

            let sourceApp = apps[0]
            // Nested app on a read-only volume often has no quarantine; the dmg did.
            // Install to a writable location and clear attributes on the copy.
            switch diskImages.installApplication(from: sourceApp) {
            case let .failure(info):
                return .failure(info)
            case let .success(installed):
                let clear = attributes.remove(appURL: installed)
                if !clear.succeeded,
                   !QuarantineAttributeClient.isMissingAttribute(result: clear) {
                    return .failure(
                        DiagnosticInfo(
                            title: "已安装但未能清除隔离标记",
                            message: "应用已复制到 \(installed.path)，但清除隔离标记失败。",
                            command: "xattr -dr com.apple.quarantine \(installed.path.shellQuoted)",
                            output: clear.combinedOutput,
                            suggestions: [
                                "在终端执行上述命令，或将应用拖入 Unseal 再试一次。"
                            ]
                        )
                    )
                }
                return .success
            }
        }

        switch mountResult {
        case let .failure(info):
            return .failure(info)
        case let .success(repairResult):
            return repairResult
        }
    }

    private enum TargetKind {
        case application
    }

    private func clearQuarantineOrExplain(at targetURL: URL, kind _: TargetKind) -> RepairResult {
        let probe = attributes.probe(appURL: targetURL)
        let hadQuarantine: Bool
        switch probe {
        case .present:
            hadQuarantine = true
        case .absent:
            hadQuarantine = attributes.hasQuarantineAnywhere(appURL: targetURL)
        case let .failed(result):
            return .failure(
                DiagnosticInfo(
                    title: "无法读取隔离标记",
                    message: "探测 com.apple.quarantine 失败，未修改应用包。",
                    command: "xattr -p com.apple.quarantine \(targetURL.path.shellQuoted)",
                    output: result.combinedOutput,
                    suggestions: [
                        "确认应用所在目录允许当前用户读取扩展属性。",
                        "在终端手动执行上述命令以查看具体错误。",
                        "解决权限或文件系统问题后重试。"
                    ]
                )
            )
        }

        if hadQuarantine {
            let removeResult = attributes.remove(appURL: targetURL)
            if !removeResult.succeeded {
                return .failure(
                    DiagnosticInfo(
                        title: "移除隔离标记失败",
                        message: "仅删除 com.apple.quarantine 时出现错误，其他扩展属性未被修改。",
                        command: "xattr -dr com.apple.quarantine \(targetURL.path.shellQuoted)",
                        output: removeResult.combinedOutput,
                        suggestions: [
                            "确认应用包未被其他进程占用。",
                            "检查应用所在目录是否允许当前用户修改。",
                            "若应用仍在只读磁盘镜像中，请先复制到应用程序文件夹，或直接拖入 .dmg。",
                            "重新下载可信来源的应用后再次尝试。"
                        ]
                    )
                )
            }
            return .success
        }

        let assessment = assessor.assess(appURL: targetURL)
        switch assessment.status {
        case .clean:
            return .success
        case .blocked, .unknown:
            return .failure(
                DiagnosticInfo(
                    title: "不是隔离标记问题",
                    message: """
                    未检测到 com.apple.quarantine。Unseal 只能移除隔离标记，无法修复签名、公证或完整性问题。\
                    若你拖入的是磁盘镜像里的 .app：隔离标记通常在 .dmg 上，请改为拖入 .dmg 本身。\
                    本机 ad-hoc 签名应用在 Gatekeeper 评估中常会显示 rejected。
                    """,
                    command: "spctl --assess --type execute \(targetURL.path.shellQuoted)",
                    output: assessment.details,
                    suggestions: [
                        "下载的安装包请直接拖入 .dmg（不要只拖镜像里的 .app）。",
                        "已安装的应用可先确认是否仍带隔离标记：xattr -l 应用路径。",
                        "ad-hoc / 未签名应用可尝试：右键应用 → 打开（仅限可信来源）。",
                        "Unseal 不会关闭系统安全策略，也不会伪造开发者签名。"
                    ]
                )
            )
        }
    }
}
