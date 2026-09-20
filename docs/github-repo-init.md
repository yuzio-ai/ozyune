# Ozyune · GitHub Repository Initialization

## Repository metadata

Recommended repository:

```text
yuzio-ai/ozyune
```

Recommended GitHub description:

> A lightweight native macOS home for dsh web.

Recommended visibility for the current stage:

```text
Private
```

Recommended default branch:

```text
main
```

### Topics

```text
macos
swift
swiftui
webkit
wkwebview
desktop-app
dsh
deepseek
```

Avoid adding generic topics such as `ai`, `agent`, or `llm` unless Ozyune itself starts owning those capabilities rather than merely presenting dsh.

## Local initialization

From the repository root:

```bash
git init
git branch -M main
git add .
git commit -m "chore: initialize Ozyune"
```

If GitHub CLI is installed and authenticated:

```bash
gh repo create yuzio-ai/ozyune \
  --private \
  --description "A lightweight native macOS home for dsh web." \
  --source . \
  --remote origin \
  --push
```

If the repository already exists on GitHub:

```bash
git remote add origin git@github.com:yuzio-ai/ozyune.git
git push -u origin main
```

## Recommended first commits

If you prefer a small commit history instead of one initial commit:

```text
chore: initialize Ozyune macOS project
feat: add managed dsh process lifecycle
feat: embed dsh web in WKWebView
brand: add Ozyune identity and app icon
docs: add repository and architecture documentation
ci: add macOS build workflow
```

## GitHub settings

Recommended repository settings:

- Issues: enabled
- Projects: optional
- Discussions: disabled initially; enable when there is a real external community
- Wiki: disabled
- Allow merge commits: optional
- Allow squash merging: enabled
- Allow rebase merging: enabled
- Automatically delete head branches: enabled

### Branch protection for `main`

Once CI has successfully run at least once, enable a ruleset for `main`:

- require pull request before merging;
- require at least 1 approval once more than one maintainer is active;
- require the `build` status check;
- require branches to be up to date before merging only if the repository volume justifies it;
- block force pushes;
- block branch deletion.

For a single-maintainer early repository, do not add approval requirements that block the maintainer from shipping.

## Repository files included

The initialized repository includes:

```text
.github/
├── ISSUE_TEMPLATE/
│   ├── bug_report.yml
│   ├── config.yml
│   └── feature_request.yml
├── pull_request_template.md
└── workflows/
    └── build.yml

CONTRIBUTING.md
docs/architecture.md
README.md
```

## License

Do not add an open-source license until the intended distribution model is decided.

Publishing source code without a license does not grant normal open-source reuse rights. When Ozyune's open-source strategy is decided, add the chosen `LICENSE` file explicitly rather than treating this as an incidental repository setting.

## Suggested repository About section

```text
A lightweight native macOS home for dsh web.
```

Website can remain empty until Ozyune has its own product page.
