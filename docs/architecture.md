# Ozyune Architecture

## Scope

Ozyune is currently a native macOS shell around the existing dsh Web application.

The architecture deliberately separates responsibilities:

| Layer | Owns |
|---|---|
| Ozyune native shell | App lifecycle, process lifecycle, native window, WebView, native file panels, system notifications |
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

## Agent attention signals

Ozyune posts macOS system notifications when the agent needs the user's judgment
(permission approval, `ask_user_question`, `exit_plan_mode` review), and when a
run ends in a way the user did not ask for: completion, failure, or an early
stop. Ends the user caused themselves stay silent.

```text
dsh host ──WebSocket (JSON frames)──> dsh Web UI (WKWebView)
                                          │  injected page-world script subclasses
                                          │  WebSocket and drops frames with no
                                          │  marker before they cross the bridge
                                          ▼
                          window.webkit.messageHandlers.ozyuneAgentSignals
                                          ▼
                          AgentSignalClassifier (pure function)
                                          ▼
                          NotificationController (delivery policy + cooldown)
                                          ▼
                          UNUserNotificationCenter (banner, click → focus app)
```

Rules the design upholds:

- **Read-only side channel.** The observer never sends requests to the host and
  never modifies the page's traffic; it only forwards frame text. No dsh
  configuration or profile is touched.
- **Structural classification.** Frames are parsed as JSON and only live
  journal `event` items are considered. Follow snapshots replay history and
  must not notify; message content that merely quotes an event name cannot
  match, because structural fields are unescaped JSON.
- **Pure classifier, one vocabulary.** `AgentSignalClassifier` maps frame text
  to a signal and nothing else. The markers (`approval/asked`, `tool/call` with
  `ask_user_question`/`exit_plan_mode`, `turn/end`) live in that type alone, and
  the page-side prefilter is generated from them, so the two consumers cannot
  drift apart.
- **Reasons, not just boundaries.** `turn/end` carries a merge-extensible
  `reason` (`TurnEndReasonMap` in `dsh-session`). `completed` reports the task
  as finished, `error` reports a failure, `blocked` and `max-tokens` report an
  early stop, and `aborted` / `interrupted` stay silent — a cancelled run was
  stopped by the user, a parent, a hook or teardown, and everyone involved
  already knows. An absent or unknown reason falls back to "finished".
- **Policy lives natively.** Delivery mode (default: only when Ozyune is not
  frontmost), per-kind cooldown, permission state and authorization failure
  handling belong to `NotificationController`, not to the bridge. The cooldown
  is only consumed once a banner is actually requested.
- **Signals are best-effort, but pinned.** They derive from the dsh Web wire
  vocabulary of the launched dsh version. `scripts/check-signal-classifier.sh`
  runs real frame fixtures in CI, so a renamed event or reshaped payload fails
  the build instead of silently disabling notifications;
  `OZYUNE_DEBUG_SIGNALS=1` traces every marker-bearing frame and its verdict to
  Console for the cases fixtures cannot predict.

## Current non-goals

The first version intentionally does not own:

- a native conversation UI;
- session/task projections;
- dsh plugin management;
- a general-purpose JavaScript bridge for application state (the notification
  observer is a one-way, single-purpose exception — see "Agent attention
  signals");
- a bundled Node/dsh runtime;
- update delivery;
- menu-bar or global overlay behavior.

These boundaries can change, but only when a native implementation provides a clear product or platform advantage.
