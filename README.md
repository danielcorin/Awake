# Awake

A menu-bar app that keeps your Mac — and its display — awake, with a bundled
Swift CLI that can do everything the UI can.

```sh
mise install
scripts/generate-api.sh
scripts/verify.sh
```

## What Awake holds

Awake holds the same public IOKit power assertions `caffeinate` uses. Each one is
a setting, and each can be overridden per session:

| Setting | Assertion | Effect | Default |
| --- | --- | --- | --- |
| `prevent-system-sleep` | `PreventUserIdleSystemSleep` | The Mac does not idle-sleep; the display may still dim. | on |
| `keep-display-on` | `PreventUserIdleDisplaySleep` | The display stays lit and the screen saver never starts. | on |
| `prevent-disk-idle` | `PreventDiskIdle` | Disks are not spun down while idle. | off |
| `default-duration-minutes` | — | Session length, 0–1440; `0` runs until stopped. | `0` |
| `activate-at-launch` | — | Start a session as soon as Awake launches. | off |
| `toggle-hotkey` | — | System-wide shortcut that toggles a session. Empty disables it. | none |

The UI is the menu bar icon: a sun while a session runs, a moon otherwise.
The panel drops straight down from the icon like a menu and closes when it
loses focus or you click away.
**Click it to toggle; Option-click (or right-click) opens the panel** with the
switch, the three assertion checkboxes, a duration, and **About** (icon and
version). `activate-at-launch` and the API address/port are CLI-only settings.
`awake show` opens the same panel; `awake status --json` reports the version.

Regenerate the app icon with `swift scripts/generate-app-icon.swift`; it renders
the Liquid Glass glyph and every legacy PNG from one set of geometry constants.

**Closing a laptop lid always sleeps the Mac.** That behavior is enforced below
the assertion layer, and the assertion that defers it (`InternalPreventSleep`) is
private API, so Awake deliberately does not claim to support it.

A session ends when its timer expires, when you stop it, or when Awake quits —
macOS releases a process's assertions on exit. `default-duration-minutes` caps at
1440 so a forgotten timer cannot hold the machine awake indefinitely.

```sh
awake on                                   # start with the configured defaults
awake on --display true --minutes 60       # one hour of display-only wakefulness
awake state --json                         # active, held assertions, seconds left
awake off
awake config set keep-display-on --value false
awake config set toggle-hotkey --value "opt+cmd+a"   # or record it in the panel
```

The shortcut needs at least one of Control, Option, or Command — Shift alone
would swallow ordinary typing — and is stored canonically, so `Command+Option+A`
reads back as `opt+cmd+a`. It is registered with `RegisterEventHotKey`, which
needs no Accessibility permission. macOS does not deliver global shortcuts to
background apps while the screen is locked.

Confirm the real assertions with `pmset -g assertions`, which lists Awake by name
while a session runs.

`project.yml` is the Xcode source of truth. Copy `Configuration/Local.xcconfig.example`
to `Configuration/Local.xcconfig` and set signing values for installation or releases.
Use `.agents/skills/try-it/scripts/try-it.sh` to install a local build. Use the
provisioned development-signing flow from the CloudKit reference when sync is enabled.

## Use the CLI

Choose **Install CLI** in the panel, then add `~/.local/bin` to `PATH`.

```sh
awake on --system true --display true --minutes 120 --json
awake state --json
awake off --json
awake status --json
awake show --json
awake api operations --json
awake api schema --json
awake config list --all true --json
awake config set keep-display-on --value false --json
```

Successful operation JSON is `{requestId,data}`. Failures go to stderr as
`{requestId?,error:{code,message,details?}}`. Exit codes are 0 success, 1 operation
failure, 2 invalid invocation, 3 unavailable backend or transport. A lost response
after dispatch reports `outcome_unknown`; inspect state before retrying. The
transport never replays a mutation.

The running app owns mutable domain data, reached over versioned private Unix IPC.
Shared validated TOML configuration also works without the app. Its path is reported
by `config-path`; `$XDG_CONFIG_HOME/awake/config.toml` defaults to
`~/.config/awake/config.toml`. Never add a second preferences store.

This app ships **no HTTP server**. `API/openapi.yaml` remains the operation contract
that generates the CLI, DTOs, and dispatch; set `"http": true` in `API/generation.json`
to also generate a server.

## Keep UI and CLI capabilities consistent

Follow [Keeping the UI, CLI, and HTTP API consistent](docs/interface-consistency.md)
when adding a feature. One OpenAPI contract generates the CLI and typed service
requirements; shared Swift services implement behavior. Native UI calls
those services and observes the same state, including changes made by automation.
Presentation and CLI customization stay in ordinary Swift.

The guide covers generic capability examples, read/write boundaries, device and
job adapters, UI refresh, shared scenarios, and the limits of programmatic checks.

## Add a feature

1. Add its schemas and operation to `API/openapi.yaml`, with a unique `operationId`
   and `x-cli.command` plus bindings. Use the existing operations as examples.
2. Run `scripts/generate-api.sh`. It builds two generators from the pinned,
   locally vendored `Packages/AppAutomation` graph and regenerates DTOs, typed inputs,
   required service protocols, dispatch, CLI commands, HTTP handlers, and discovery.
3. Implement the generated protocol requirement in the app's Swift service and
   call that service from the UI directly. Keep persistence mutations internal to
   the core module. Exposed stores conform to a `TypeNameReadAccess` Swift protocol;
   the declaration gate rejects new public methods outside that read surface.
   Keep UI read models refreshed after external service writes, and test the native
   action's delegation and observable result. Extend compiler probes for new stores.
4. Add Swift renderers or replacements in `Sources/CLI/Custom`. For example,
   `environment.render(APIOperations.Status.self) { status in status.appName }`.
   A replacement command constructs `APIInputs.*` and calls `environment.client.call`.
   `--json` retains the common result envelope. No Swift function names go into YAML.
5. Add a typed scenario in `TestsSupport/AppScenarios.swift`. Supply generated inputs
   and assert the behavior with `require(...)`. The same Swift assertions run
   through the direct service, CLI, and HTTP. Missing operation coverage fails.
6. Run `scripts/verify.sh`; commit the spec, generated sources, locks, manifest,
   and tests together. The script runs the compiler/declaration boundary checks,
   coverage rejection tests, domain/runtime tests, transport scenarios, and builds.
   Xcode also checks generated files and UI access boundaries before compilation.

The initial generator supports one CLI group, scalar inputs, and string/integer
arrays. Unsupported input shapes and ambiguous bindings fail generation. Add a
reusable generator capability with tests before relying on a new schema shape.
Use `--input-file input.json` for complete inputs, `--clear field` for nullable
updates, JSON arrays for collections, `--file` for uploads, and `--output` for
binary downloads. Do not combine `--input-file` with individual input fields.

Keep request JSON within 1 MiB, files within 25 MiB, and paginate large collections.
Every meaningful GUI mutation and inspection needs an operation; device actions
need explicit capability/status behavior. Secrets never belong in TOML or logs.

Release builds use `scripts/publish-release.sh` for signing, notarization, and
packaging. Keep the embedded helper and `scripts/verify-no-coverage.sh` checks intact.

## Required verification

`.github/workflows/verify.yml` runs the deterministic **App verification** check
on pull requests, pushes to `main`, and merge queues. Run the same gate locally:

```sh
scripts/verify.sh
```

For a hosted repository, install the required branch rule and check it:

```sh
python3 scripts/require-verification.py --apply
python3 scripts/require-verification.py
```

Repository administrator access and a GitHub plan supporting rules for the
repository's visibility are required. The command reports unavailable enforcement
as a failure; the presence of a CI workflow alone does not block merging.
Results from executed scenarios are written to `build/verification/scenarios.json`.
OS permissions and app lifecycle use explicit unavailable cases in the isolated
fixture and still need signed-app verification when those adapters change.
