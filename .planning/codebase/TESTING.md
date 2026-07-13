# Testing Patterns

**Analysis Date:** 2026-07-13

## Test Framework

**Runner:**
- XCTest through Swift Package Manager with Swift tools 6.2, configured by the two `.testTarget` declarations in `Package.swift`.
- Config: `Package.swift`; no separate `.xctestplan`, Xcode project, or test-runner configuration is present at the repository root.
- The current suite contains 17 XCTest methods across `Tests/AppModuleTests/` and `Tests/UnsealCoreTests/`; `swift test` passes all 17 on 2026-07-13.

**Assertion Library:**
- Use XCTest assertions imported from `XCTest`, including `XCTAssertEqual`, `XCTAssertTrue`, `XCTAssertFalse`, `XCTAssertNil`, `XCTAssertNotNil`, `XCTUnwrap`, and `XCTFail` across `Tests/AppModuleTests/` and `Tests/UnsealCoreTests/`.
- No third-party assertion, mocking, snapshot, or property-testing library is declared in `Package.swift`.

**Run Commands:**
```bash
swift test                                      # Run all tests from Package.swift
swift test --filter AppModelTests               # Run one suite; no watch task is configured
swift test --enable-code-coverage               # Run all tests and export SwiftPM coverage data
```

- CI runs `swift test` before packaging in `.github/workflows/release.yml`.
- XCTest watch mode is not configured in `Package.swift`, `.github/workflows/release.yml`, or any repository task file.

## Test File Organization

**Location:**
- Keep tests in separate SwiftPM test targets under `Tests/`, mirroring the production targets declared in `Package.swift`.
- Put application-state and login-item tests in `Tests/AppModuleTests/` for code under `Sources/AppModule/`.
- Put command execution, quarantine repair, and diagnostic tests in `Tests/UnsealCoreTests/` for code under `Sources/UnsealCore/`.
- Tests are not co-located with implementation files; preserve the `Sources/` to `Tests/` target boundary defined in `Package.swift`.

**Naming:**
- Name files and suites `{Subject}Tests`, as in `Tests/AppModuleTests/AppModelTests.swift`, `Tests/AppModuleTests/LaunchAtLoginControllerTests.swift`, and `Tests/UnsealCoreTests/QuarantineServiceTests.swift`.
- Name methods `test{Scenario}{ExpectedBehavior}`, as in `testRegistrationFailureUsesLaunchAgentFallback()` in `Tests/AppModuleTests/LaunchAtLoginControllerTests.swift`.
- Name fakes after the protocol or adapter they replace, as in `FakeLaunchAtLoginManager` and `FakeMainAppLoginItem` in `Tests/AppModuleTests/LaunchAtLoginControllerTests.swift`.

**Structure:**
```text
Tests/
├── AppModuleTests/
│   ├── AppModelTests.swift
│   └── LaunchAtLoginControllerTests.swift
└── UnsealCoreTests/
    └── QuarantineServiceTests.swift
```

- Each test target and path above is declared explicitly in `Package.swift`.

## Test Structure

**Suite Organization:**
```swift
// Tests/AppModuleTests/AppModelTests.swift
@MainActor
final class AppModelTests: XCTestCase {
    func testSecondDropIsIgnoredWhileRepairIsRunning() async {
        let service = ControlledRepairService()
        let model = AppModel(service: service)
        let firstURL = URL(fileURLWithPath: "/Applications/First.app")

        model.handleDrop(urls: [firstURL])
        service.completeNext(with: .success)
        await Task.yield()

        XCTAssertEqual(model.dropStatus, .success(firstURL))
    }
}
```

**Patterns:**
- Use `final class {Subject}Tests: XCTestCase` for every suite under `Tests/`.
- Annotate suites that exercise main-actor application state with `@MainActor`, as in both files under `Tests/AppModuleTests/`.
- Arrange dependencies and inputs, invoke the behavior, then assert observable state; blank lines make these phases visible in `Tests/AppModuleTests/AppModelTests.swift` and `Tests/UnsealCoreTests/QuarantineServiceTests.swift`.
- Build dependencies inside each test rather than relying on shared mutable `setUp()` state; no suite under `Tests/` overrides `setUp()` or `tearDown()`.
- Use private helper methods inside the suite for repeated fixture construction, as in `makeTemporaryApp()` in `Tests/UnsealCoreTests/QuarantineServiceTests.swift`.
- Register cleanup with `addTeardownBlock` at fixture creation time in `Tests/UnsealCoreTests/QuarantineServiceTests.swift` and `Tests/AppModuleTests/LaunchAtLoginControllerTests.swift`.
- Assert public or `@testable` observable behavior and dependency interactions, including state in `Tests/AppModuleTests/AppModelTests.swift` and exact command invocations in `Tests/UnsealCoreTests/QuarantineServiceTests.swift`.

## Mocking

**Framework:**
- Use handwritten protocol-conforming fakes and controlled test doubles; no mocking framework is declared in `Package.swift`.
- Production seams are `QuarantineRepairing` and `CommandRunning` in `Sources/UnsealCore/QuarantineService.swift` and the login-item management protocols in `Sources/AppModule/LaunchAtLoginController.swift`.

**Patterns:**
```swift
// Tests/AppModuleTests/AppModelTests.swift
private final class ControlledRepairService: QuarantineRepairing, @unchecked Sendable {
    private struct Request {
        let url: URL
        let completion: @Sendable (RepairResult) -> Void
    }

    private let lock = NSLock()
    private var requests: [Request] = []

    func repair(appURL: URL, completion: @escaping @Sendable (RepairResult) -> Void) {
        lock.lock()
        requests.append(Request(url: appURL, completion: completion))
        lock.unlock()
    }

    func completeNext(with result: RepairResult) {
        lock.lock()
        let completion = requests.removeFirst().completion
        lock.unlock()
        completion(result)
    }
}
```

- Queue predetermined outputs and record calls in a thread-safe fake, following `QueueCommandRunner` in `Tests/UnsealCoreTests/QuarantineServiceTests.swift`.
- Count calls and mutate fake status to model service behavior, following `FakeLaunchAtLoginManager` and `FakeMainAppLoginItem` in `Tests/AppModuleTests/LaunchAtLoginControllerTests.swift`.
- Capture asynchronous completions and release them explicitly from the test, following `ControlledRepairService` in `Tests/AppModuleTests/AppModelTests.swift`.
- Protect mutable state in `@unchecked Sendable` doubles with `NSLock`, following both `Tests/AppModuleTests/AppModelTests.swift` and `Tests/UnsealCoreTests/QuarantineServiceTests.swift`.

**What to Mock:**
- Replace subprocess execution through `CommandRunning` when testing repair decisions in `Tests/UnsealCoreTests/QuarantineServiceTests.swift` so command order, arguments, status, and output are deterministic.
- Replace asynchronous repair through `QuarantineRepairing` when testing `AppModel` state transitions in `Tests/AppModuleTests/AppModelTests.swift`.
- Replace `SMAppService` access through the login-item protocols when testing controller policy in `Tests/AppModuleTests/LaunchAtLoginControllerTests.swift`.

**What NOT to Mock:**
- Use real domain values such as `DiagnosticInfo`, `RepairResult`, and `URL` from `Sources/UnsealCore/` in tests instead of duplicating their behavior.
- Use isolated real filesystem operations for property-list and application-bundle behavior in `Tests/AppModuleTests/LaunchAtLoginControllerTests.swift` and `Tests/UnsealCoreTests/QuarantineServiceTests.swift`.
- Exercise the real `SystemCommandRunner` only with bounded, deterministic system commands, as the `/bin/echo` and `/bin/sleep` cases do in `Tests/UnsealCoreTests/QuarantineServiceTests.swift`.

## Fixtures and Factories

**Test Data:**
```swift
// Tests/UnsealCoreTests/QuarantineServiceTests.swift
private func makeTemporaryApp() throws -> URL {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("UnsealTests-\(UUID().uuidString)", isDirectory: true)
    let appURL = rootURL.appendingPathComponent("Example.app", isDirectory: true)
    try FileManager.default.createDirectory(
        at: appURL,
        withIntermediateDirectories: true
    )
    addTeardownBlock { try? FileManager.default.removeItem(at: rootURL) }
    return appURL
}
```

**Location:**
- Keep small factories private in the suite that consumes them, as with `makeTemporaryApp()` in `Tests/UnsealCoreTests/QuarantineServiceTests.swift` and `makeLaunchAgentLoginItem()` in `Tests/AppModuleTests/LaunchAtLoginControllerTests.swift`.
- Create filesystem fixtures below `FileManager.default.temporaryDirectory` with a UUID in `Tests/UnsealCoreTests/QuarantineServiceTests.swift` and `Tests/AppModuleTests/LaunchAtLoginControllerTests.swift`.
- Create isolated `UserDefaults` suites with UUID names and remove their persistent domains during teardown in `Tests/AppModuleTests/LaunchAtLoginControllerTests.swift`.
- Inline one-off values near the test that uses them, including URLs and `DiagnosticInfo` values in `Tests/AppModuleTests/AppModelTests.swift`.
- No shared fixture directory, resource bundle, or factory module is configured in `Package.swift`.

## Coverage

**Requirements:**
- No numeric coverage target, exclusion list, coverage upload, or failure threshold is enforced by `Package.swift` or `.github/workflows/release.yml`.
- The automated gate in `.github/workflows/release.yml` requires all XCTest cases to pass, but it does not collect or publish coverage.
- Current behavioral coverage is concentrated on `Sources/AppModule/AppModel.swift`, `Sources/AppModule/LaunchAtLoginController.swift`, and `Sources/UnsealCore/QuarantineService.swift` through their matching files under `Tests/`.

**View Coverage:**
```bash
swift test --enable-code-coverage
swift test --show-codecov-path
```

- The commands above use SwiftPM's built-in coverage support for the targets declared in `Package.swift`; no repository-specific report formatter is present.

## Test Types

**Unit Tests:**
- Test application state transitions with a controlled service in `Tests/AppModuleTests/AppModelTests.swift`.
- Test login preference policy and adapter fallback behavior with fakes in `Tests/AppModuleTests/LaunchAtLoginControllerTests.swift`.
- Test quarantine decision branches with queued `CommandResult` values in `Tests/UnsealCoreTests/QuarantineServiceTests.swift`.
- Assert both returned domain state and outbound interactions, such as exact `xattr` and `spctl` arguments in `Tests/UnsealCoreTests/QuarantineServiceTests.swift`.

**Integration Tests:**
- No separate integration-test target exists in `Package.swift`; boundary checks live in the normal XCTest targets.
- Use temporary real directories and serialized launch-agent property lists in `Tests/AppModuleTests/LaunchAtLoginControllerTests.swift`.
- Exercise real `Process` output capture and timeout termination through `/bin/echo` and `/bin/sleep` in `Tests/UnsealCoreTests/QuarantineServiceTests.swift`.
- The integration-style cases require macOS facilities consistent with the `.macOS(.v13)` platform declaration in `Package.swift`.

**E2E Tests:**
- Not used; `Package.swift` contains only the two XCTest targets and no UI automation target.
- SwiftUI and AppKit surfaces in `Sources/AppModule/DropZoneView.swift`, `Sources/AppModule/MenuContent.swift`, `Sources/AppModule/SettingsView.swift`, and `Sources/AppModule/StatusItemController.swift` have no browser, snapshot, or `XCUITest` harness in `Tests/`.

## Common Patterns

**Async Testing:**
```swift
// Tests/AppModuleTests/AppModelTests.swift
model.handleDrop(urls: [appURL])
service.completeNext(with: .success)
await Task.yield()
XCTAssertEqual(model.dropStatus, .success(appURL))
```

- Mark state-model test methods `async` and yield once after a controlled callback schedules work on `MainActor`, as in `Tests/AppModuleTests/AppModelTests.swift`.
- For callback APIs running on a private queue, use `expectation(description:)`, fulfill from the callback, and call `wait(for:timeout:)`, following `repairResult(using:appURL:)` in `Tests/UnsealCoreTests/QuarantineServiceTests.swift`.
- Store callback results in an `NSLock`-protected box before fulfilling expectations, following `RepairResultBox` in `Tests/UnsealCoreTests/QuarantineServiceTests.swift`.
- Give asynchronous waits explicit short timeouts, using two seconds in `Tests/UnsealCoreTests/QuarantineServiceTests.swift`, so failures terminate deterministically.

**Error Testing:**
```swift
// Tests/UnsealCoreTests/QuarantineServiceTests.swift
guard case let .failure(info) = result else {
    return XCTFail("Expected failure")
}
XCTAssertTrue(info.title.contains("Gatekeeper"))
```

- Pattern-match result enums with `guard case`, fail immediately with `XCTFail`, then assert diagnostic fields in `Tests/UnsealCoreTests/QuarantineServiceTests.swift`.
- Inject an error into a fake and assert fallback side effects in `Tests/AppModuleTests/LaunchAtLoginControllerTests.swift`.
- Assert that invalid input causes no dependency invocation in `testRepairRejectsInvalidApplicationBeforeRunningCommands()` in `Tests/UnsealCoreTests/QuarantineServiceTests.swift`.
- Use `XCTUnwrap` when a failed optional conversion should fail the current test cleanly, as in the launch-agent property-list check in `Tests/AppModuleTests/LaunchAtLoginControllerTests.swift`.

## Test Inventory

| Suite | Cases | Primary Scope | File |
|-------|------:|---------------|------|
| `AppModelTests` | 3 | Concurrent drops, clearing, stale completion | `Tests/AppModuleTests/AppModelTests.swift` |
| `LaunchAtLoginControllerTests` | 6 | Defaults, approval, registration, fallback plist | `Tests/AppModuleTests/LaunchAtLoginControllerTests.swift` |
| `QuarantineServiceTests` | 8 | Repair branches, validation, process output, timeout | `Tests/UnsealCoreTests/QuarantineServiceTests.swift` |

- All 17 cases above pass through the package-wide command documented in `README.md` and executed by `.github/workflows/release.yml`.

## Adding Tests

- Add a `{Subject}Tests.swift` file to the test target matching the implementation target in `Package.swift`.
- Add a narrow protocol seam beside the production dependency only when deterministic substitution is required, following `CommandRunning` in `Sources/UnsealCore/QuarantineService.swift` and `LaunchAtLoginManaging` in `Sources/AppModule/LaunchAtLoginController.swift`.
- Keep new fakes private to the test file unless multiple suites under the same `Tests/` target genuinely share them.
- Preserve per-test fixture isolation and teardown patterns from `Tests/UnsealCoreTests/QuarantineServiceTests.swift` and `Tests/AppModuleTests/LaunchAtLoginControllerTests.swift`.
- Run the full `swift test` gate from `README.md` after focused `--filter` runs because test targets share the production modules declared in `Package.swift`.

---

*Testing analysis: 2026-07-13*
