# Coding Conventions

**Analysis Date:** 2026-07-13

## Naming Patterns

**Files:**
- Use UpperCamelCase type-oriented names for Swift implementation files, such as `Sources/AppModule/AppModel.swift`, `Sources/AppModule/LaunchAtLoginController.swift`, and `Sources/UnsealCore/QuarantineService.swift`.
- Name view files after their primary SwiftUI type with a `View` suffix, as in `Sources/AppModule/DropZoneView.swift`, `Sources/AppModule/MenuContent.swift`, and `Sources/AppModule/SettingsView.swift`.
- Name XCTest files `{Subject}Tests.swift` and keep them under the matching test target, as in `Tests/AppModuleTests/AppModelTests.swift` and `Tests/UnsealCoreTests/QuarantineServiceTests.swift`.
- Keep repository automation in descriptive snake_case shell scripts, following `generate_app_icon.sh` and `package_app.sh`.

**Functions:**
- Use lowerCamelCase verb phrases for behavior: `handleDrop(urls:)` and `prepareForTermination()` in `Sources/AppModule/AppModel.swift`, `activateIfNeeded()` in `Sources/AppModule/LaunchAtLoginController.swift`, and `repair(appURL:completion:)` in `Sources/UnsealCore/QuarantineService.swift`.
- Use Swift argument labels to make call sites read as sentences, such as `performRepair(for:)` in `Sources/AppModule/AppModel.swift` and `validationFailure(for:)` in `Sources/UnsealCore/QuarantineService.swift`.
- Prefix XCTest methods with `test` and encode the scenario and expected outcome in the method name, as in `testSecondDropIsIgnoredWhileRepairIsRunning()` in `Tests/AppModuleTests/AppModelTests.swift`.
- Prefix local test factories with `make`, as in `makeTemporaryApp()` in `Tests/UnsealCoreTests/QuarantineServiceTests.swift` and `makeDefaults()` in `Tests/AppModuleTests/LaunchAtLoginControllerTests.swift`.

**Variables:**
- Use lowerCamelCase nouns for values and dependencies, including `activeRepairID` in `Sources/AppModule/AppModel.swift`, `launchAtLoginController` in `Sources/AppModule/AppDelegate.swift`, and `standardOutputURL` in `Sources/UnsealCore/QuarantineService.swift`.
- Prefix Boolean state with `is`, `has`, or `can`, as demonstrated by `isProcessing` and `canClearRecords` in `Sources/AppModule/AppModel.swift`, `isRegistered` in `Sources/AppModule/LaunchAtLoginController.swift`, and `hasDiagnostic` in `Sources/AppModule/StatusItemController.swift`.
- Use `private(set)` for externally readable but internally mutated state, including the published properties in `Sources/AppModule/AppModel.swift` and counters in the fakes in `Tests/AppModuleTests/LaunchAtLoginControllerTests.swift`.
- Store stable keys and identifiers as `static let`, such as `preferenceKey` and `label` in `Sources/AppModule/LaunchAtLoginController.swift`.

**Types:**
- Use UpperCamelCase for structs, classes, enums, and protocols throughout `Sources/AppModule/` and `Sources/UnsealCore/`.
- Name capability protocols with an `-ing` role suffix, including `CommandRunning` and `QuarantineRepairing` in `Sources/UnsealCore/QuarantineService.swift` and `LaunchAtLoginManaging` in `Sources/AppModule/LaunchAtLoginController.swift`.
- Name concrete adapters after their implementation mechanism, such as `SystemCommandRunner`, `SystemLaunchAtLoginManager`, and `SMMainAppLoginItem` in `Sources/UnsealCore/QuarantineService.swift` and `Sources/AppModule/LaunchAtLoginController.swift`.
- Use lowerCamelCase enum cases and model states as associated-value enums, following `RepairResult` in `Sources/UnsealCore/QuarantineService.swift` and `AppModel.DropStatus` in `Sources/AppModule/AppModel.swift`.
- Prefix handwritten test doubles with `Fake` when they simulate a dependency and use a behavior-oriented name for controlled doubles, as in `FakeLaunchAtLoginManager` and `ControlledRepairService` under `Tests/AppModuleTests/`.

## Code Style

**Formatting:**
- No SwiftFormat configuration is present at the repository root; preserve the established four-space indentation visible across `Sources/` and `Tests/`.
- Put opening braces on the declaration line and separate logical phases with blank lines, following `Sources/AppModule/AppModel.swift` and `Tests/AppModuleTests/AppModelTests.swift`.
- Break multi-parameter declarations and calls across one argument per line when they do not fit compactly, as in `CommandResult.init` and `SystemCommandRunner.runSync` in `Sources/UnsealCore/QuarantineService.swift`.
- Indent chained SwiftUI modifiers one level beneath the view expression, following `Sources/AppModule/DropZoneView.swift` and `Sources/AppModule/MenuContent.swift`.
- Prefer expression bodies for short computed properties and explicit `return` in multi-branch `switch` properties, following `isEnabled` in `Sources/AppModule/LaunchAtLoginController.swift` and `statusTitle` in `Sources/AppModule/DropZoneView.swift`.
- Keep whitespace-only grouping meaningful: dependencies and fixtures, action, then assertions are separated by blank lines in `Tests/AppModuleTests/AppModelTests.swift` and `Tests/UnsealCoreTests/QuarantineServiceTests.swift`.

**Linting:**
- No SwiftLint configuration, SwiftLint package dependency, or other lint task is defined in `Package.swift` or at the repository root.
- Treat the Swift 6.2 compiler and the full `swift test` build as the active static quality gate configured by `Package.swift` and `.github/workflows/release.yml`.
- Preserve Swift 6 concurrency annotations already enforced by the compiler: `@MainActor` on UI state in `Sources/AppModule/AppModel.swift`, `Sendable` on cross-queue values in `Sources/UnsealCore/`, and `@Sendable` callback closures in `Sources/UnsealCore/QuarantineService.swift`.
- Use `@unchecked Sendable` only when mutable state is explicitly synchronized, as shown by `QueueCommandRunner` and `RepairResultBox` in `Tests/UnsealCoreTests/QuarantineServiceTests.swift` and `ControlledRepairService` in `Tests/AppModuleTests/AppModelTests.swift`.

## Import Organization

**Order:**
1. Keep imports in one contiguous block at the top of each file, as in every file under `Sources/` and `Tests/`.
2. Place Apple/system modules before the target under test, following `Foundation`, `ServiceManagement`, and `XCTest` in `Tests/AppModuleTests/LaunchAtLoginControllerTests.swift`.
3. Use `@testable import` only for the implementation target whose internal API is exercised, as in `@testable import AppModule` in `Tests/AppModuleTests/AppModelTests.swift` and `@testable import UnsealCore` in `Tests/UnsealCoreTests/QuarantineServiceTests.swift`.
4. There is no enforced import sorter; when adding imports, preserve the neighboring file's compact ordering in `Sources/AppModule/StatusItemController.swift` or `Sources/UnsealCore/QuarantineService.swift`.

**Path Aliases:**
- Swift path aliases are not used; import SwiftPM target modules directly as `AppModule` or `UnsealCore`, with target relationships declared in `Package.swift`.
- Source paths are target-relative through SwiftPM rather than referenced in imports, using `Sources/AppModule`, `Sources/UnsealCore`, and their corresponding paths in `Tests/` as configured by `Package.swift`.

## Error Handling

**Patterns:**
- Use `throws` for recoverable filesystem and service-registration operations, then translate errors at the UI boundary in `Sources/AppModule/LaunchAtLoginController.swift`.
- Use `do`/`catch` when an error must become visible state, as `LaunchAtLoginController.setEnabled(_:)` and `enableIfPossible()` do in `Sources/AppModule/LaunchAtLoginController.swift`.
- Represent command execution as a value result rather than throwing: `CommandResult` captures termination status and output in `Sources/UnsealCore/QuarantineService.swift`.
- Represent repair outcomes with the domain enum `RepairResult`, returning `DiagnosticInfo` for user-actionable failures in `Sources/UnsealCore/QuarantineService.swift` and displaying it in `Sources/AppModule/MenuContent.swift`.
- Validate early with `guard` and return without side effects, following `handleDrop(urls:)` in `Sources/AppModule/AppModel.swift`, `validationFailure(for:)` in `Sources/UnsealCore/QuarantineService.swift`, and `LaunchAgentLoginItem.register()` in `Sources/AppModule/LaunchAtLoginController.swift`.
- Reserve `try?` for best-effort cleanup or non-fatal inspection, such as temporary-file removal in `Sources/UnsealCore/QuarantineService.swift` and fixture cleanup in `Tests/UnsealCoreTests/QuarantineServiceTests.swift`.
- Handle evolving system enums with `@unknown default`, as in the `SMAppService.Status` switches in `Sources/AppModule/LaunchAtLoginController.swift`.
- Keep `fatalError` for impossible framework initializers or failed test harness assumptions, as in `HostingController.init(coder:)` in `Sources/AppModule/StatusItemController.swift` and `repairResult(using:appURL:)` in `Tests/UnsealCoreTests/QuarantineServiceTests.swift`.

## Logging

**Framework:** Not detected in `Sources/` or `Tests/`; there are no `Logger`, `os_log`, `NSLog`, `print`, or `debugPrint` calls.

**Patterns:**
- Surface operational failures through structured state instead of console output: `DiagnosticInfo` in `Sources/UnsealCore/Diagnostics.swift` carries a title, message, command, output, and suggestions.
- Surface login-item failures through `statusMessage` in `Sources/AppModule/LaunchAtLoginController.swift` and render them in `Sources/AppModule/MenuContent.swift` and `Sources/AppModule/SettingsView.swift`.
- Preserve captured subprocess stdout and stderr inside `CommandResult` in `Sources/UnsealCore/QuarantineService.swift`; do not discard it or replace it with ad hoc console logging.

## Comments

**When to Comment:**
- Production and test Swift files under `Sources/` and `Tests/` currently contain no line or block comments; intent is conveyed through type names, extracted helpers, and domain enums.
- Keep user-facing explanation in `README.md` and in structured UI copy under `Sources/AppModule/` rather than narrating straightforward implementation steps inline.
- Prefer a small named helper such as `validationFailure(for:)` in `Sources/UnsealCore/QuarantineService.swift` or `resetState()` in `Sources/AppModule/AppModel.swift` when a comment would otherwise explain a code block.

**Doc Comments:**
- Swift `///` documentation comments are not used in the current public `UnsealCore` API in `Sources/UnsealCore/Diagnostics.swift` or `Sources/UnsealCore/QuarantineService.swift`.
- Public behavior is documented at repository level in `README.md`; match that current approach unless the public module becomes an independently consumed library through `Package.swift`.

## Function Design

**Size:**
- Keep UI state transitions and event handlers short, usually one guard plus a state update or delegated call, following `Sources/AppModule/AppModel.swift` and `Sources/AppModule/AppDelegate.swift`.
- Extract repeated or conceptually distinct operations into private helpers, such as `resetState()` and `performRepair(for:)` in `Sources/AppModule/AppModel.swift` and `readOutput(at:)` in `Sources/UnsealCore/QuarantineService.swift`.
- Use exhaustive computed-property switches to map domain state to presentation, following `Sources/AppModule/DropZoneView.swift` and `Sources/AppModule/LaunchAtLoginController.swift`.
- Keep longer orchestration at infrastructure boundaries where ordering matters, notably `SystemCommandRunner.runSync` and `QuarantineService.repair` in `Sources/UnsealCore/QuarantineService.swift`.

**Parameters:**
- Inject replaceable dependencies through initializers using protocol existentials, as in `AppModel.init(service:)` in `Sources/AppModule/AppModel.swift` and `QuarantineService.init(runner:)` in `Sources/UnsealCore/QuarantineService.swift`.
- Supply production implementations as default arguments while allowing tests to pass fakes, following `SystemLaunchAtLoginManager.init(appService:fallback:)` in `Sources/AppModule/LaunchAtLoginController.swift`.
- Mark callbacks crossing concurrency boundaries `@escaping @Sendable`, as in `QuarantineRepairing.repair(appURL:completion:)` in `Sources/UnsealCore/QuarantineService.swift`.
- Use `any Protocol` explicitly for stored existential dependencies under Swift 6.2, as in `Sources/AppModule/AppModel.swift` and `Sources/AppModule/LaunchAtLoginController.swift`.

**Return Values:**
- Return domain-specific structs and enums instead of tuples, following `CommandResult`, `RepairResult`, `DiagnosticInfo`, and `QuarantineAssessment` in `Sources/UnsealCore/`.
- Return `Bool` only for simple capability or framework action answers, such as `canAcceptDrop` in `Sources/AppModule/AppModel.swift` and the drop action in `Sources/AppModule/DropZoneView.swift`.
- Use optional returns when absence is the meaningful success path, as `validationFailure(for:) -> DiagnosticInfo?` does in `Sources/UnsealCore/QuarantineService.swift`.

## Module Design

**Exports:**
- Keep reusable security and diagnostic logic in the `UnsealCore` target and mark its cross-target API explicitly `public`, as in `Sources/UnsealCore/Diagnostics.swift` and `Sources/UnsealCore/QuarantineService.swift`.
- Keep application UI and lifecycle types at default internal visibility in the `AppModule` executable target under `Sources/AppModule/`.
- Hide implementation details with `private` and file-private placement, including `String` helpers in `Sources/UnsealCore/QuarantineService.swift`, `DiagnosticPanel` in `Sources/AppModule/MenuContent.swift`, and test doubles under `Tests/`.
- Co-locate small private helpers with their owning type instead of creating general utility files, following `MenuLayout` in `Sources/AppModule/StatusItemController.swift` and `LaunchAtLoginError` in `Sources/AppModule/LaunchAtLoginController.swift`.

**Barrel Files:**
- Barrel or re-export files are not used; SwiftPM forms modules directly from the source directories declared in `Package.swift`.
- Add target dependencies in `Package.swift` and import the target module directly rather than creating an umbrella source file under `Sources/`.

---

*Convention analysis: 2026-07-13*
