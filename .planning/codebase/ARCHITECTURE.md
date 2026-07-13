<!-- refreshed: 2026-07-13 -->
# Architecture

**Analysis Date:** 2026-07-13

## System Overview

```text
+------------------------------------------------------------------------------+
| Bootstrap and lifecycle                                                      |
| Sources/AppModule/UnsealApp.swift                                             |
| Sources/AppModule/AppDelegate.swift                                           |
+--------------------------------------+---------------------------------------+
                                       |
                                       v
+------------------------------------------------------------------------------+
| AppKit shell and SwiftUI presentation                                         |
| Sources/AppModule/StatusItemController.swift                                  |
| Sources/AppModule/MenuContent.swift, Sources/AppModule/DropZoneView.swift     |
+--------------------------------------+---------------------------------------+
                                       |
                                       v
+------------------------------------------------------------------------------+
| Main-actor state and capability coordination                                 |
| Sources/AppModule/AppModel.swift                                              |
| Sources/AppModule/LaunchAtLoginController.swift                               |
+--------------------------------------+---------------------------------------+
                                       |
                                       v
+------------------------------------------------------------------------------+
| Quarantine domain and process boundary                                       |
| Sources/UnsealCore/QuarantineService.swift                                    |
| Sources/UnsealCore/Diagnostics.swift                                          |
+--------------------------------------+---------------------------------------+
                                       |
                                       v
+------------------------------------------------------------------------------+
| macOS: xattr, spctl, SMAppService, UserDefaults, ~/Library/LaunchAgents       |
+------------------------------------------------------------------------------+
```

The Swift package boundary in `Package.swift` is one-way: the executable target at `Sources/AppModule/` depends on the library target at `Sources/UnsealCore/`; `Sources/UnsealCore/` does not import application UI code.

## Component Responsibilities

| Component | Responsibility | File |
|-----------|----------------|------|
| `UnsealApp` | Declares the `@main` SwiftUI application, installs `AppDelegate`, and exposes the Settings scene with shared environment objects. | `Sources/AppModule/UnsealApp.swift` |
| `AppDelegate` | Owns process-lifetime state, switches the app to accessory mode, activates login registration, creates the menu-bar controller, refreshes system state, and clears transient repair state at termination. | `Sources/AppModule/AppDelegate.swift` |
| `StatusItemController` | Bridges AppKit and SwiftUI through `NSStatusItem`, `NSPopover`, `NSHostingController`, a right-click context menu, and Combine-driven popover sizing. | `Sources/AppModule/StatusItemController.swift` |
| `MenuContent` | Composes the drop surface, diagnostic panel, help link, clear command, and launch-at-login toggle inside the popover. | `Sources/AppModule/MenuContent.swift` |
| `DropZoneView` | Accepts file URLs, filters for `.app` packages, renders repair state, and forwards valid drops to `AppModel`. | `Sources/AppModule/DropZoneView.swift` |
| `SettingsView` | Presents launch-at-login controls and operational guidance in the SwiftUI Settings scene. | `Sources/AppModule/SettingsView.swift` |
| `AppModel` | Implements the UI state machine, enforces one active repair, injects `QuarantineRepairing`, rejects stale completions, and publishes success or diagnostic failure. | `Sources/AppModule/AppModel.swift` |
| `LaunchAtLoginController` | Persists user intent in `UserDefaults`, publishes login-item state, and converts registration errors or approval requirements into UI messages. | `Sources/AppModule/LaunchAtLoginController.swift` |
| `SystemLaunchAtLoginManager` | Chooses between `SMAppService.mainApp` and a user LaunchAgent fallback behind `LaunchAtLoginManaging`. | `Sources/AppModule/LaunchAtLoginController.swift` |
| `LaunchAgentLoginItem` | Reads, validates, writes, and removes `~/Library/LaunchAgents/io.github.darkkid0.Unseal.login-item.plist` for full `.app` bundles. | `Sources/AppModule/LaunchAtLoginController.swift` |
| `QuarantineService` | Validates application bundles, removes only `com.apple.quarantine`, runs Gatekeeper assessment, and returns typed repair outcomes on a private serial queue. | `Sources/UnsealCore/QuarantineService.swift` |
| `SystemCommandRunner` | Executes absolute macOS tool paths without a shell, captures output in private temporary files, and enforces process timeouts. | `Sources/UnsealCore/QuarantineService.swift` |
| Diagnostics models | Carry sendable, equatable failure details and Gatekeeper assessment state across the core/application boundary. | `Sources/UnsealCore/Diagnostics.swift` |
| Packaging pipeline | Produces a universal `.app`, injects `Info.plist` and icon resources, signs it, and optionally submits it for notarization. | `package_app.sh` |

## Pattern Overview

**Overall:** A two-target Swift package with an MVVM-like observable state layer, protocol-based dependency inversion, and a hybrid AppKit/SwiftUI menu-bar shell (`Package.swift`, `Sources/AppModule/AppModel.swift`, `Sources/AppModule/StatusItemController.swift`).

**Key Characteristics:**
- Keep OS mutation and process execution behind `QuarantineRepairing` and `CommandRunning` in `Sources/UnsealCore/QuarantineService.swift`; UI code in `Sources/AppModule/` consumes results rather than launching tools directly.
- Keep all AppKit and SwiftUI state mutations on `@MainActor` in `Sources/AppModule/AppDelegate.swift`, `Sources/AppModule/AppModel.swift`, `Sources/AppModule/LaunchAtLoginController.swift`, and `Sources/AppModule/StatusItemController.swift`.
- Model user-visible repair outcomes as explicit enum/value states in `Sources/AppModule/AppModel.swift` and `Sources/UnsealCore/Diagnostics.swift` rather than exposing raw `Process` failures to views.
- Inject protocol implementations through initializers in `Sources/AppModule/AppModel.swift`, `Sources/AppModule/LaunchAtLoginController.swift`, and `Sources/UnsealCore/QuarantineService.swift` so tests can replace OS-facing behavior.

## Layers

**Bootstrap and Application Lifecycle:**
- Purpose: Create process-lifetime dependencies and translate `NSApplicationDelegate` callbacks into application actions.
- Location: `Sources/AppModule/UnsealApp.swift`, `Sources/AppModule/AppDelegate.swift`
- Contains: The `@main` entry point, Settings scene, accessory activation policy, and launch/activation/termination callbacks.
- Depends on: AppKit/SwiftUI plus `AppModel`, `LaunchAtLoginController`, and `StatusItemController` from `Sources/AppModule/`.
- Used by: The macOS application process built from `AppModule` in `Package.swift`.

**AppKit Menu-Bar Shell:**
- Purpose: Own menu-bar affordances that SwiftUI's scene declaration does not own.
- Location: `Sources/AppModule/StatusItemController.swift`
- Contains: `NSStatusItem`, `NSPopover`, context-menu commands, the hosting bridge, and popover sizing logic.
- Depends on: `AppModel` and `LaunchAtLoginController` from `Sources/AppModule/`, plus AppKit, Combine, and SwiftUI.
- Used by: `AppDelegate.applicationDidFinishLaunching` in `Sources/AppModule/AppDelegate.swift`.

**SwiftUI Presentation:**
- Purpose: Render state and turn direct user interactions into model/controller commands.
- Location: `Sources/AppModule/MenuContent.swift`, `Sources/AppModule/DropZoneView.swift`, `Sources/AppModule/SettingsView.swift`
- Contains: Popover composition, drag-and-drop handling, diagnostics, retry/clear actions, and login-at-launch controls.
- Depends on: Environment objects from `Sources/AppModule/AppModel.swift` and `Sources/AppModule/LaunchAtLoginController.swift`, plus diagnostics from `Sources/UnsealCore/Diagnostics.swift`.
- Used by: `HostingController` in `Sources/AppModule/StatusItemController.swift` and the Settings scene in `Sources/AppModule/UnsealApp.swift`.

**Application State:**
- Purpose: Coordinate UI state transitions without placing asynchronous workflow logic in views.
- Location: `Sources/AppModule/AppModel.swift`, `Sources/AppModule/LaunchAtLoginController.swift`
- Contains: Published state, repair request identity, persisted login preference, system-state refresh, and UI-ready messages.
- Depends on: Protocol abstractions in `Sources/UnsealCore/QuarantineService.swift` and `Sources/AppModule/LaunchAtLoginController.swift`.
- Used by: All views and lifecycle controllers under `Sources/AppModule/`.

**Core Domain and OS Process Adapter:**
- Purpose: Implement quarantine repair and Gatekeeper assessment independently of AppKit/SwiftUI.
- Location: `Sources/UnsealCore/QuarantineService.swift`, `Sources/UnsealCore/Diagnostics.swift`
- Contains: Domain protocols, command result types, serial repair workflow, app-bundle validation, process execution, and diagnostic values.
- Depends on: Foundation, Dispatch, `Process`, `/usr/bin/xattr`, and `/usr/sbin/spctl` from `Sources/UnsealCore/QuarantineService.swift`.
- Used by: `AppModel` in `Sources/AppModule/AppModel.swift` and core tests in `Tests/UnsealCoreTests/QuarantineServiceTests.swift`.

**Build and Distribution:**
- Purpose: Convert the SwiftPM executable into a signed, icon-bearing, universal macOS application bundle.
- Location: `Package.swift`, `generate_app_icon.sh`, `package_app.sh`, `Sources/AppModule/Resources/`
- Contains: Target definitions, icon conversion, dual-architecture builds, `Info.plist` generation, signing, and optional notarization.
- Depends on: Swift 6.2/Xcode tools and the raster sources under `icon/`.
- Used by: Developers producing `.build/release/Unseal.app` through `package_app.sh`.

## Data Flow

### Primary Request Path

1. SwiftUI accepts URL drops and filters for local `.app` candidates in `DropZoneView.body` (`Sources/AppModule/DropZoneView.swift:33`).
2. `AppModel.handleDrop` selects the first acceptable app and starts a uniquely identified repair (`Sources/AppModule/AppModel.swift:41`, `Sources/AppModule/AppModel.swift:71`).
3. `QuarantineService.repair` moves work to its user-initiated serial queue and validates that the URL is a real, local, non-symbolic-link application directory (`Sources/UnsealCore/QuarantineService.swift:181`, `Sources/UnsealCore/QuarantineService.swift:292`).
4. The service probes `com.apple.quarantine` with `/usr/bin/xattr -p` and, when present, removes only that attribute recursively with `/usr/bin/xattr -dr` (`Sources/UnsealCore/QuarantineService.swift:190`, `Sources/UnsealCore/QuarantineService.swift:192`, `Sources/UnsealCore/QuarantineService.swift:284`).
5. The service assesses execution with `/usr/sbin/spctl --assess --type execute` and maps the result to `.clean`, `.blocked`, or `.unknown` (`Sources/UnsealCore/QuarantineService.swift:216`, `Sources/UnsealCore/QuarantineService.swift:267`).
6. `AppModel.performRepair` returns the callback to `@MainActor`, ignores stale repair IDs, and publishes `.success` or `.failure` plus `DiagnosticInfo` (`Sources/AppModule/AppModel.swift:80`).
7. `DropZoneView` and `MenuContent` redraw from the published state; `StatusItemController` also resizes the popover when diagnostics appear (`Sources/AppModule/DropZoneView.swift:46`, `Sources/AppModule/MenuContent.swift:14`, `Sources/AppModule/StatusItemController.swift:120`).

### Application Launch and Menu Interaction

1. `UnsealApp` installs `AppDelegate` and declares only the Settings scene (`Sources/AppModule/UnsealApp.swift:3`).
2. `AppDelegate.applicationDidFinishLaunching` adopts accessory mode, activates login registration, constructs `StatusItemController`, and attaches its click action (`Sources/AppModule/AppDelegate.swift:10`).
3. `StatusItemController.togglePopover` routes left-clicks to the SwiftUI popover and right/control-clicks to AppKit clear/quit commands (`Sources/AppModule/StatusItemController.swift:64`, `Sources/AppModule/StatusItemController.swift:70`).

### Launch-at-Login Flow

1. First launch defaults `LaunchAtLoginEnabled` to `true`; later launches honor the persisted value in `UserDefaults` (`Sources/AppModule/LaunchAtLoginController.swift:214`, `Sources/AppModule/LaunchAtLoginController.swift:236`).
2. `SystemLaunchAtLoginManager.register` uses `SMAppService.mainApp`, falling back to a per-user LaunchAgent when the service is not found or registration fails for a complete `.app` bundle (`Sources/AppModule/LaunchAtLoginController.swift:139`, `Sources/AppModule/LaunchAtLoginController.swift:171`).
3. `LaunchAtLoginController.refresh` publishes enabled, disabled, approval-required, or unavailable state to both `MenuContent` and `SettingsView` (`Sources/AppModule/LaunchAtLoginController.swift:287`, `Sources/AppModule/MenuContent.swift:41`, `Sources/AppModule/SettingsView.swift:8`).

**State Management:**
- `AppModel` owns transient repair state for the process lifetime and resets it on clear or termination (`Sources/AppModule/AppModel.swift:5`, `Sources/AppModule/AppDelegate.swift:24`).
- `LaunchAtLoginController` owns published capability state while `UserDefaults` stores only the user's enablement preference (`Sources/AppModule/LaunchAtLoginController.swift:209`).
- `LaunchAgentLoginItem` persists fallback registration as a plist under the user's `Library/LaunchAgents`; no project database or cache layer exists (`Sources/AppModule/LaunchAtLoginController.swift:46`).

## Key Abstractions

**`QuarantineRepairing`:**
- Purpose: Separate `AppModel` from concrete command execution and filesystem mutation.
- Examples: `Sources/UnsealCore/QuarantineService.swift`, `Sources/AppModule/AppModel.swift`, `Tests/AppModuleTests/AppModelTests.swift`
- Pattern: Protocol injection with an asynchronous sendable completion.

**`CommandRunning`:**
- Purpose: Isolate absolute-path process invocation and make the repair pipeline deterministic in tests.
- Examples: `Sources/UnsealCore/QuarantineService.swift`, `Tests/UnsealCoreTests/QuarantineServiceTests.swift`
- Pattern: Synchronous adapter called only from `QuarantineService`'s background serial queue.

**`LaunchAtLoginManaging` and `MainAppLoginItemManaging`:**
- Purpose: Separate UI preference state from `SMAppService` and LaunchAgent registration mechanics.
- Examples: `Sources/AppModule/LaunchAtLoginController.swift`, `Tests/AppModuleTests/LaunchAtLoginControllerTests.swift`
- Pattern: Layered protocol adapters with fallback selection.

**Observable Application Models:**
- Purpose: Give SwiftUI and the AppKit hosting bridge a single source for repair and login status.
- Examples: `Sources/AppModule/AppModel.swift`, `Sources/AppModule/LaunchAtLoginController.swift`, `Sources/AppModule/StatusItemController.swift`
- Pattern: `@MainActor ObservableObject` instances owned by `AppDelegate` and injected as environment/observed objects.

**Diagnostic Value Types:**
- Purpose: Translate process and policy failures into user-displayable, sendable data.
- Examples: `Sources/UnsealCore/Diagnostics.swift`, `Sources/AppModule/MenuContent.swift`
- Pattern: Immutable structs and enums crossing the core/application target boundary.

## Entry Points

**Application Entry:**
- Location: `Sources/AppModule/UnsealApp.swift`
- Triggers: Launching the `Unseal` executable defined in `Package.swift`.
- Responsibilities: Initialize SwiftUI, attach `AppDelegate`, and provide the Settings scene.

**Lifecycle Entry:**
- Location: `Sources/AppModule/AppDelegate.swift`
- Triggers: macOS application launch, activation, and termination callbacks.
- Responsibilities: Create long-lived models, configure menu-bar behavior, refresh login state, and invalidate transient repair state.

**User Repair Entry:**
- Location: `Sources/AppModule/DropZoneView.swift`
- Triggers: A user drops one or more file URLs onto the popover.
- Responsibilities: Accept `.app` URLs and call `AppModel.handleDrop` in `Sources/AppModule/AppModel.swift`.

**Build/Packaging Entries:**
- Location: `generate_app_icon.sh`, `package_app.sh`
- Triggers: Developer shell invocation.
- Responsibilities: Generate `Sources/AppModule/Resources/AppIcon.icns` and package `.build/release/Unseal.app`.

## Architectural Constraints

- **Threading:** AppKit/SwiftUI controllers are `@MainActor` under `Sources/AppModule/`; `QuarantineService` serializes blocking work on its private queue in `Sources/UnsealCore/QuarantineService.swift`; callbacks return to the main actor in `Sources/AppModule/AppModel.swift`.
- **Process execution:** `SystemCommandRunner` blocks its caller for up to 30 seconds per command, captures output in mode-`0700`/`0600` temporary storage, terminates then force-kills timed-out processes, and runs only off the UI thread through `QuarantineService` (`Sources/UnsealCore/QuarantineService.swift`).
- **Global state:** Process-wide facilities are `NSApp` and `NSStatusBar.system` in `Sources/AppModule/AppDelegate.swift` and `Sources/AppModule/StatusItemController.swift`, `SMAppService.mainApp`, `Bundle.main`, `UserDefaults.standard`, and `FileManager.default` in `Sources/AppModule/LaunchAtLoginController.swift`, and `FileManager.default` in `Sources/UnsealCore/QuarantineService.swift`.
- **Circular imports:** GitNexus reports zero file import cycles; maintain the one-way `AppModule` to `UnsealCore` target dependency declared in `Package.swift`.
- **Platform:** The package requires macOS 13 and Swift tools 6.2 in `Package.swift`; the release pipeline requires macOS/Xcode command-line tools in `package_app.sh` and `generate_app_icon.sh`.
- **Bundle form:** Login launch is available only from a complete `.app`; `swift run` does not provide that bundle shape, and fallback availability checks live in `Sources/AppModule/LaunchAtLoginController.swift`.
- **Resources:** `Sources/AppModule/Resources/` is excluded from the SwiftPM target in `Package.swift`; `package_app.sh` must copy `Sources/AppModule/Resources/AppIcon.icns` into the application bundle explicitly.

## Anti-Patterns

### Dual Popover Size Ownership

**What happens:** AppKit assigns `NSPopover.contentSize` while SwiftUI assigns a root `.frame`, both using `MenuLayout.height`; resize observation watches only `lastDiagnostic` and `statusMessage` in `Sources/AppModule/StatusItemController.swift`.
**Why it's wrong:** A new content-driven height condition in `Sources/AppModule/MenuContent.swift` can desynchronize the AppKit container unless the layout function and observation inputs change together.
**Do this instead:** Keep `MenuLayout` as the only size calculation in `Sources/AppModule/StatusItemController.swift`, and add every new published size driver to `observePopoverContent` or replace both manual size owners with one intrinsic-sizing strategy.

### Login Feature Layer Co-location

**What happens:** State enums, two protocols, the `SMAppService` adapter, LaunchAgent plist persistence, fallback selection, and the observable UI controller share `Sources/AppModule/LaunchAtLoginController.swift`.
**Why it's wrong:** Expanding any one mechanism increases the change surface across presentation state and OS persistence in the same file.
**Do this instead:** Preserve the protocol boundaries in `Sources/AppModule/LaunchAtLoginController.swift`; place substantial new login adapters in focused files under `Sources/AppModule/` and leave `LaunchAtLoginController` responsible only for preference and published state.

## Error Handling

**Strategy:** Convert expected filesystem, process, Gatekeeper, and registration failures into typed state that the UI can render (`Sources/UnsealCore/Diagnostics.swift`, `Sources/UnsealCore/QuarantineService.swift`, `Sources/AppModule/LaunchAtLoginController.swift`).

**Patterns:**
- Return `.failure(DiagnosticInfo)` from repair operations rather than throw across the asynchronous boundary in `Sources/UnsealCore/QuarantineService.swift`.
- Encode process launch/capture failures in `CommandResult` with nonzero status and captured text in `Sources/UnsealCore/QuarantineService.swift`.
- Catch login registration errors and publish localized `statusMessage` values in `Sources/AppModule/LaunchAtLoginController.swift`.
- Use `activeRepairID` to discard completions invalidated by clear or termination in `Sources/AppModule/AppModel.swift`.
- Reserve `fatalError` for unsupported storyboard/coder construction of the private hosting controller in `Sources/AppModule/StatusItemController.swift`.

## Cross-Cutting Concerns

**Logging:** No logging subsystem or persistent telemetry is present; actionable failures are retained only as `DiagnosticInfo` in `Sources/UnsealCore/Diagnostics.swift` and displayed by `Sources/AppModule/MenuContent.swift`.
**Validation:** Validate at the interaction boundary in `Sources/AppModule/DropZoneView.swift`, at state admission in `Sources/AppModule/AppModel.swift`, and authoritatively at the filesystem boundary in `Sources/UnsealCore/QuarantineService.swift`.
**Authentication:** Not applicable; `Sources/AppModule/` and `Sources/UnsealCore/` expose no network server or user identity layer. macOS trust assessment is delegated to `spctl` in `Sources/UnsealCore/QuarantineService.swift`.

---

*Architecture analysis: 2026-07-13*
