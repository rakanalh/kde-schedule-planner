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
    property var _notifiedToday: ({})     // id → true once its reminder fired today
    property int _trackedIso: -1          // reset per-day state when the date rolls over
    property string _lastCurrentId: ""    // for the "task changed" chime
    property bool _currentInit: false     // skip the chime on the very first tick
    property bool _soundThisTick: false   // collect all sound triggers, ring once

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
        }

        currentTask = Sched.currentTask(schedule, d);
        nextTask = Sched.nextTask(schedule, d);
        todayEntries = Sched.timeline(schedule, iso, Plasmoid.configuration.timelineStartHour * 60, Plasmoid.configuration.timelineEndHour * 60);
        currentProgress = Sched.progress(currentTask, d);
        var rem = Sched.remainingMinutes(currentTask, d);
        remainingMinutes = rem === null ? 0 : rem;

        _soundThisTick = false;

        // Audible cue when the widget auto-switches the current task (but not on
        // the first tick after loading — that's initialisation, not a change).
        var curId = currentTask ? currentTask.id : "";
        if (_currentInit && curId !== _lastCurrentId && Plasmoid.configuration.playSound) {
            _soundThisTick = true;
        }
        _lastCurrentId = curId;
        _currentInit = true;

        evaluateNotifications(d);

        // Ring at most once per tick, whatever combination of triggers fired.
        if (_soundThisTick) {
            playBell();
        }
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
                    notify(i18n("Take a break"), t.title + " · " + Sched.rangeLabel(t), "media-playback-pause");
                } else if (t.leadMinutes > 0) {
                    notify(t.title, i18n("Starts in %1 min — at %2", t.leadMinutes, t.start), "appointment-soon");
                } else {
                    notify(t.title, i18n("Starting now · %1", Sched.rangeLabel(t)), "appointment-new");
                }
            }
        }

        // 2) Interval breaks: only while working on a task, counted within it.
        //    Fire at taskStart + k*interval as long as that's before the task
        //    ends — so a task shorter than the interval never triggers one, and
        //    free time or breaks never do (you're already resting).
        var st = schedule.settings || {};
        if (st.intervalBreaksEnabled && st.intervalBreakMinutes > 0 && currentTask && !currentTask.isBreak) {
            var taskStart = Sched.toMinutes(currentTask.start);
            var taskEnd = Sched.effectiveEndMinute(currentTask);
            var step = st.intervalBreakMinutes;
            for (var k = 1; taskStart + k * step < taskEnd; k++) {
                var breakAt = taskStart + k * step;
                var key = "ib-" + currentTask.id + "-" + k;
                if (_notifiedToday[key]) {
                    continue;
                }
                if (nowMin >= breakAt && nowMin - breakAt <= 1) {
                    _notifiedToday[key] = true;
                    notify(i18n("Take a break"), i18n("You've been on “%1” for %2 minutes — stand up and stretch.", currentTask.title, k * step), "media-playback-pause");
                }
            }
        }

        // 3) One-time reminders for today's date: a persistent notification
        //    (stays until dismissed) that always rings, regardless of the widget.
        var oneTimers = Sched.oneTimeTasksOnDate(schedule, d);
        for (var j = 0; j < oneTimers.length; j++) {
            var ot = oneTimers[j];
            if (!ot.notify || _notifiedToday[ot.id]) {
                continue;
            }
            var otMin = Sched.toMinutes(ot.time);
            if (nowMin >= otMin && nowMin - otMin <= 1) {
                _notifiedToday[ot.id] = true;
                notify(ot.title, i18n("Reminder · %1", ot.time), "appointment-new", {
                    "persistent": true,
                    "forceSound": true
                });
            }
        }
    }

    function playBell() {
        _run("canberra-gtk-play -i bell 2>/dev/null || paplay /usr/share/sounds/freedesktop/stereo/bell.oga 2>/dev/null");
    }

    function notify(title, text, icon, opts) {
        opts = opts || ({});
        var cmd = "notify-send --app-name=" + _shq("Schedule Planner") + " --icon=" + _shq(icon || "myschedule");
        if (opts.persistent) {
            cmd += " --urgency=critical"; // stays until dismissed; also bypasses Do Not Disturb
        }
        cmd += " " + _shq(title) + " " + _shq(text);
        _run(cmd);
        if (opts.forceSound || Plasmoid.configuration.playSound) {
            _soundThisTick = true;
        }
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
