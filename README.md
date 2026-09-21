# Awake

Native macOS app with a bundled Swift CLI and an authenticated HTTP API.

```sh
mise install
scripts/generate-api.sh
scripts/verify.sh
```

`project.yml` is the Xcode source of truth. Copy `Configuration/Local.xcconfig.example`
to `Configuration/Local.xcconfig` and set signing values for installation or releases.
Use `.agents/skills/try-it/scripts/try-it.sh` to install a local build. Use the
provisioned development-signing flow from the CloudKit reference when sync is enabled.

## Use the CLI and API

Choose **Install Command Line Tool** in the app, then add `~/.local/bin` to `PATH`.

```sh
awake status --json
awake show --json
awake api operations --json
awake api schema --json
awake config list --all true --json
awake config set show-welcome-message --value false --json
awake api token create --json
awake serve --port 8080 --json
```

The last command runs in the foreground. Read the token from the explicit credential
command and send it as `Authorization: Bearer <token>`. `GET /health` is the sole
unauthenticated route. `/ready`, `/openapi.json`, `/operations`, and `/v1/...` require
a token. Ctrl-C stops the server and leaves the app running. Only `127.0.0.1` and
`::1` are supported. Port `0` selects a free port and reports it in the ready event.
Tokens live in the app's Keychain; rotate or revoke using `api token rotate --force`
and `api token revoke --force`. Token commands are local-only and never prompt for
Keychain access. An unavailable or locked Keychain produces an actionable error.

Successful operation JSON is `{requestId,data}`. Failures go to stderr as
`{requestId?,error:{code,message,details?}}`; HTTP uses the corresponding status.
Exit codes are 0 success, 1 operation failure, 2 invalid invocation, 3 unavailable
backend or transport. A lost response after dispatch reports `outcome_unknown`;
inspect state before retrying. The transport never replays a mutation.

The CLI works without the HTTP listener. The running app owns mutable domain data.
Both interfaces call the same Swift operations through versioned private Unix IPC.
Shared validated TOML configuration also works without the app. Its path is reported
by `config-path`; `$XDG_CONFIG_HOME/awake/config.toml` defaults to
`~/.config/awake/config.toml`. Never add a second preferences store.

## Keep UI, CLI, and API capabilities consistent

Follow [Keeping the UI, CLI, and HTTP API consistent](docs/interface-consistency.md)
when adding a feature. One OpenAPI contract generates CLI/API interfaces and typed
service requirements; shared Swift services implement behavior. Native UI calls
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
Uploads use private UUID transfer handles and downloads stream temporary app exports.
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
