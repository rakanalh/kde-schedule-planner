#!/usr/bin/env bash
# Removes My Schedule. Keeps your schedule.json unless --purge is given.
set -euo pipefail

DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
say() { printf '\033[1;34m==>\033[0m %s\n' "$1"; }

say "Removing plasmoid"
kpackagetool6 --type Plasma/Applet --remove org.kde.myschedule 2>/dev/null || true

say "Removing app, launcher, icons and desktop entry"
rm -rf "$DATA_HOME/myschedule"
rm -f "$HOME/.local/bin/myschedule-planner"
rm -f "$DATA_HOME/applications/myschedule-planner.desktop"
rm -f "$DATA_HOME"/icons/hicolor/*/apps/myschedule.png
kbuildsycoca6 >/dev/null 2>&1 || true

if [ "${1:-}" = "--purge" ]; then
    say "Purging schedule data"
    rm -rf "$CONFIG_HOME/myschedule"
else
    say "Kept your schedule at $CONFIG_HOME/myschedule/schedule.json (use --purge to delete)"
fi

say "Done. You may need to remove the widget from your panel if it was added."
