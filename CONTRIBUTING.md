# Contributing to Ozyune

Ozyune is intentionally small. Contributions should preserve that constraint unless a larger architectural change is explicitly agreed first.

## Development setup

Requirements:

- macOS 14+
- Xcode 16+
- Node.js / `npx`

Open `Ozyune.xcodeproj`, select the `Ozyune` scheme, and run on **My Mac**.

## Before opening a pull request

Please make sure:

- the project builds successfully;
- launching Ozyune starts one managed dsh process;
- the dsh Web UI loads inside the app window;
- quitting Ozyune terminates the managed dsh process;
- no external browser opens during normal startup;
- the change does not add unrelated native UI or duplicate dsh functionality.

## Code conventions

- Prefer Apple-native APIs and SwiftUI/AppKit/WebKit over third-party dependencies.
- Keep process management inside `OzyuneProcessManager`.
- Keep WebKit-specific behavior inside `OzyuneWebView`.
- Avoid introducing a Swift ↔ JavaScript bridge unless a feature genuinely requires one.
- Keep user-facing errors concise and actionable.
- Do not hard-code the default dsh port; Ozyune currently requests an OS-assigned port.

## Pull requests

Keep pull requests focused. A PR should explain:

1. what changed;
2. why it belongs in the native shell;
3. how it was tested;
4. any lifecycle or process-management edge cases introduced.

For larger architectural changes, open an issue first so the boundary can be agreed before implementation.
