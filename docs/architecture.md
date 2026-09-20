# Ozyune Architecture

## Scope

Ozyune is currently a native macOS shell around the existing dsh Web application.

The architecture deliberately separates responsibilities:

| Layer | Owns |
|---|---|
| Ozyune native shell | App lifecycle, process lifecycle, native window, WebView, native file panels |
| dsh host | Agent/runtime behavior, APIs, session state, Web server |
| dsh Web UI | Product interface rendered inside `WKWebView` |

## Startup lifecycle

```text
Ozyune launches
    ↓
OzyuneProcessManager starts /bin/zsh
    ↓
npx @deepseek-ai/dsh web --no-open --port 0
    ↓
dsh completes startup
    ↓
dsh prints its ready URL
    ↓
Ozyune parses the URL
    ↓
OzyuneWebView loads the URL
```

Ozyune does not assume port `3080`. It requests an OS-assigned port with `--port 0` and treats the dsh ready URL as the source of truth.

## Shutdown lifecycle

```text
User quits Ozyune
    ↓
AppDelegate asks OzyuneProcessManager to stop
    ↓
SIGTERM
    ↓
short grace period
    ↓
SIGKILL only if necessary
    ↓
App exits
```

The app must not leave the process it started running after termination.

## Failure model

Ozyune should surface native startup failure when:

- the shell cannot be launched;
- `npx` / Node cannot be resolved;
- dsh exits before becoming ready;
- startup does not reach readiness within the configured timeout.

A retry should tear down any owned process first, then start a fresh one.

## Current non-goals

The first version intentionally does not own:

- a native conversation UI;
- session/task projections;
- dsh plugin management;
- a JavaScript bridge for application state;
- a bundled Node/dsh runtime;
- update delivery;
- menu-bar or global overlay behavior.

These boundaries can change, but only when a native implementation provides a clear product or platform advantage.
