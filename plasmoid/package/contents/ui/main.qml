/*
 * My Schedule — panel widget.
 *
 * Always-on engine: every tick it reloads the shared schedule, figures out
 * which time block you are in right now, drives the compact (panel) and full
 * (vertical timeline) views, and fires "take a break" notifications for both
 * scheduled break blocks and optional interval nudges.
 */
pragma ComponentBehavior: Bound

import QtQuick
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5
import org.kde.plasma.plasmoid
import "../code/schedule.js" as Sched

PlasmoidItem {
    id: root

    // ---- live state, bound by the representations -------------------------
    property var schedule: Sched.emptySchedule()
    property var currentTask: null
    property var nextTask: null
    property var todayEntries: []        // timeline entries (tasks + free gaps)
    property real currentProgress: 0
    property int remainingMinutes: 0
    property date now: new Date()

    // ---- notification bookkeeping ----------------------------------------
    property var _notifiedToday: ({})     // task.id → true once its reminder fired today
    property int _lastIntervalMin: -1     // minutesOfDay of last interval nudge
    property int _trackedIso: -1          // reset per-day state when the date rolls over

    Plasmoid.icon: "myschedule"
    Plasmoid.status: currentTask ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.PassiveStatus
    toolTipMainText: currentTask ? currentTask.title : i18n("My Schedule")
    toolTipSubText: currentTask ? Sched.rangeLabel(currentTask) + " · " + remainingMinutes + i18n(" min left") : (nextTask ? i18n("Next: %1 at %2", nextTask.title, nextTask.start) : i18n("Nothing scheduled"))

    Storage {
        id: storage
        onLoaded: function (s) {
            root.schedule = s;
            root.recompute();
        }
        onParseError: function (msg) {
            console.warn("MySchedule:", msg);
        }
    }

    // Fire-and-forget shell commands (notifications + launching the planner).
    // We use notify-send rather than KNotification because it is dead-simple and
    // proven to reach the notification daemon from plasmashell's environment.
    P5.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: function (source) {
            exec.disconnectSource(source);
        }
    }
    property int _cmdNonce: 0
    function _shq(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'";
    }
    function _run(cmd) {
        root._cmdNonce += 1;
        exec.connectSource(cmd + " # " + root._cmdNonce);
    }

    // Tick frequently enough to feel live, cheap because the work is tiny.
    Timer {
        id: tick
        interval: 20000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: storage.load()
    }

    function recompute() {
        var d = new Date();
        now = d;
        var iso = Sched.isoDay(d);

        // New day → clear per-day notification memory.
        if (iso !== _trackedIso) {
            _trackedIso = iso;
            _notifiedToday = {};
            _lastIntervalMin = Sched.minutesOfDay(d); // don't fire instantly on rollover
        }

        currentTask = Sched.currentTask(schedule, d);
        nextTask = Sched.nextTask(schedule, d);
        todayEntries = Sched.timeline(schedule, iso, Plasmoid.configuration.timelineStartHour * 60, Plasmoid.configuration.timelineEndHour * 60);
        currentProgress = Sched.progress(currentTask, d);
        var rem = Sched.remainingMinutes(currentTask, d);
        remainingMinutes = rem === null ? 0 : rem;

        evaluateNotifications(d);
    }

    function evaluateNotifications(d) {
        var nowMin = Sched.minutesOfDay(d);
        var today = Sched.tasksForDate(schedule, d);

        // 1) Per-task start reminders: fire at (start - leadMinutes), once per day.
        //    The 1-minute window plus the per-day dedup set means we fire exactly
        //    once, and never retroactively for blocks whose reminder already passed
        //    before the widget started (or for blocks edited later in the day).
        for (var i = 0; i < today.length; i++) {
            var t = today[i];
            if (!t.notify || _notifiedToday[t.id]) {
                continue;
            }
            var rm = Sched.reminderMinute(t);
            if (nowMin >= rm && nowMin - rm <= 1) {
                _notifiedToday[t.id] = true;
                if (t.isBreak) {
                    _lastIntervalMin = nowMin; // a planned break resets the interval clock
                    notify(i18n("Take a break"), t.title + " · " + Sched.rangeLabel(t), "media-playback-pause");
                } else if (t.leadMinutes > 0) {
                    notify(t.title, i18n("Starts in %1 min — at %2", t.leadMinutes, t.start), "appointment-soon");
                } else {
                    notify(t.title, i18n("Starting now · %1", Sched.rangeLabel(t)), "appointment-new");
                }
            }
        }

        // 2) Interval nudge (independent of the plan), if enabled.
        var st = schedule.settings || {};
        if (st.intervalBreaksEnabled && st.intervalBreakMinutes > 0) {
            if (_lastIntervalMin < 0) {
                _lastIntervalMin = nowMin;
            } else if (nowMin - _lastIntervalMin >= st.intervalBreakMinutes) {
                _lastIntervalMin = nowMin;
                notify(i18n("Take a break"), i18n("You've been at it for %1 minutes — stand up and stretch.", st.intervalBreakMinutes), "media-playback-pause");
            }
        }
    }

    function notify(title, text, icon) {
        _run("notify-send --app-name=" + _shq("Schedule Planner") + " --icon=" + _shq(icon || "myschedule") + " " + _shq(title) + " " + _shq(text));
    }

    function launchPlanner() {
        var cmd = Plasmoid.configuration.plannerCommand;
        if (!cmd || cmd.length === 0) {
            return;
        }
        // If it's a bare command name, don't depend on plasmashell's PATH —
        // try it, but fall back to the absolute install location.
        if (cmd.indexOf("/") === -1) {
            _run("command -v " + cmd + " >/dev/null 2>&1 && exec " + cmd + " || exec \"$HOME/.local/bin/" + cmd + "\"");
        } else {
            _run(cmd);
        }
    }

    compactRepresentation: CompactRepresentation {
        plasmoidItem: root
    }
    fullRepresentation: FullRepresentation {
        plasmoidItem: root
    }

    PlasmaCore.Action {
        id: planAction
        text: i18n("Plan my day…")
        icon.name: "view-calendar-day"
        onTriggered: root.launchPlanner()
    }

    Component.onCompleted: {
        Plasmoid.setInternalAction("plan", planAction);
    }
}
