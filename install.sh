#!/usr/bin/env bash
# Installs My Schedule: the Plasma 6 panel widget + the standalone planner app.
# Safe to re-run (upgrades in place).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
BIN_DIR="$HOME/.local/bin"
APP_DIR="$DATA_HOME/myschedule/app"
APPS_DIR="$DATA_HOME/applications"
SCHEDULE_FILE="$CONFIG_HOME/myschedule/schedule.json"
LEGACY_SCHEDULE_FILE="$DATA_HOME/myschedule/schedule.json"

say() { printf '\033[1;34m==>\033[0m %s\n' "$1"; }

# 1. Sync the canonical brain into both packages (copy, never symlink — the
#    plasmoid package is copied wholesale at install time).
say "Syncing shared schedule.js into both packages"
cp "$REPO/shared/schedule.js" "$REPO/plasmoid/package/contents/code/schedule.js"
cp "$REPO/shared/schedule.js" "$REPO/app/schedule.js"

# 2. Install / upgrade the plasmoid.
PLASMOID_ID="org.kde.myschedule"
if kpackagetool6 --type Plasma/Applet --list 2>/dev/null | grep -qx "$PLASMOID_ID"; then
    say "Upgrading plasmoid $PLASMOID_ID"
    kpackagetool6 --type Plasma/Applet --upgrade "$REPO/plasmoid/package"
else
    say "Installing plasmoid $PLASMOID_ID"
    kpackagetool6 --type Plasma/Applet --install "$REPO/plasmoid/package"
fi

# 3. Install the standalone app QML.
say "Installing planner app to $APP_DIR"
mkdir -p "$APP_DIR"
cp "$REPO/app/"*.qml "$APP_DIR/"
cp "$REPO/app/schedule.js" "$APP_DIR/"

# 4. Install the launcher on PATH.
say "Installing launcher to $BIN_DIR/myschedule-planner"
mkdir -p "$BIN_DIR"
install -m 0755 "$REPO/app/myschedule-planner" "$BIN_DIR/myschedule-planner"

# 5. Install the app icon into the hicolor theme (used by both app + widget).
say "Installing icons"
ICON_BASE="$DATA_HOME/icons/hicolor"
for png in "$REPO"/icons/hicolor/*/apps/myschedule.png; do
    sz="$(basename "$(dirname "$(dirname "$png")")")"
    mkdir -p "$ICON_BASE/$sz/apps"
    cp "$png" "$ICON_BASE/$sz/apps/myschedule.png"
done
gtk-update-icon-cache "$ICON_BASE" >/dev/null 2>&1 || true

# 6. Install the desktop entry (absolute Exec so it works regardless of PATH).
say "Installing desktop entry"
mkdir -p "$APPS_DIR"
sed "s|^Exec=.*|Exec=$BIN_DIR/myschedule-planner|" \
    "$REPO/myschedule-planner.desktop" > "$APPS_DIR/myschedule-planner.desktop"
update-desktop-database "$APPS_DIR" 2>/dev/null || true
kbuildsycoca6 >/dev/null 2>&1 || true

# 7. Provision the schedule under ~/.config (migrate, seed, or keep).
mkdir -p "$(dirname "$SCHEDULE_FILE")"
if [ -f "$SCHEDULE_FILE" ]; then
    say "Existing schedule kept at $SCHEDULE_FILE"
elif [ -f "$LEGACY_SCHEDULE_FILE" ]; then
    say "Migrating schedule $LEGACY_SCHEDULE_FILE → $SCHEDULE_FILE"
    mv "$LEGACY_SCHEDULE_FILE" "$SCHEDULE_FILE"
else
    say "Seeding a sample schedule at $SCHEDULE_FILE"
    cp "$REPO/sample-schedule.json" "$SCHEDULE_FILE"
fi

cat <<'DONE'

Installed.

Next steps:
  • Panel widget:  right-click your panel → "Add or Manage Widgets…" →
                   search "My Schedule" → add it.
  • Planner app:   run  myschedule-planner   (or find "My Schedule Planner"
                   in the app launcher), or click "Plan my day…" in the widget.

If "myschedule-planner" isn't found, ensure ~/.local/bin is on your PATH.
DONE
printf '\n'
