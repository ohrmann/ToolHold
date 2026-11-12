# Running the macOS helper

Xcode and its selected command-line toolchain are required; see [requirements and unsigned builds](../README.md#requirements). Opening the Xcode UI is not required for this shell-based run.

From the repository root:

```sh
./scripts/run-macos.sh
```

The [script](../scripts/run-macos.sh) builds Debug with the **ToolHold Navigation** scheme, macOS destination and `CODE_SIGNING_ALLOWED=NO`, then runs the ToolHold executable. Outputs go to the ignored `.build/idea-macos` directory. It supports paths containing spaces, stops on build failure and forwards arguments to the app. It does not change checked-in signing settings.

This helper targets the local Mac. It is not a verified native Swift debugger workflow or an iPhone deployment configuration. Use Xcode for Simulator/device selection and your own signing setup for physical devices. IDE-specific run configurations are not distributed; contributors can configure their preferred editor locally.
