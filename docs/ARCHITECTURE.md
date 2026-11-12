# Architecture and engineering contracts

Developer Toolbox is a Swift/SwiftUI Apple-platform application. The app is branded ToolHold; package names and source paths retain Developer Toolbox names. [Package.swift](../Package.swift) defines independently testable cores and seven local package dependencies. The [Xcode project](<../Developer Toolbox.xcodeproj>) assembles the app and its UI tests. App deployment targets and core package minimums are different; see [requirements](../README.md#requirements).

## Layout

| Location | Responsibility |
|---|---|
| `MyApp/NavigationCore` | Canonical tool/category metadata, navigation rules and preferences |
| `MyApp/JSONCore`, `MyApp/JSONTool` | JSON processing and shared native editor integration |
| `MyApp/*Core` | Tool-specific processors, models, diagnostics and resource policies |
| Other `MyApp/` views/workspaces | SwiftUI presentation and per-window, per-tool state |
| `Vendor/` | Pinned local C/C++/Swift packages and bridges; OpenSSL XCFramework |
| `Tests/*CoreTests`, `Tests/JSONEditorTests` | SwiftPM regression suites and synthetic fixtures |
| `Tests/Native*`, `NavigationUITests` | Targeted platform probes and Xcode UI automation |
| `ThirdPartyNotices/`, `scripts/` | Upstream provenance, notices, generators and checks |

Use the [catalog](TOOL_CATALOG.md) to find a tool ID and its core. Prefer the existing typed processor/worker and workspace pattern over a new universal tool framework. Keep parsing and conversion outside SwiftUI views. Worker results must be revision-checked before publication; cancellation or changed input must not publish an obsolete result. Bound expensive input, output, nesting, iteration and image allocation before doing the work. Tests and source constants, rather than historical performance measurements, define the implemented limits.

## State and privacy

Inputs, outputs, credentials and generated keys are working data held in memory. Only allowlisted preferences such as navigation IDs and tool options are persisted. Favorites reference tool IDs; search filters canonical order and does not permit rearrangement. Do not add document contents to preferences, scene restoration, autosave, logs or diagnostics. Switching tools preserves the current window's in-memory work; a new session starts without restoring those documents.

Clipboard reads, copy and export are user actions. Native Undo, clipboard managers, exported files and system/provider staging can retain copies. Clearing the UI is not secure erasure. The app has no account/OAuth flow, cloud sync or credential vault. Generated keys are not imported into Keychain.

## Parsing and representations

- Keep JSON number lexemes, string escapes and Unicode identity where the operation promises lossless transformation. Do not silently round large integers, normalize distinct strings, remove duplicate members or treat invalid input as equal. Converters expose representation limits rather than promising arbitrary round trips.
- Editor/source ranges use UTF-16 where required by TextKit; byte offsets and grapheme positions are different units. Diagnostics identify the detected problem location, which need not be the original cause. Test EOF, CRLF, combining marks and surrogate pairs when changing range logic.
- Schema resources and registered references resolve locally. Do not add implicit remote resolution or execute data as code. The selected schema draft and the implemented JSONPath dialect are explicit constraints.
- JWT decoding is separate from signature verification and claims validation. Certificate inspection is separate from chain trust; offline inspection does not perform online revocation checks.
- QR generation uses Core Image; decoding uses the vendored QR-only ZXing-C++ bridge. Image processing checks dimensions and allocation bounds before decoding large images.

## Native editors and UI state

Preserve `NSTextView`/`UITextView` identity, caret, selection, native Undo, IME composition and scroll position across asynchronous work. Keep visible text, highlighting and gutters while a replacement result is pending; stale syntax results must not overwrite current input. Do not replace an active native editor to hide input or change its role during a representable update. Responder changes, including changing an active `UITextView`'s editability, can reenter SwiftUI; coordinate them outside that update and verify the affected runtime path.

Use bounded previews and lazy rendering for large collections. Expand/collapse and source navigation should have short native transitions (about 200 ms), respect Reduce Motion and allow newer user actions to interrupt them. Avoid automatic scrolling on each keystroke or stealing focus. A build or unit test does not establish visual smoothness; affected editor changes need focused runtime checks for rapid typing/paste, wrap, offscreen targets, diagnostics, selection and Undo.

## Embedded engines and preview networking

QuickJS evaluates only shipped bundles through fixed entry points. User SQL, JavaScript and markup are request data, never executable source. The bridge has no filesystem, network, module loader or host timers. It bounds memory, stack, deadlines and returned content; see [runtime policy](../Vendor/ToolboxScriptRuntime/README.md) and [bundle reproduction](../scripts/code-markup/README.md). PCRE2 uses its interpreter without JIT and bounded cancellation; preserve the native bridge's resource limits.

HTML, Markdown and MJML previews use nonpersistent WebKit state. Scripts, frames and general navigation are blocked. External resources are blocked by default; **Load external resources** explicitly permits HTTPS images, stylesheets and fonts for the current input, with permission revoked on input changes. It does not authorize fetch APIs, user-script execution, telemetry or submission of working text. Opt-in requests disclose resource URLs and connection metadata to hosts. Keep normal TLS validation and cancelled authentication prompts. Test WebKit restrictions under actual App Sandbox entitlements, not only an unsandboxed probe.

## Files and cryptographic ownership

Text imports validate the local file-URL boundary, use nonblocking regular-file reads and enforce size/change checks. Preserve bounded reads and atomic, no-clobber export behavior when changing file code. Do not import or export implicitly. PKI staging uses restricted local access, but remote/provider destinations and system staging have separate retention and protection limits; no universal secure-deletion or provider-ACL guarantee is made.

Cryptographic standards use the existing platform APIs and pinned upstream libraries. The PKI bridge owns OpenSSL handles in a private context; callers must release returned buffers with the matching function and respect borrowed-input lifetimes. Native cleanup does not guarantee erasure of Swift String/Data copies. A cancelled synchronous operation may still finish internally, but its stale result must not be published. See [PKI ownership](../Vendor/ToolboxPKI/README.md).

Dependency changes need exact versions, source checksums, license evidence, modification notices and relevant platform/security regressions. Preserve the upstream terms in [third-party notices](../THIRD_PARTY_NOTICES.md). Known export and dependency limitations remain in the [verification summary](../PUBLIC_RELEASE_AUDIT.md); architecture descriptions do not close release gates.
