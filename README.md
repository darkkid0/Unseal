# Unseal

Unseal 是一款 Swift/SwiftUI 编写的 macOS 菜单栏小工具，专为“应用已损坏，无法打开”提示设计。它将手动执行 `xattr -cr <App>` 的流程可视化：用户只需从访达拖入受限的 `.app` 包，工具会自动移除隔离标记并重新校验 Gatekeeper，结果即时反馈。

## 功能亮点
- **菜单栏常驻**：点击图标即可呼出拖拽面板，界面简洁清晰。
- **拖拽修复**：支持从访达拖入 `.app` 包触发一次性修复流程。
- **诊断说明**：失败时展示执行命令及系统反馈，附带重试与操作建议。
- **状态重置**：一键清空修复记录，恢复初始拖拽提示。
- **零监听**：不后台扫描磁盘，仅在用户操作时运行命令，无额外数据收集。

## 快速开始
```bash
swift build
open .build/debug/Unseal.app
```

> 提示：若构建后未生成 `.app`，可在 Xcode 中打开项目运行，或执行 `swift build --configuration release` 再从 `.build/release` 中启动。

## 使用步骤
1. 打开 Unseal 菜单栏窗口。
2. 在访达中定位受限的应用（常见提示：“应用已损坏，无法打开。您应该将它移到废纸篓。”）。
3. 拖动 `.app` 包到 Unseal 窗口的拖拽区域。
4. 等待状态更新：
   - ✅ 成功：显示绿色对勾，可直接重新启动应用。
   - ⚠️ 失败：查看诊断信息，尝试重试或按建议操作。
5. 通过“清空记录”按钮恢复初始界面。

## 依赖环境
- macOS 13 或更高版本
- Xcode 15 / Swift 6.2 toolchain

## 架构概览
```
Sources/
├── AppModule/        # 菜单栏 UI 与状态管理
│   ├── UnsealApp.swift
│   ├── AppDelegate.swift
│   ├── AppModel.swift
│   ├── StatusItemController.swift
│   ├── MenuContent.swift
│   └── DropZoneView.swift
└── UnsealCore/       # 命令执行与诊断逻辑
    ├── QuarantineService.swift
    └── Diagnostics.swift
Tests/
└── UnsealCoreTests/  # 单元测试（命令执行路径覆盖）
```

## 测试
```bash
swift test
```

测试主要覆盖 `UnsealCore` 中的修复与评估逻辑，包括：
- `xattr -cr` 执行成功/失败路径
- `spctl --assess` 在 Gatekeeper 拒绝时的诊断输出

## 权限说明
- 默认无需“完全磁盘访问权限”即可处理 `/Applications` 下的常规应用。
- 若修复多次失败，可在“系统设置 > 隐私与安全 > 完全磁盘访问权限”中手动授予，以处理位于特殊路径或自定义权限的应用。
- Unseal 不读取或上传用户文件，仅运行 `xattr` 与 `spctl` 命令。

## 常见问题
- **修复仍失败**  
  提示可能来自签名确实存在问题，建议重新下载软件或在“隐私与安全”中临时允许运行。

- **拖拽无反应**  
  仅支持 `.app` 目录，请确保拖入的是应用包而非其内部文件。

- **构建时出现 `default.metallib` 警告**  
  该路径为 Apple 内部版本残留，外部环境可忽略，不影响使用。

## 许可证
暂未指定，可根据团队需求补充。
