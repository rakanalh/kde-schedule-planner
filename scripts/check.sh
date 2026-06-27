#!/usr/bin/env bash
# Local pre-push gate: formatting, lint, and tests. Run this before pushing.
#   ./scripts/check.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Locate the Qt 6 tools / QML import path across distros.
QMLLINT=""; QMLFORMAT=""; QMLPATH=""
for d in /usr/lib64/qt6/bin /usr/lib/qt6/bin /usr/lib/qt6/libexec; do
    [ -x "$d/qmllint" ] && QMLLINT="$d/qmllint"
    [ -x "$d/qmlformat" ] && QMLFORMAT="$d/qmlformat"
done
[ -z "$QMLLINT" ] && QMLLINT="$(command -v qmllint6 qmllint 2>/dev/null | head -1 || true)"
[ -z "$QMLFORMAT" ] && QMLFORMAT="$(command -v qmlformat6 qmlformat 2>/dev/null | head -1 || true)"
for d in /usr/lib64/qt6/qml /usr/lib/qt6/qml /usr/lib/x86_64-linux-gnu/qt6/qml; do
    [ -d "$d" ] && QMLPATH="$d"
done

QML_FILES=$(find app plasmoid -name '*.qml' | sort)
fail=0

echo "==> node unit tests"
node tests/test_schedule.js

echo "==> JS syntax (shared/schedule.js)"
node --check shared/schedule.js

echo "==> sample-schedule.json is valid JSON"
node -e "JSON.parse(require('fs').readFileSync('sample-schedule.json','utf8'))"

echo "==> shell script syntax"
for f in install.sh uninstall.sh app/myschedule-planner; do bash -n "$f"; done

echo "==> QML formatting (qmlformat)"
if [ -n "$QMLFORMAT" ]; then
    for f in $QML_FILES; do
        if ! "$QMLFORMAT" "$f" | diff -q "$f" - >/dev/null; then
            echo "   NOT FORMATTED: $f  (run: $QMLFORMAT -i $f)"; fail=1
        fi
    done
else
    echo "   (qmlformat not found — skipped)"
fi

echo "==> QML lint (qmllint)"
if [ -n "$QMLLINT" ] && [ -n "$QMLPATH" ]; then
    for f in $QML_FILES; do
        out=$("$QMLLINT" -I "$QMLPATH" "$f" 2>&1 | grep -iE ':[0-9]+:[0-9]+: (error|warning)' || true)
        if [ -n "$out" ]; then echo "   $f"; echo "$out" | sed 's/^/     /'; fail=1; fi
    done
else
    echo "   (qmllint or QML import path not found — skipped)"
fi

if [ "$fail" -ne 0 ]; then
    echo; echo "CHECKS FAILED"; exit 1
fi
echo; echo "ALL CHECKS PASSED"
