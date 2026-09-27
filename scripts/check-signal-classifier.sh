#!/bin/bash
#
# check-signal-classifier.sh — AgentSignalClassifier fixture check.
#
# Compiles Ozyune/AgentSignal.swift together with scripts/signal-fixtures and
# runs the cases. This is the regression net for the dsh wire vocabulary: if a
# dsh release renames an event or reshapes a payload, this fails instead of
# notifications going quietly dead.
#
# Usage:
#   bash scripts/check-signal-classifier.sh
#
# 全部通过退出码为 0，任意一项失败退出码为 1。

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ozyune-signal-check.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

if ! command -v xcrun >/dev/null 2>&1; then
    echo "❌ xcrun not found — install the Xcode command line tools." >&2
    exit 1
fi

# Top-level code must live in `main.swift`, hence the fixture directory.
xcrun swiftc \
    -module-cache-path "$WORK_DIR/modulecache" \
    "$REPO_ROOT/Ozyune/AgentSignal.swift" \
    "$REPO_ROOT/scripts/signal-fixtures/main.swift" \
    -o "$WORK_DIR/signal-check" || {
        echo "❌ fixture check failed to compile" >&2
        exit 1
    }

"$WORK_DIR/signal-check"
