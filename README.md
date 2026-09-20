<p align="center">
  <img src="design/ozyune-logo.png" width="180" alt="Ozyune logo">
</p>

<h1 align="center">Ozyune</h1>

<p align="center">
  A lightweight native macOS home for <code>dsh web</code>.
</p>

<p align="center">
  <strong>Native launch. Embedded Web UI. Minimal surface.</strong>
</p>

## Overview

Ozyune is a small macOS application that wraps the existing `dsh web` experience in a native app window.

The first version intentionally does only three things:

- launches `dsh web --no-open --port 0` when Ozyune starts;
- displays the dsh Web UI inside a native `WKWebView`;
- stops the dsh process managed by Ozyune when the app quits.

Ozyune does **not** reimplement the dsh interface or agent runtime. The goal is to keep the native shell thin and let dsh continue to own its Web application and runtime behavior.

> Ozyune is an independent project and is not an official DeepSeek application.

## Current status

**Early development / v0.1**

The current build is intentionally minimal. There is no native session list, menu-bar companion, bundled Node runtime, updater, or custom dsh UI.

## Requirements

- macOS 14 or later
- Xcode 16 or later recommended
- Node.js and `npx` available in the user's shell environment
- network access when `npx` needs to resolve or download `@deepseek-ai/dsh`

## Run locally

1. Clone the repository.
2. Open `Ozyune.xcodeproj` in Xcode.
3. Select the `Ozyune` scheme.
4. Select **My Mac** as the run destination.
5. Press **Run**.

Ozyune currently launches:

```bash
npx --yes @deepseek-ai/dsh web --no-open --port 0
```

It waits for the dsh ready URL, then loads that URL directly inside `WKWebView`. No external browser is opened.

## Architecture

```text
Ozyune.app
├── OzyuneProcessManager
│   ├── launches dsh
│   ├── observes stdout / stderr
│   ├── detects the ready URL
│   └── owns process teardown
│
└── OzyuneWebView
    └── WKWebView
        └── dsh Web UI
```

See [`docs/architecture.md`](docs/architecture.md) for the current boundary and lifecycle rules.

## Project structure

```text
Ozyune/
├── .github/
│   ├── ISSUE_TEMPLATE/
│   ├── pull_request_template.md
│   └── workflows/build.yml
├── design/
│   └── ozyune-logo.png
├── docs/
│   └── architecture.md
├── Ozyune.xcodeproj/
├── Ozyune/
│   ├── AppDelegate.swift
│   ├── Assets.xcassets/
│   ├── ContentView.swift
│   ├── Info.plist
│   ├── OzyuneApp.swift
│   ├── OzyuneProcessManager.swift
│   └── OzyuneWebView.swift
├── CONTRIBUTING.md
├── LICENSE
└── README.md
```

## Design principles

- **Thin native shell** — do not duplicate dsh business logic in Swift without a clear reason.
- **Native where it matters** — lifecycle, windowing, file dialogs, and future macOS integrations belong to the app shell.
- **Web where it already works** — the existing dsh Web UI remains the product surface for now.
- **Small scope first** — new native features should solve a concrete limitation rather than grow the shell by default.

## Roadmap

Near-term possibilities, not commitments:

- bundle a controlled Node + dsh runtime instead of depending on the user's shell environment;
- improve native startup / recovery diagnostics;
- add macOS-specific integrations only where they materially improve the experience;
- establish signing, notarization, packaging, and update delivery when distribution begins.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md).

## License

Ozyune is released under the [MIT License](LICENSE).
