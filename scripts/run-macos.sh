#!/bin/bash
set -euo pipefail

# Use the Xcode toolchain directly; IDEA's SDK model is not needed for this run.
toolbox_project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
toolbox_derived_data="$toolbox_project_dir/.build/idea-macos"

toolbox_build_args=(
  -project "$toolbox_project_dir/Developer Toolbox.xcodeproj"
  -scheme "ToolHold Navigation"
  -configuration Debug
  -destination 'platform=macOS'
  -derivedDataPath "$toolbox_derived_data"
  CODE_SIGNING_ALLOWED=NO
  build
)
/usr/bin/xcodebuild "${toolbox_build_args[@]}"

# exec keeps the app attached to IDEA's Run console and its Stop button.
exec "$toolbox_derived_data/Build/Products/Debug/ToolHold.app/Contents/MacOS/ToolHold" "$@"
