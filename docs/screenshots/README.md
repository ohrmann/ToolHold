# ToolHold screenshots

These PNGs were captured on 2026-11-12 from a running Debug build of the actual macOS application in Light appearance. Each image contains only the app window, at 2880 × 1712 pixels (1440 × 856 points at 2×). They are native window-view captures, without generated artwork, compositing or retouching.

The capture session used the app's isolated UI-test preferences domain and temporarily populated its existing workspaces with the examples below. Results came from the application's normal processors. Temporary capture instrumentation was removed afterward; application source is unchanged.

| File | Screen | Example |
| --- | --- | --- |
| [home.png](home.png) | Home and navigation | Three favorites: JSON Formatter, Text Diff and X.509 Certificate Inspector; no working input. |
| [json-tool.png](json-tool.png) | JSON Formatter | Compact synthetic project metadata, formatted with two-space indentation and validated. |
| [text-tool.png](text-tool.png) | Text Diff | Two invented local preview configurations, showing three changed lines and one added line. |
| [pki-tool.png](pki-tool.png) | X.509 Certificate Inspector | The existing synthetic `Toolbox PUBLIC TEST Root` certificate, inspected locally. |

## JSON input

```json
{"project":"ToolHold Demo","environment":"local","release":{"version":"1.4.0","ready":true},"tools":[{"name":"JSON Formatter","category":"Data"},{"name":"Text Diff","category":"Text"}],"privacy":{"processing":"on device","savedInputs":false}}
```

The version and settings are invented example values, not release metadata or application configuration.

## Text comparison inputs

Before:

```text
# Local preview settings
APP_NAME=ToolHold Demo
LOG_LEVEL=info
CACHE_TTL=300
PREVIEW_THEME=light
FEATURE_JSON_TREE=false
```

After:

```text
# Local preview settings
APP_NAME=ToolHold Demo
LOG_LEVEL=debug
CACHE_TTL=600
PREVIEW_THEME=light
FEATURE_JSON_TREE=true
FEATURE_TEXT_DIFF=true
```

Both inputs end with a newline. These are demonstration text, not executable input or actual ToolHold settings.

## Certificate input

The public certificate comes from [Tests/PKICoreTests/Fixtures/root.pem](../../Tests/PKICoreTests/Fixtures/root.pem); its synthetic provenance is recorded in the [fixture notes](../../Tests/PKICoreTests/Fixtures/README.txt). Its subject and issuer are `CN=Toolbox PUBLIC TEST Root`. Only this public certificate was loaded, with PEM Base64 lines rewrapped to 36 characters for readability. No private key was loaded or displayed, and no certificate was installed or trusted. Inspection does not evaluate trust, certificate signatures or revocation, as stated in the app UI.

All examples are synthetic. No real credentials, personal data, customer content or internal URLs were used.
