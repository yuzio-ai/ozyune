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

## Releasing

Release notes are not free-form. Every published body starts from the same
skeleton, so consecutive releases read alike and a note cannot quietly drift from
the last one. The pinned structure lives in `.github/RELEASE_NOTES_TEMPLATE.md`,
`scripts/check-release-notes.sh` enforces it, and CI plus `scripts/preflight.sh`
both run that check.

1. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `Ozyune.xcodeproj`
   and commit.
2. Render the note skeleton for that version:

   ```bash
   bash scripts/render-release-notes.sh 1.2.0
   ```

   It resolves the previous tag from the repository, fills in the version and the
   changelog range, and writes `docs/releases/v1.2.0.md`. Fill in the prose in
   that file — keep the language order, the section names, the Requirements /
   Installation blocks and the trailing changelog line. Delete the sections you
   do not need, and every `<!-- ... -->` hint.
3. Check the style and commit the note together with the version bump:

   ```bash
   bash scripts/check-release-notes.sh
   git add docs/releases/v1.2.0.md
   git commit -m "chore: release notes for v1.2.0"
   ```

4. Tag, build, notarize and package as usual, then run the pre-release check
   against the built app. It validates the note style before it looks at the
   bundle:

   ```bash
   ./scripts/preflight.sh
   ```

5. Publish with the committed note as the release body:

   ```bash
   gh release create v1.2.0 Ozyune.zip --title v1.2.0 --notes-file docs/releases/v1.2.0.md
   ```

   The title is always the tag itself: pass `--title <tag>`, or omit `--title`
   entirely (GitHub then defaults to the tag name). Never hand-type it — release
   v1.0.0 shipped a `V1.0.0` title against a `v1.0.0` tag, and that casing
   mismatch is exactly the kind of drift this section exists to prevent.

What the checker pins, in short:

- `<a href="#english">English</a> | <a href="#简体中文">简体中文</a>` is the first line,
  and `## English` comes before `## 简体中文`;
- `##` marks a language and `###` marks a section — no `#`, no `####`;
- sections come from one vocabulary, in one order:
  `New / Changed / Fixed / How it works / Engineering / Known limitations / Requirements / Installation`
  (中文：新增 / 变更 / 修复 / 实现方式 / 工程质量 / 已知限制 / 系统要求 / 安装);
- `Requirements` and `Installation` (系统要求 / 安装) are always present, and no
  section is left empty;
- the download is always called `Ozyune.zip` — never `Ozyune-1.2.0.zip`;
- the release title is the tag (`v1.2.0`): pass `--title "$TAG"` or omit `--title`,
  which defaults to the tag name — never hand-type or re-case it;
- each language block closes with `compare/<previous-tag>...<tag>`
  (`commits/<tag>` only for the first release), and the tag matches the file name.
