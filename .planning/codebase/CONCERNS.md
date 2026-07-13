# Codebase Concerns

**Analysis Date:** 2026-07-13

## Tech Debt

**Quarantine workflow combines process control, validation, mutation, and diagnosis:**
- Issue: The largest production file owns subprocess lifecycle, temporary-file capture, bundle validation, quarantine mutation, Gatekeeper assessment, and user-facing Chinese diagnostics in one class.
- Files: `Sources/UnsealCore/QuarantineService.swift`, `Sources/UnsealCore/Diagnostics.swift`
- Impact: Changes to command execution or diagnostic wording can alter the security-sensitive repair path, and the single `CommandRunning` boundary is too coarse to test filesystem state independently from process results.
- Fix approach: Split the file into a bounded process runner, quarantine-attribute client, bundle validator, Gatekeeper assessor, and orchestration service. Keep an immutable command/result model shared by execution and diagnostic rendering.

**Command outcomes discard important failure distinctions:**
- Issue: `hasQuarantineAttribute` reduces every nonzero `xattr -p` result to `false`, so "attribute absent," permission denial, timeout, executable failure, and filesystem errors become the same state.
- Files: `Sources/UnsealCore/QuarantineService.swift`, `Sources/UnsealCore/Diagnostics.swift`
- Impact: The orchestrator cannot decide whether removal is unnecessary or impossible, and later diagnostics can blame signing or integrity instead of the failed attribute probe.
- Fix approach: Return a typed probe result such as `present(value)`, `absent`, and `failed(CommandResult)`. Preserve the original quarantine value for verification and possible rollback.

**Login-at-startup uses two persistence mechanisms without an explicit migration model:**
- Issue: `SMAppService.mainApp` and a hand-written `~/Library/LaunchAgents` plist are merged into one state machine; fallback state always wins, and the fallback label is hard-coded rather than derived from the configured bundle identifier.
- Files: `Sources/AppModule/LaunchAtLoginController.swift`, `package_app.sh`, `README.md`
- Impact: A signed update can remain on the legacy fallback indefinitely, custom `BUNDLE_IDENTIFIER` builds can collide on one LaunchAgent label, and partial registration failures leave preference and system state difficult to reconcile.
- Fix approach: Define one authoritative registration record, derive identifiers from `Bundle.main.bundleIdentifier`, migrate and remove legacy fallback entries when `SMAppService` is usable, and make enable/disable operations transactional.

**Status-item UI relies on initialization order and imperative mutable references:**
- Issue: A lazy `NSMenu` mutates the separate optional `clearMenuItem`, while `updateContextMenuItems` can run before the lazy menu exists. Fixed popover heights are also duplicated between AppKit and SwiftUI.
- Files: `Sources/AppModule/StatusItemController.swift`, `Sources/AppModule/MenuContent.swift`
- Impact: UI state can be stale on first presentation, and layout or menu changes require coordinated edits across private controller state with no compiler-enforced relationship.
- Fix approach: Construct the menu eagerly or return its item references from a dedicated builder, observe the model state directly, and centralize popover sizing in one layout abstraction.

**Quality gates are concentrated in the release job:**
- Issue: The only GitHub Actions workflow runs for tags or manual dispatch; there is no pull-request/push test job, formatting rule, lint configuration, static analysis, or enforced coverage threshold.
- Files: `.github/workflows/release.yml`, `Package.swift`
- Impact: The first automated signal for a regression can arrive while publishing a release, and style/concurrency drift depends entirely on local discipline.
- Fix approach: Add a fast CI workflow for pull requests and the default branch, then run formatting, SwiftLint or equivalent static checks, tests, and a modest coverage floor before release packaging.

## Known Bugs

**Failed quarantine probes can be reported as success or the wrong diagnosis:**
- Symptoms: A permission error or timeout from `xattr -p` is treated as "no quarantine attribute." If `spctl` accepts the bundle, repair returns success; if it rejects it, the app reports an unknown signing/integrity problem instead of the probe failure.
- Files: `Sources/UnsealCore/QuarantineService.swift`, `Sources/UnsealCore/Diagnostics.swift`
- Trigger: Make the target's extended attributes unreadable, make `/usr/bin/xattr` time out through a runner, or return any nonzero probe result other than the normal missing-attribute result.
- Workaround: Inspect `xattr -p com.apple.quarantine <path>` outside the app and resolve the filesystem or permission error before retrying; the current UI has no distinct recovery path.

**The first context menu can show Clear Records enabled when clearing is invalid:**
- Symptoms: On the first right-click after launch, `clearMenuItem` has its default enabled state even while the model is idle or processing. Selecting it is a visible no-op because `AppModel.clearState` correctly rejects the action.
- Files: `Sources/AppModule/StatusItemController.swift`, `Sources/AppModule/AppModel.swift`
- Trigger: Right-click the status item before `contextMenu` has ever been initialized, while `AppModel.canClearRecords` is false.
- Workaround: Use the disabled Clear Records button in the popover; later context-menu openings refresh correctly after the lazy menu has been created.

**Dropping multiple applications silently processes only the first:**
- Symptoms: The drop target accepts an array of `.app` URLs and returns `true`, but `AppModel.handleDrop` selects only the first matching URL; the remaining accepted items receive no result or warning.
- Files: `Sources/AppModule/DropZoneView.swift`, `Sources/AppModule/AppModel.swift`
- Trigger: Drag two or more application bundles into the drop zone in one operation.
- Workaround: Drop applications one at a time.

**Manual releases are not tied to the requested tag's source commit:**
- Symptoms: `workflow_dispatch` validates the `tag` input but checkout remains on the workflow-selected ref. Existing release assets can therefore be overwritten with a binary built from a different commit, or a new tag can be created at `GITHUB_SHA` rather than an intended existing tag.
- Files: `.github/workflows/release.yml`
- Trigger: Manually dispatch with a tag whose commit differs from the selected workflow ref, especially when updating an existing release.
- Workaround: Dispatch only from the exact release commit and manually verify it matches the tag before publishing; the workflow does not enforce this invariant.

**Published checksum files reference the build-time `dist/` directory:**
- Symptoms: `shasum` records `dist/Unseal-...zip`, but GitHub Release uploads the ZIP and checksum as flat sibling assets. Running `shasum -c` beside downloaded assets cannot find the recorded path.
- Files: `.github/workflows/release.yml`
- Trigger: Download the release ZIP and `.sha256` into one directory and verify with the standard checksum command.
- Workaround: Place the downloaded ZIP under a local `dist/` directory or remove the `dist/` prefix from the checksum entry before verification.

**Repair completion is not guaranteed when the service is released:**
- Symptoms: `QuarantineService.repair` captures `self` weakly and returns without invoking its completion if the service deallocates before its serial-queue block starts, leaving generic callers waiting indefinitely.
- Files: `Sources/UnsealCore/QuarantineService.swift`, `Sources/AppModule/AppModel.swift`
- Trigger: Start a repair through a short-lived `QuarantineService` instance and release the last strong reference immediately.
- Workaround: Retain the service for the full operation. `AppModel` does this in the current app path, but the public protocol does not document the requirement.

## Security Considerations

**Quarantine removal happens before trust verification and is not rolled back:**
- Risk: The app recursively deletes `com.apple.quarantine`, then runs `spctl`. A rejected or unknown assessment leaves the original provenance marker removed even though the UI reports failure, and Gatekeeper acceptance alone does not prove software is safe.
- Files: `Sources/UnsealCore/QuarantineService.swift`, `Sources/AppModule/DropZoneView.swift`, `README.md`
- Current mitigation: Executables are fixed absolute paths, arguments bypass a shell, only the quarantine attribute is targeted, `spctl` runs afterward, and UI/documentation repeatedly tells users to process trusted software only.
- Recommendations: Show developer identity and signature/notarization details before mutation, require an explicit confirmation for uncertain software, preserve the original attribute value, verify removal, and restore it when postflight validation fails or is inconclusive.

**Bundle validation is shallow and subject to path races:**
- Risk: Any existing non-top-level-symlink directory ending in `.app` passes validation, including a renamed arbitrary tree. Failure to read `isSymbolicLink` is treated as safe, nested links are not considered, and another process can replace the path between validation and recursive `xattr` execution.
- Files: `Sources/UnsealCore/QuarantineService.swift`
- Current mitigation: The URL must be a local file URL, exist as a directory, use the `.app` extension, and not report itself as a symbolic link.
- Recommendations: Fail closed when resource metadata cannot be read, standardize and resolve the target, require a valid bundle and executable, capture a stable filesystem identity, and revalidate that identity immediately before mutation.

**The application is intentionally unsandboxed and can modify user-writable bundles:**
- Risk: The package has no App Sandbox entitlement and launches system commands with the user's full filesystem permissions. A defect in target validation therefore has a larger write radius than a sandboxed drag-and-drop app.
- Files: `package_app.sh`, `Package.swift`, `Sources/UnsealCore/QuarantineService.swift`
- Current mitigation: Work occurs only after an explicit drop, fixed commands are used, no elevation is requested, and only one named extended attribute is removed.
- Recommendations: Document the unsandboxed requirement in release security notes, minimize the mutation surface, add audit logging local to the user, and evaluate a narrowly scoped privileged design only if sandboxing is otherwise impossible.

**Production releases can silently degrade to ad-hoc signing:**
- Risk: When signing credentials are entirely absent, tag builds still create a public ad-hoc-signed, unnotarized GitHub Release and skip `spctl` verification. Users must bypass normal trust signals for a tool whose purpose is to remove those signals from other apps.
- Files: `.github/workflows/release.yml`, `package_app.sh`, `README.md`
- Current mitigation: Tests run, ad-hoc `codesign --verify` runs, a SHA-256 file is published, and partially configured credentials fail the job.
- Recommendations: Fail closed for production tags unless Developer ID signing, notarization, stapling, and Gatekeeper assessment all succeed. Restrict ad-hoc outputs to clearly labeled development artifacts or prereleases.

**First launch creates persistence without an in-app consent step:**
- Risk: A missing preference is immediately set to enabled and the app registers itself for login startup. This is disclosed in the README and reversible, but it is still persistence established before the user explicitly chooses the toggle.
- Files: `Sources/AppModule/LaunchAtLoginController.swift`, `Sources/AppModule/AppDelegate.swift`, `README.md`
- Current mitigation: Registration is user-level, the UI exposes a toggle, and macOS approval states are surfaced instead of bypassed.
- Recommendations: Default to disabled or present a first-run choice before registration, and store consent separately from observed system state.

**Release actions are referenced by mutable major-version tags:**
- Risk: Compromise or unexpected movement of a third-party action tag changes code executed in a write-enabled release job.
- Files: `.github/workflows/release.yml`
- Current mitigation: Only two widely used first-party GitHub actions are present and the job uses ephemeral hosted runners.
- Recommendations: Pin actions to reviewed full commit SHAs, enable automated update review, and reduce `contents: write` to only the publishing step or job that requires it.

## Performance Bottlenecks

**Repair is a serial sequence of blocking subprocesses:**
- Problem: One repair can run up to four synchronous command calls on a single serial queue, with a default 30-second timeout per call. The model blocks new drops for the full operation and exposes no cancellation.
- Files: `Sources/UnsealCore/QuarantineService.swift`, `Sources/AppModule/AppModel.swift`, `Sources/AppModule/DropZoneView.swift`
- Cause: `CommandRunning` is synchronous, `QuarantineService` has one private serial `DispatchQueue`, and each state check launches a fresh process.
- Improvement path: Use structured async process orchestration with a total operation deadline, cancellation propagation, explicit progress stages, and one post-mutation verification plan that avoids redundant probes.

**Command output is captured and loaded without a size limit:**
- Problem: Each subprocess can write an arbitrary amount to private temporary files, after which `Data(contentsOf:)` loads each entire file into memory.
- Files: `Sources/UnsealCore/QuarantineService.swift`
- Cause: File-backed capture prevents pipe deadlocks but has no byte cap or streaming/truncation policy.
- Improvement path: Enforce a maximum captured size, retain a truncated tail for diagnostics, and report truncation. The current fixed `xattr` and `spctl` commands normally produce small output, so this is a defensive limit.

**Universal packaging performs two clean builds with no reusable cache:**
- Problem: Every package run deletes `.build`, compiles arm64 and x86_64 sequentially, and the release workflow does not restore a Swift build cache.
- Files: `package_app.sh`, `.github/workflows/release.yml`
- Cause: The script prioritizes deterministic clean artifacts and uses two architecture-specific SwiftPM builds before `lipo`.
- Improvement path: Preserve architecture-keyed caches in CI, build architectures in parallel where runner capacity permits, and keep the destructive clean option for explicit reproducible-release mode.

## Fragile Areas

**Quarantine state transition and diagnostics:**
- Files: `Sources/UnsealCore/QuarantineService.swift`, `Sources/UnsealCore/Diagnostics.swift`
- Why fragile: Filesystem state is inferred from command exit status at multiple moments, mutation is irreversible in the current flow, and localized command output can vary across macOS versions.
- Safe modification: Model probe/mutation/postflight states explicitly, preserve raw results, add rollback, and keep executed arguments and displayed commands derived from the same value object.
- Test coverage: Happy path, removal failure, broad assessment outcomes, and timeout are covered; probe-error classification, rollback, metadata races, and real signed/quarantined fixtures are not.

**Launch-at-login registration:**
- Files: `Sources/AppModule/LaunchAtLoginController.swift`, `package_app.sh`
- Why fragile: State spans `UserDefaults`, `SMAppService`, and an on-disk LaunchAgent. Disable removes fallback before unregistering the service, status prioritizes fallback, and registration failures can partially mutate system state.
- Safe modification: Treat preference, desired state, and observed state separately; make transitions idempotent; verify final state; and test migrations before changing identifiers or packaging.
- Test coverage: Default enable/disable, approval, fallback creation, and registration fallback are covered; unregister errors, malformed/stale plists, partial states, migration, and a packaged app are not.

**AppKit status item around SwiftUI content:**
- Files: `Sources/AppModule/StatusItemController.swift`, `Sources/AppModule/MenuContent.swift`, `Sources/AppModule/DropZoneView.swift`, `Sources/AppModule/AppDelegate.swift`
- Why fragile: Lifecycle, lazy menu creation, event-type inspection, model observation, and fixed dimensions are coordinated manually across framework boundaries.
- Safe modification: Make menu construction deterministic, drive enabled state from publishers, isolate AppKit event handling behind a testable adapter, and validate popover behavior at multiple content/accessibility sizes.
- Test coverage: No tests instantiate `StatusItemController`, `AppDelegate`, `MenuContent`, `DropZoneView`, or `SettingsView`.

**Release identity and artifact creation:**
- Files: `.github/workflows/release.yml`, `package_app.sh`
- Why fragile: Tag text, checkout ref, version metadata, signing mode, notarization mode, archive naming, and checksum content are assembled in shell across two files.
- Safe modification: Resolve and checkout an immutable tag commit first, pass one validated metadata file through packaging, fail closed on production signing, and verify the downloaded-form archive/checksum before publishing.
- Test coverage: The scripts have no automated shell tests, `actionlint`/ShellCheck gate, dry-run fixture, or post-release verification job.

**Unchecked concurrency contracts:**
- Files: `Sources/UnsealCore/QuarantineService.swift`, `Sources/AppModule/AppModel.swift`
- Why fragile: `SystemCommandRunner` and `QuarantineService` use `@unchecked Sendable`; correctness relies on immutable fields, a serial queue, and callers retaining the service until completion.
- Safe modification: Prefer compiler-checked actors or value types, document completion guarantees, and make cancellation/lifetime behavior part of the protocol.
- Test coverage: AppModel covers stale completion suppression, but service deallocation, concurrent direct calls, cancellation, and queue ordering are not tested.

## Scaling Limits

**Interactive repair throughput:**
- Current capacity: One accepted application and one active repair at a time; only the first URL from a multi-item drop is selected.
- Limit: A slow command blocks all subsequent UI work for that repair path for up to roughly 90-120 seconds in worst-case near-timeout sequences.
- Files: `Sources/AppModule/AppModel.swift`, `Sources/AppModule/DropZoneView.swift`, `Sources/UnsealCore/QuarantineService.swift`
- Scaling path: Add an explicit bounded queue, per-item progress and results, cancellation, and batch semantics that either reject extra URLs clearly or process all accepted items.

**Direct service request backlog:**
- Current capacity: A single serial dispatch queue with no public queue-depth limit or cancellation token.
- Limit: Non-UI callers can enqueue an arbitrary number of long-running repairs, retaining closures and making completion latency proportional to backlog length.
- Files: `Sources/UnsealCore/QuarantineService.swift`
- Scaling path: Apply bounded admission, return an operation handle, expose cancellation, and consider limited concurrency only after isolating filesystem targets and resource budgets.

**Diagnostic history:**
- Current capacity: One in-memory `dropStatus` and one optional `lastDiagnostic`; state is cleared on request or termination.
- Limit: There is no per-item history, audit trail, or recovery context for batch use or support investigations.
- Files: `Sources/AppModule/AppModel.swift`, `Sources/AppModule/MenuContent.swift`, `Sources/AppModule/AppDelegate.swift`
- Scaling path: Store a bounded local history with timestamps and redacted paths, while keeping data collection opt-in and entirely local.

**Compatibility validation:**
- Current capacity: Release CI runs tests on one moving `macos-26` hosted environment and builds, but does not execute tests, for both universal architectures.
- Limit: The declared macOS 13 minimum, x86_64 runtime, and multiple Xcode/Swift patch versions can regress without pre-release detection.
- Files: `Package.swift`, `.github/workflows/release.yml`, `package_app.sh`
- Scaling path: Add a supported-OS/toolchain matrix where hosted capacity permits, execute an x86_64 smoke test, and run a packaged-app launch/repair smoke test before publishing.

## Dependencies at Risk

**macOS command-line security tools:**
- Risk: Core behavior depends on fixed paths and exit semantics for `/usr/bin/xattr` and `/usr/sbin/spctl`; diagnostics also expose their localized output directly.
- Impact: A macOS behavior or output change can misclassify repair state even though the Swift code still builds.
- Files: `Sources/UnsealCore/QuarantineService.swift`, `README.md`
- Migration plan: Wrap each command behind typed adapters, test supported macOS versions with fixtures and live smoke tests, and prefer stable Security framework APIs where they provide equivalent assessment data.

**ServiceManagement plus LaunchAgent fallback:**
- Risk: `SMAppService` approval behavior and direct LaunchAgent loading are platform policies rather than repository-controlled contracts; fallback registration verifies plist content, not whether macOS actually loaded it.
- Impact: The UI can report enabled based on a file while login launch fails, and future macOS policy can remove the fallback path.
- Files: `Sources/AppModule/LaunchAtLoginController.swift`, `package_app.sh`
- Migration plan: Make `SMAppService` the supported production mechanism, retain fallback only for explicitly unsupported development builds, verify observed launch state, and provide a migration/removal path.

**Swift 6.2 and moving hosted runner:**
- Risk: `swift-tools-version: 6.2` requires a recent toolchain while CI relies on the default Xcode selected by the mutable `macos-26` image.
- Impact: A runner-image update can change compiler diagnostics or break releases without a repository change; older developer toolchains cannot build the package.
- Files: `Package.swift`, `.github/workflows/release.yml`, `README.md`
- Migration plan: Select and print a supported Xcode version explicitly, document a tested version range, add a matrix for the minimum supported compiler where feasible, and review image changes before release.

**GitHub Actions release components:**
- Risk: `actions/checkout@v4` and `actions/upload-artifact@v4` are mutable tag references, and `gh` behavior comes from the hosted image.
- Impact: Upstream changes affect a write-enabled supply-chain path and can alter release contents or publication semantics.
- Files: `.github/workflows/release.yml`
- Migration plan: Pin reviewed SHAs, pin or verify critical CLI versions, use least privilege, and add artifact attestations.

**Third-party Swift packages:**
- Risk: Not detected; the package currently depends only on Apple frameworks and the local `UnsealCore` target.
- Impact: Runtime dependency supply-chain exposure is low, but system-framework and toolchain coupling remains concentrated.
- Files: `Package.swift`
- Migration plan: Preserve the minimal dependency set; require review, version pinning, and a committed resolution file before adding external packages.

## Missing Critical Features

**Transactional, trust-aware repair:**
- Problem: There is no preflight display of signing identity/notarization, explicit risk confirmation, saved quarantine value, or rollback after a failed postflight assessment.
- Blocks: The app cannot guarantee that a reported failure leaves the bundle in its original security state.
- Files: `Sources/UnsealCore/QuarantineService.swift`, `Sources/UnsealCore/Diagnostics.swift`, `Sources/AppModule/DropZoneView.swift`, `Sources/AppModule/MenuContent.swift`

**Cancellation and total operation deadline:**
- Problem: The UI can ignore a late result but cannot cancel the active subprocess or queued work, and each command has an independent timeout rather than one repair deadline.
- Blocks: Users cannot recover promptly from a hung or unexpectedly slow repair, and clean application termination does not explicitly stop the work.
- Files: `Sources/UnsealCore/QuarantineService.swift`, `Sources/AppModule/AppModel.swift`, `Sources/AppModule/AppDelegate.swift`

**Continuous validation before release:**
- Problem: There is no PR/default-branch CI, packaged-app integration test, required signed-release gate, immutable tag checkout, or artifact provenance/attestation.
- Blocks: Maintainers cannot make publication depend on the same reviewed commit and security checks across every release path.
- Files: `.github/workflows/release.yml`, `package_app.sh`, `Package.swift`

**Explicit multi-item behavior:**
- Problem: The drop API accepts multiple applications but neither queues all items nor rejects extras with an explanation.
- Blocks: Reliable batch repair and per-item diagnostics are unavailable, and current acceptance feedback is misleading.
- Files: `Sources/AppModule/DropZoneView.swift`, `Sources/AppModule/AppModel.swift`, `Sources/AppModule/MenuContent.swift`

## Test Coverage Gaps

**Current automated baseline:**
- What's not tested: `swift test` passes 17 tests, but there is no coverage threshold or report to prevent erosion and no automated run before pull-request merge.
- Files: `Tests/UnsealCoreTests/QuarantineServiceTests.swift`, `Tests/AppModuleTests/AppModelTests.swift`, `Tests/AppModuleTests/LaunchAtLoginControllerTests.swift`, `.github/workflows/release.yml`
- Risk: A green suite can overstate confidence because entire UI, packaging, and real system integration surfaces are outside it.
- Priority: High

**Quarantine probe, validation, and rollback matrix:**
- What's not tested: Permission-denied and timeout probes, missing executable/launch failure, nonexistent `.app`, regular files named `.app`, top-level symlinks, metadata-read failure, renamed arbitrary directories, path replacement races, original-value preservation, and rollback.
- Files: `Sources/UnsealCore/QuarantineService.swift`, `Tests/UnsealCoreTests/QuarantineServiceTests.swift`
- Risk: Security-sensitive failures can be misclassified or mutate a different state than the test suite models.
- Priority: High

**Command runner lifecycle:**
- What's not tested: Capture directory/file failures, command launch failure, forced `SIGKILL` fallback, output truncation or large output, concurrent invocations, double-close behavior, and process cleanup after cancellation/termination.
- Files: `Sources/UnsealCore/QuarantineService.swift`, `Tests/UnsealCoreTests/QuarantineServiceTests.swift`
- Risk: Rare process failures can hang, leak resources, or return misleading statuses unnoticed.
- Priority: Medium

**Status item and SwiftUI interaction:**
- What's not tested: First context-menu state, left/right/control-click handling, popover opening/closing and sizing, multiple-item drops, help/settings links, retry/clear buttons, accessibility sizing, and AppDelegate lifecycle wiring.
- Files: `Sources/AppModule/StatusItemController.swift`, `Sources/AppModule/MenuContent.swift`, `Sources/AppModule/DropZoneView.swift`, `Sources/AppModule/SettingsView.swift`, `Sources/AppModule/AppDelegate.swift`
- Risk: User-visible regressions and no-op controls are not caught by the model-only tests.
- Priority: High

**Login-item failure and migration paths:**
- What's not tested: Unregister failure, fallback removal followed by service failure, unavailable and unknown statuses, malformed or stale plist data, existing fallback migration to `SMAppService`, hard-coded label collisions, filesystem permission errors, and actual login after reboot.
- Files: `Sources/AppModule/LaunchAtLoginController.swift`, `Tests/AppModuleTests/LaunchAtLoginControllerTests.swift`, `package_app.sh`
- Risk: Persistence can be reported incorrectly or remain enabled/disabled contrary to user preference.
- Priority: High

**Release and packaging automation:**
- What's not tested: Workflow-dispatch ref/tag alignment, checksum verification in downloaded layout, all-or-none production signing behavior, Info.plist escaping, archive contents, ad-hoc release labeling, and retry/update of an existing release.
- Files: `.github/workflows/release.yml`, `package_app.sh`, `generate_app_icon.sh`
- Risk: A source-correct application can still be packaged or published under the wrong identity, commit, signature, or checksum metadata.
- Priority: High

**Real macOS compatibility:**
- What's not tested: Live quarantine attributes, signed/notarized/rejected fixture apps, `spctl` behavior on the declared macOS 13 minimum, x86_64 execution, ServiceManagement approval states in a packaged app, and LaunchAgent behavior at login.
- Files: `Package.swift`, `Sources/UnsealCore/QuarantineService.swift`, `Sources/AppModule/LaunchAtLoginController.swift`, `.github/workflows/release.yml`
- Risk: Mocked command results and plist inspection can pass while the supported operating systems reject the actual workflow.
- Priority: High

---

*Concerns audit: 2026-07-13*
