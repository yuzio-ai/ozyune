# The release note convention

Release notes in this repository are not free-form. Every published body starts
from the same skeleton, so consecutive releases read alike and a note cannot
quietly drift from the last one. This document describes the convention, the
kit that enforces it, and how to lift the whole thing into another repository.

## The kit

Five files, and nothing else, make up the convention:

| File | Role | When porting |
|---|---|---|
| `scripts/release-notes-lib.sh` | shared loader; reads the config and exposes it to the scripts | copy **untouched** |
| `scripts/check-release-notes.sh` | style checker; enforces every invariant below | copy **untouched** |
| `scripts/render-release-notes.sh` | renders the note skeleton for a version | copy **untouched** |
| `.github/release-notes.conf` | the only per-repository settings file | **edit this** |
| `.github/RELEASE_NOTES_TEMPLATE.md` | the pinned skeleton, with authoring hints | keep the structure, adapt the product prose |

Everything repository specific — the product name, the GitHub slug, the notes
directory, the release asset, the languages and their section vocabularies —
lives in `.github/release-notes.conf`. The scripts read it through
`release-notes-lib.sh` and contain no repository specific values of their own.

Two helpers live next to the kit but are not part of it:

- `scripts/export-release-note-kit.sh` — packages the five files for another
  repository (`--copy <repo-root>` or `--tarball [<file>]`), with the conf
  values reset to their fallbacks;
- `scripts/test-release-notes-kit.sh` — adopts the kit into throwaway
  repositories and proves the behaviour above; CI runs it on every push.

## Adopting the convention in another repository

1. Copy the five kit files to the same relative paths (`scripts/`, `.github/`)
   — by hand, or with `bash scripts/export-release-note-kit.sh --copy <repo-root>`.
2. Edit `.github/release-notes.conf` only — see the reference below.
3. Adapt the product prose in `.github/RELEASE_NOTES_TEMPLATE.md`
   (Requirements / Installation etc.), keeping the structure: heading levels,
   section vocabulary and order, anchors, and the trailing changelog line are
   enforced by the checker and must not move. If you run a single-language
   configuration, drop the nav line, the anchors and the `## ` language
   headings from the template — only `### ` sections remain.
4. Wire the check into CI and any pre-release script:

   ```bash
   bash scripts/render-release-notes.sh --self-test   # template conformance
   bash scripts/check-release-notes.sh                # all published notes
   ```

   (see `.github/workflows/build.yml` and `scripts/preflight.sh` here).
5. Copy the release workflow from `CONTRIBUTING.md` — render, fill in, check,
   then `gh release create <tag> <asset> --title <tag> --notes-file <note>`.
6. Verify the port before publishing anything:

   ```bash
   bash scripts/render-release-notes.sh 0.1.0 --stdout | head
   bash scripts/check-release-notes.sh
   ```

## `.github/release-notes.conf` reference

| Variable | Meaning | Fallback |
|---|---|---|
| `REPO_SLUG` | `owner/repo`, used for changelog links | derived from the `origin` remote |
| `PRODUCT_NAME` | replaces `{{PRODUCT}}` in the template | repository name, verbatim |
| `NOTES_DIR` | where canonical notes live, relative to the root | `docs/releases` |
| `ASSET_NAME` | the release download; must not carry a version | `<PRODUCT_NAME>.zip` |

Pin `REPO_SLUG` explicitly once notes are published (that is what this
repository does): the committed notes link at the canonical slug, and a fork or
a renamed `origin` remote must not change what the checker expects of them.

`LANGUAGES` is an array; entries are processed in order and each carries six
pipe-separated fields:

```text
id | anchor | heading | marker | vocabulary | required
```

1. **id** — short prefix used in the checker's messages (`en`, `zh`, …).
2. **anchor** — target of `<a id="…">` and of the nav line's `href`.
3. **heading** — text of the `## ` heading that opens the language block.
4. **marker** — literal start of the block's closing changelog line, URL
   excluded (e.g. `**Full changelog**: `).
5. **vocabulary** — comma-separated section names, in the only order allowed.
6. **required** — comma-separated 0-based indexes into the vocabulary that
   every note must carry.

Two or more entries give a multi-language note: a nav line on the first line,
one anchor and one `## ` heading per language, each block closing with its own
changelog line. Exactly one entry gives a single-language note: no nav line, no
anchors, no `## ` headings — sections plus one closing changelog line.

## What the checker pins

`scripts/check-release-notes.sh` rejects any note that violates these — the
skeleton rendered by `render-release-notes.sh` is the only thing that passes
unfilled (`--skeleton` mode, used by `--self-test`):

1. multi-language notes open with the language nav line and carry the language
   blocks in the configured order — each `## ` language heading appears exactly
   once, with its own anchor before it;
2. `##` marks a language and `###` a section — no `#`, no `####`; a
   single-language note carries `###` sections only;
3. sections come from the configured vocabulary of their language and keep its
   order; nothing outside the vocabulary is allowed;
4. the required sections (Requirements / Installation here) are always present,
   and no surviving section is left empty;
5. no authoring hint (`<!-- … -->`) and no `{{placeholder}}` survives in a
   published note;
6. each language block closes with its configured changelog marker and a
   `compare/<previous-tag>...<tag>` link (`commits/<tag>` for the first
   release), and the tag matches the file name `docs/releases/<tag>.md`;
7. the asset is always `<ASSET_NAME>` — never `<stem>-<version>.zip`;
8. the release title is the tag itself: pass `--title <tag>` or omit `--title`
   (GitHub then defaults to the tag name) — never hand-type or re-case it.

## Template placeholders

`scripts/render-release-notes.sh` substitutes:

| Placeholder | Becomes |
|---|---|
| `{{PRODUCT}}` | `PRODUCT_NAME` |
| `{{VERSION}}` | the version argument (`0.1.0`) |
| `{{ASSET}}` | `ASSET_NAME` |
| `{{CHANGELOG_URL}}` | `compare/<previous>...<tag>`, or `commits/<tag>` for the first release |

Everything else — `{{ONE_LINE_SUMMARY}}` and friends — is filled in by hand
before `check-release-notes.sh` runs in full mode.

## The release workflow

```bash
bash scripts/render-release-notes.sh 1.2.0        # write docs/releases/v1.2.0.md
# fill in the prose; delete unused sections and every <!-- hint -->
bash scripts/check-release-notes.sh
git add docs/releases/v1.2.0.md && git commit -m "chore: release notes for v1.2.0"
# tag, build, notarize, package; run the pre-release check
./scripts/preflight.sh
gh release create v1.2.0 Ozyune.zip --title v1.2.0 --notes-file docs/releases/v1.2.0.md
```

The title is always the tag itself (rule 8 above). `CONTRIBUTING.md` carries the
repository-specific details of this sequence.
