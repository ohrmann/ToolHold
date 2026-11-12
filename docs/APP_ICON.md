# App icon sources and packaging

The current AppIcon is derived from `MyApp/Assets.xcassets/th.imageset/th.png`. The owner reports that the main icons were generated with ChatGPT Images from his requirements and iteratively adjusted at his direction. That provenance does not guarantee uniqueness, exclusive copyright or third-party clearance. The full register and separate sources of screenshots/fixtures are in [ASSET_PROVENANCE.md](../ASSET_PROVENANCE.md).

## Derivative chain

The recorded icon workflow used image-generation editing to clean the TH master's exterior contour and alpha while preserving its design. Core Graphics then cropped/padded the image and exported platform sizes. The historical prompt is not a reproducible build input; no generator script for recreating the exact final artwork is checked in. Ordinary builds use the committed PNGs and need no image-generation service.

`MyApp/Assets.xcassets/AppIcon.appiconset/Contents.json` assigns eight PNG files to eleven slots:

| Platform | Files / dimensions | Appearance |
|---|---|---|
| iOS/iPadOS | `AppIcon-iOS-1024.png`, 1024×1024 | RGB, opaque navy background |
| macOS | `AppIcon-macOS-{16,32,64,128,256,512,1024}.png` at the indicated square sizes | RGBA, transparent outer padding and shadow; tile occupies 824 of 1024 pixels at the largest size |

The three source image sets `th`, `toolholdicon` and `toolhold2` each contain three byte-identical 1254×1254 PNGs assigned to 1×/2×/3× slots. They are not separately rendered resolutions. Home uses `toolholdicon`; the current AppIcon uses `th`, not the historical `toolhold2` iteration.

Earlier checks confirmed the slot dimensions/alpha properties and asset-catalog compilation for macOS and iOS Simulator. A 512-pixel macOS icon was visually reviewed. Those checks are not full Dock/device presentation QA. When changing icons, inspect `Contents.json`, pixel sizes, alpha and actual built-app appearance on affected platforms; keep provenance and permission scope up to date.

## Distribution terms

Branding is separate from the source-code license. [BRANDING_TERMS.md](../BRANDING_TERMS.md) lists the exact three sets and their AppIcon derivatives. It accommodates technical forks, local/CI builds, necessary technical adaptations and permitted app distribution, and was approved by the owner with effect from **2026-11-12**. Its scope does not extend to future artwork, screenshots as a whole, system symbols or unknown third-party resources.
