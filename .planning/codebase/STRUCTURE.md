# Codebase Structure

**Analysis Date:** 2026-07-13

## Directory Layout

```text
Unseal/
├── Package.swift                         # SwiftPM targets and macOS platform declaration
├── Sources/
│   ├── AppModule/                        # Executable target: lifecycle, AppKit shell, SwiftUI UI, state
│   │   ├── AppDelegate.swift
│   │   ├── AppModel.swift
│   │   ├── DropZoneView.swift
│   │   ├── LaunchAtLoginController.swift
│   │   ├── MenuContent.swift
│   │   ├── SettingsView.swift
│   │   ├── StatusItemController.swift
│   │   ├── UnsealApp.swift
│   │   └── Resources/                    # Icon copied by the packaging script
│   │       ├── .keep
│   │       └── AppIcon.icns
│   └── UnsealCore/                       # Library target: repair, process, diagnostics
│       ├── Diagnostics.swift
│       └── QuarantineService.swift
├── Tests/
│   ├── AppModuleTests/                   # Main-actor model and login-item tests
│   │   ├── AppModelTests.swift
│   │   └── LaunchAtLoginControllerTests.swift
│   └── UnsealCoreTests/
│       └── QuarantineServiceTests.swift
├── icon/                                 # Committed PNG icon source sizes
├── asset/                                # Committed README screenshot
├── generate_app_icon.sh                  # PNG-to-ICNS pipeline
├── package_app.sh                        # Universal application packaging pipeline
├── .swiftpm/xcode/                       # SwiftPM-generated Xcode workspace metadata
├── .build/                               # Ignored build and packaged-app output
├── .codegraph/                           # Local CodeGraph index metadata
├── .gitnexus/                            # Local GitNexus index data
├── .codex/                               # Local GSD/Codex workflow installation
├── .claude/                              # Local GitNexus/Claude skill installation
└── .planning/codebase/                   # GSD-generated codebase reference documents
```

## Directory Purposes

**`Sources/AppModule/`:**
- Purpose: Houses the `AppModule` executable target declared in `Package.swift`.
- Contains: The `@main` entry, application lifecycle, AppKit menu-bar bridge, SwiftUI views, observable state, and launch-at-login adapters under `Sources/AppModule/`.
- Key files: `Sources/AppModule/UnsealApp.swift`, `Sources/AppModule/AppDelegate.swift`, `Sources/AppModule/AppModel.swift`, `Sources/AppModule/StatusItemController.swift`, `Sources/AppModule/LaunchAtLoginController.swift`

**`Sources/AppModule/Resources/`:**
- Purpose: Stores bundle artifacts consumed by `package_app.sh`, not SwiftPM resources.
- Contains: `Sources/AppModule/Resources/AppIcon.icns` and `Sources/AppModule/Resources/.keep`.
- Key files: `Sources/AppModule/Resources/AppIcon.icns`, `Package.swift`, `package_app.sh`

**`Sources/UnsealCore/`:**
- Purpose: Houses the UI-independent `UnsealCore` library target declared in `Package.swift`.
- Contains: Domain protocols, process execution, quarantine repair/assessment, and diagnostic value types under `Sources/UnsealCore/`.
- Key files: `Sources/UnsealCore/QuarantineService.swift`, `Sources/UnsealCore/Diagnostics.swift`

**`Tests/AppModuleTests/`:**
- Purpose: Tests stateful application behavior without constructing the full menu-bar UI.
- Contains: Repair state-machine tests in `Tests/AppModuleTests/AppModelTests.swift` and launch-registration tests in `Tests/AppModuleTests/LaunchAtLoginControllerTests.swift`.
- Key files: `Tests/AppModuleTests/AppModelTests.swift`, `Tests/AppModuleTests/LaunchAtLoginControllerTests.swift`, `Package.swift`

**`Tests/UnsealCoreTests/`:**
- Purpose: Tests the quarantine workflow and concrete command runner for the `UnsealCore` target.
- Contains: Command sequencing, Gatekeeper outcomes, output capture, timeout, and filesystem-backed scenarios in `Tests/UnsealCoreTests/QuarantineServiceTests.swift`.
- Key files: `Tests/UnsealCoreTests/QuarantineServiceTests.swift`, `Sources/UnsealCore/QuarantineService.swift`

**`icon/`:**
- Purpose: Provides raster source files for the application icon pipeline in `generate_app_icon.sh`.
- Contains: Committed PNG sizes such as `icon/16.png`, `icon/128.png`, `icon/512.png`, and the required `icon/1024.png`.
- Key files: `icon/1024.png`, `generate_app_icon.sh`

**`asset/`:**
- Purpose: Stores documentation media referenced from `README.md`.
- Contains: The UI preview at `asset/unseal.png`.
- Key files: `asset/unseal.png`, `README.md`

**`.planning/codebase/`:**
- Purpose: Stores GSD's generated reference map for planning and execution.
- Contains: Architecture, structure, stack, integration, convention, testing, and concern documents under `.planning/codebase/`.
- Key files: `.planning/codebase/ARCHITECTURE.md`, `.planning/codebase/STRUCTURE.md`

## Key File Locations

**Entry Points:**
- `Sources/AppModule/UnsealApp.swift`: Swift `@main` application entry and Settings scene.
- `Sources/AppModule/AppDelegate.swift`: macOS lifecycle entry and process-lifetime dependency owner.
- `Sources/AppModule/DropZoneView.swift`: User-triggered quarantine repair entry.
- `generate_app_icon.sh`: Developer entry for generating `Sources/AppModule/Resources/AppIcon.icns`.
- `package_app.sh`: Developer entry for producing `.build/release/Unseal.app`.

**Configuration:**
- `Package.swift`: Swift tools version, macOS minimum, products, target dependency direction, paths, and test targets.
- `.gitignore`: Ignores `.build/`, Xcode user state, Carthage output, and other generated local artifacts.
- `.swiftpm/xcode/package.xcworkspace/contents.xcworkspacedata`: Checked-in SwiftPM Xcode workspace metadata.
- `package_app.sh`: Generates the application `Info.plist` and reads bundle ID/version/signing/notarization configuration from shell environment variables.

**Application UI and State:**
- `Sources/AppModule/StatusItemController.swift`: AppKit status item, popover, hosting bridge, and right-click menu.
- `Sources/AppModule/MenuContent.swift`: Popover-level SwiftUI composition and diagnostics.
- `Sources/AppModule/DropZoneView.swift`: Drag target and repair-state presentation.
- `Sources/AppModule/SettingsView.swift`: Settings-window content.
- `Sources/AppModule/AppModel.swift`: Repair state machine and core-service coordination.
- `Sources/AppModule/LaunchAtLoginController.swift`: Login preference, ServiceManagement adapter, and LaunchAgent fallback.

**Core Logic:**
- `Sources/UnsealCore/QuarantineService.swift`: Command abstraction, process runner, repair pipeline, validation, and Gatekeeper assessment.
- `Sources/UnsealCore/Diagnostics.swift`: Public diagnostic and assessment value types.

**Testing:**
- `Tests/AppModuleTests/AppModelTests.swift`: `AppModel` acceptance, concurrency, clear, retry, and stale-completion behavior.
- `Tests/AppModuleTests/LaunchAtLoginControllerTests.swift`: Login preference and registration/fallback state behavior.
- `Tests/UnsealCoreTests/QuarantineServiceTests.swift`: Repair commands, diagnostics, process output, timeout, and filesystem behavior.

**Assets and Packaging:**
- `icon/1024.png`: Required high-resolution source for `generate_app_icon.sh`.
- `Sources/AppModule/Resources/AppIcon.icns`: Generated and committed icon copied into the `.app` by `package_app.sh`.
- `asset/unseal.png`: Documentation screenshot referenced by `README.md`.
- `package_app.sh`: Creates `.build/release/Unseal.app/Contents/` and embeds the executable, generated `Info.plist`, and icon.

## Naming Conventions

**Files:**
- Use PascalCase and match the primary Swift type, as in `Sources/AppModule/AppModel.swift`, `Sources/AppModule/DropZoneView.swift`, and `Sources/UnsealCore/QuarantineService.swift`.
- Use a cohesive domain noun for files containing related public values, as in `Sources/UnsealCore/Diagnostics.swift`.
- Name XCTest files `<Subject>Tests.swift`, as in `Tests/AppModuleTests/AppModelTests.swift` and `Tests/UnsealCoreTests/QuarantineServiceTests.swift`.
- Use lowercase snake_case for repository automation, as in `generate_app_icon.sh` and `package_app.sh`.

**Directories:**
- Match SwiftPM target names exactly for code roots: `Sources/AppModule/`, `Sources/UnsealCore/`, `Tests/AppModuleTests/`, and `Tests/UnsealCoreTests/` align with `Package.swift`.
- Use singular lowercase directories for repository media collections: `icon/` and `asset/`.
- Keep generated planning documents in uppercase Markdown filenames under `.planning/codebase/`, including `.planning/codebase/ARCHITECTURE.md` and `.planning/codebase/STRUCTURE.md`.

## Where to Add New Code

**New User-Facing Menu Feature:**
- Primary code: Add a focused SwiftUI view under `Sources/AppModule/` and compose it from `Sources/AppModule/MenuContent.swift`.
- State transitions: Extend `Sources/AppModule/AppModel.swift` when the feature belongs to the repair workflow.
- Tests: Add or extend a matching test under `Tests/AppModuleTests/`, following `Tests/AppModuleTests/AppModelTests.swift`.

**New Settings Feature:**
- Primary code: Add the control to `Sources/AppModule/SettingsView.swift`; move a substantial section into a focused `*View.swift` file under `Sources/AppModule/`.
- State/controller: Reuse an existing environment object from `Sources/AppModule/AppModel.swift` or `Sources/AppModule/LaunchAtLoginController.swift`, or add a focused observable controller under `Sources/AppModule/`.
- Tests: Put controller/model tests under `Tests/AppModuleTests/` and declare any new target dependency in `Package.swift`.

**New AppKit Menu-Bar Behavior:**
- Implementation: Extend `Sources/AppModule/StatusItemController.swift` for `NSStatusItem`, `NSPopover`, or context-menu lifecycle behavior.
- Presentation: Keep SwiftUI content in `Sources/AppModule/MenuContent.swift` or a new view under `Sources/AppModule/`.
- Tests: Extract behavior behind an injectable model/controller under `Sources/AppModule/` when it needs coverage in `Tests/AppModuleTests/`.

**New Core Repair Capability:**
- Primary code: Add a focused file under `Sources/UnsealCore/`; extend `Sources/UnsealCore/QuarantineService.swift` only when the behavior is part of the existing repair pipeline.
- Public result types: Add domain-specific values to `Sources/UnsealCore/Diagnostics.swift` or a new focused value-type file under `Sources/UnsealCore/`.
- Tests: Add a matching `<Subject>Tests.swift` file under `Tests/UnsealCoreTests/` and keep test target wiring in `Package.swift`.

**New OS or Command Adapter:**
- Implementation: Define a narrow protocol beside the owning domain in `Sources/UnsealCore/` or `Sources/AppModule/`, following `CommandRunning` in `Sources/UnsealCore/QuarantineService.swift` and `LaunchAtLoginManaging` in `Sources/AppModule/LaunchAtLoginController.swift`.
- Integration: Inject the concrete adapter through the owning type's initializer in `Sources/UnsealCore/QuarantineService.swift`, `Sources/AppModule/AppModel.swift`, or `Sources/AppModule/LaunchAtLoginController.swift`.
- Tests: Put fakes and assertions in the corresponding target under `Tests/UnsealCoreTests/` or `Tests/AppModuleTests/`.

**Utilities:**
- Shared helpers: No generic utilities directory exists; keep a private helper beside its sole owner, as with the private `String` helpers in `Sources/UnsealCore/QuarantineService.swift`.
- Reusable domain helper: Create a named, focused Swift file under `Sources/UnsealCore/` rather than introducing `Sources/UnsealCore/Utils.swift`.
- UI-only helper: Keep it private in the relevant file under `Sources/AppModule/`, as with `DiagnosticPanel` in `Sources/AppModule/MenuContent.swift` and `MenuLayout` in `Sources/AppModule/StatusItemController.swift`.

**Resources:**
- Source artwork: Add committed raster inputs under `icon/` and update `generate_app_icon.sh` when a new size or source convention is required.
- Bundle output: Generate `Sources/AppModule/Resources/AppIcon.icns` through `generate_app_icon.sh`; update `package_app.sh` for every new runtime resource because `Package.swift` excludes `Sources/AppModule/Resources/`.

**New Target or Dependency:**
- Manifest: Declare products, targets, target dependencies, and paths in `Package.swift`.
- Source root: Follow SwiftPM's mirrored structure under `Sources/<TargetName>/` and `Tests/<TargetName>Tests/`, matching the existing `Sources/UnsealCore/` and `Tests/UnsealCoreTests/` layout.

## Special Directories

**`.build/`:**
- Purpose: Stores SwiftPM intermediates, architecture-specific release binaries, the universal binary, and `.build/release/Unseal.app` produced by `package_app.sh`.
- Generated: Yes, by SwiftPM and `package_app.sh`.
- Committed: No; `.gitignore` excludes `.build/`.

**`Sources/AppModule/Resources/`:**
- Purpose: Stores the icon that `package_app.sh` manually embeds into the application bundle.
- Generated: `Sources/AppModule/Resources/AppIcon.icns` is generated by `generate_app_icon.sh`; `Sources/AppModule/Resources/.keep` preserves the directory.
- Committed: Yes; both `Sources/AppModule/Resources/AppIcon.icns` and `Sources/AppModule/Resources/.keep` are tracked.

**`.swiftpm/`:**
- Purpose: Stores SwiftPM/Xcode workspace metadata at `.swiftpm/xcode/package.xcworkspace/contents.xcworkspacedata`.
- Generated: Yes, by SwiftPM/Xcode tooling.
- Committed: The workspace metadata file is committed; user-specific `xcuserdata/` remains ignored by `.gitignore`.

**`.codegraph/`:**
- Purpose: Stores the repository-local CodeGraph index used for symbol and call-path discovery.
- Generated: Yes, by CodeGraph; `.codegraph/.gitignore` controls local index data.
- Committed: Only `.codegraph/.gitignore` is tracked.

**`.gitnexus/`:**
- Purpose: Stores the local GitNexus knowledge graph used for process, impact, and import-cycle analysis.
- Generated: Yes, by GitNexus indexing.
- Committed: No tracked files are present under `.gitnexus/`.

**`.planning/`:**
- Purpose: Stores GSD project state and generated codebase documents such as `.planning/codebase/ARCHITECTURE.md`.
- Generated: Yes, by GSD workflows.
- Committed: Managed by GSD workflow commits rather than product build scripts such as `package_app.sh`.

**`.codex/` and `.claude/`:**
- Purpose: Store local workflow, agent, and skill installations used to operate on the repository.
- Generated: Yes, by local agent tooling under `.codex/` and `.claude/`.
- Committed: No; `.gitignore` excludes both `.codex/` and `.claude/`.

**`icon/` and `asset/`:**
- Purpose: Store source icons for `generate_app_icon.sh` and the screenshot referenced by `README.md`.
- Generated: No; `icon/*.png` and `asset/unseal.png` are repository source assets.
- Committed: Yes; the image assets under `icon/` and `asset/` are tracked.

---

*Structure analysis: 2026-07-13*
