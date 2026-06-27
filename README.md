# My Schedule

A KDE Plasma 6 day planner built around a single source of truth: **your authored
day plan** drives everything — the panel widget that tells you what to work on
right now, a vertical timeline of today, and "take a break" popups.

Nothing in the KDE ecosystem combined these; existing widgets either read an
external calendar, time pomodoros, or nag you to take breaks on a fixed interval.
This ties them together around a plan you write.

![Screenshot](/screenshot.png)

## What you get

| Piece | What it does |
|-------|--------------|
| **Panel widget** (`org.kde.myschedule`) | Shows the block you should be working on *right now*, with a progress bar. Click it for a **vertical timeline** of today. Always-on engine that also fires the break popups. |
| **Planner app** (`myschedule-planner`) | Standalone Kirigami window to author recurring time blocks: title, color, days of the week, from–to time, and whether it's a break. Includes a per-weekday timeline preview and overlap warnings. |
| **Breaks** | Two kinds: **scheduled** break blocks (a "Lunch 12:30–13:30" in your plan pops up when it starts) and an optional **interval nudge** ("stretch every 90 min"). |

## Architecture

```
shared/schedule.js   ── the "brain": pure functions (what's now, next break,
                        timeline, conflicts). Shared verbatim by both UIs and
                        unit-tested under node.
        │
        ├── plasmoid/  ── Plasma 6 widget. Reads schedule.json each tick,
        │                 computes the current block, fires notifications.
        └── app/       ── QML-only Kirigami planner. Authors schedule.json.

~/.config/myschedule/schedule.json   ── shared data file (dotfiles-friendly).
        app writes  ───────────────▶  widget reads
```

The data file is read/written through Plasma's `executable` data engine
(`cat` to read, base64-piped to write) so it works without enabling QML's
disabled-by-default local-file access. Blocks are **strictly sequential**
(no overlap); the planner warns if two blocks on the same day collide.

Weekdays use ISO numbering (1 = Monday … 7 = Sunday). Times are `"HH:MM"`.

## Install

```sh
./install.sh
```

Then:
- **Widget:** right-click your panel → *Add or Manage Widgets…* → search
  "My Schedule" → add it.
- **Planner:** run `myschedule-planner`, find *My Schedule Planner* in the app
  launcher, or click *Plan my day…* in the widget.

Requirements: Plasma 6, Qt 6 (`qt6-qtdeclarative`), Kirigami. `~/.local/bin`
should be on your `PATH` for the launch-from-widget button.

## Uninstall

```sh
./uninstall.sh           # keeps your schedule.json
./uninstall.sh --purge   # also deletes your data
```

## Develop / test

```sh
node tests/test_schedule.js          # unit-test the brain
qmllint -I /usr/lib64/qt6/qml app/*.qml plasmoid/package/contents/ui/*.qml
QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 \
    /usr/lib64/qt6/bin/qml app/main.qml   # headless load (surfaces runtime errors)
```

After editing `shared/schedule.js`, re-run `./install.sh` to copy it into both
packages (they hold copies, not symlinks, because the plasmoid is installed by
copying the whole package).

## Data format

```jsonc
{
  "version": 1,
  "settings": {
    "intervalBreaksEnabled": true,
    "intervalBreakMinutes": 90,
    "intervalBreakDurationMinutes": 5
  },
  "tasks": [
    { "id": "…", "title": "Deep Work", "color": "#3daee9",
      "days": [1,2,3,4,5], "start": "09:30", "end": "11:30", "isBreak": false,
      "notify": true, "leadMinutes": 0 }
  ]
}
```

`notify` fires a start reminder; `leadMinutes` makes it fire that many minutes
*before* the start (e.g. a gym block at 18:00 with `leadMinutes: 15` reminds you
at 17:45). The widget's timeline popup can page to other days with the ◂ ▸
buttons; done blocks dim and strike through.
