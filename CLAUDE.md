# Awake agent guide

Awake keeps the Mac awake by holding IOKit power assertions. `WakeSessionStore`
owns them and is the only place `IOPMAssertionCreateWithName` is called;
`WakeOperationService` resolves per-session overrides against the configured
defaults and implements `wakeOn`/`wakeOff`/`wakeState`. Inject a
`RecordingPowerAssertionController` in anything automated — a test that holds real
assertions keeps the developer's machine awake. Lid-closed sleep needs private
API and is out of scope; say so rather than approximating it.

The menu bar item is AppKit, not `MenuBarExtra`, because a plain click must
toggle the session and only Option/right-click opens the panel. The dropdown is
a borderless `NSPanel` rather than an `NSPopover`, which would draw a caret at
the status item. Two settings are load-bearing: `hidesOnDeactivate = false`
(panels default to true, so for an accessory app it hides the instant it
appears) and an activating style mask (a `.nonactivatingPanel` never activates
the app, so `didResignActive` never fires and it stays up after a click away). Both icon states
are centered in one fixed-size canvas and the item has a fixed length: SF Symbols
from different families have different glyph bounds and the item visibly shifts
on every toggle without this.

The app icon is generated: edit the geometry in `scripts/generate-app-icon.swift`
and re-run it, never the PNGs or SVG. Rays are emitted as explicit capsule paths
because actool renders SVG arcs with the opposite sweep to CoreGraphics; always
check the compiled `AppIcon.icns`, not just the legacy PNGs.

The global shortcut uses Carbon `RegisterEventHotKey` (no Accessibility prompt,
and it claims the combination) rather than an `NSEvent` global monitor. Parsing
lives in `HotkeyShortcut` so the TOML store rejects an unusable shortcut before
it reaches the registrar. Verifying that it fires needs a real key press on an
unlocked screen: synthesized events and a locked session both fail to dispatch.

Use `project.yml` as the only Xcode source of truth and regenerate with
`mise exec -- xcodegen generate`. Keep domain/persistence and generated API types
in `Sources/Shared`, Mac-only socket/TOML code in `Sources/Core`, and platform UI
in `Sources/App` or `Sources/Mobile`.

`API/openapi.yaml` is the public operation contract. Run `scripts/generate-api.sh`
after changing it, implement the required Swift service method, and add meaningful
GUI/CLI/HTTP verification. Custom behavior belongs in `Sources/CLI/Custom` Swift.
Never edit generated files or add a parallel handwritten route/command catalog.
Read [Keeping the UI, CLI, and HTTP API consistent](docs/interface-consistency.md)
when adding capabilities or changing UI/service boundaries. Apply its generic
feature-authoring loop to this app's domain.

The app owns mutable domain data. The CLI never opens a second mutable store. Commands are non-interactive, accept `--json`,
print results to stdout and errors to stderr, and require `--force` for destructive
actions. Use the shared TOML store for all non-secret runtime settings; no
`UserDefaults` or `@AppStorage`. This app has no HTTP server: `API/generation.json`
sets `"http": false`, so generation emits the CLI, DTOs, and dispatch only. Set it
to `true` (and restore the AutomationHTTP target) to add one.

Run `scripts/verify.sh` before handoff; CI executes the same deterministic gate.
UI persistence writes must use generated operations via Swift services. Add a
meaningful Swift scenario with every operation; exact declared coverage and all
three execution paths are enforced by the test runner. Use `*ReadAccess` protocols
for public read surfaces; keep underlying mutation methods internal to Core and
extend compiler probes for new stores. Test native action delegation and read-model
refresh after CLI/API mutations. Presentation state can stay local to views.

Verify the bundled helper, graceful shutdown, and no coverage instrumentation before
installation or release. CloudKit checks require real provisioning and the same
long-lived container on both platforms. Report unavailable CI enforcement or device
verification explicitly; the gate uses compiler results and assertions, with no
LLM pass/fail step.
