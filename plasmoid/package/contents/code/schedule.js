// MySchedule — shared scheduling "brain".
//
// Pure, stateless functions over an in-memory schedule object. NO file I/O,
// NO QML/DOM dependencies, so the exact same logic runs in:
//   * the Plasma 6 plasmoid (imported as a QML JS resource)
//   * the Kirigami planner app (same)
//   * node, for the test suite (via the CommonJS export at the bottom)
//
// Weekdays use the ISO convention: 1 = Monday ... 7 = Sunday.
// Times are "HH:MM" 24h strings. A task occupies [start, end) on each of `days`.
//
// Schedule shape:
//   {
//     version: 1,
//     settings: { intervalBreaksEnabled, intervalBreakMinutes, intervalBreakDurationMinutes },
//     tasks: [ { id, title, color, days:[1..7], start:"HH:MM", end:"HH:MM", isBreak } ]
//   }

function emptySchedule() {
    return {
        version: 1,
        settings: {
            intervalBreaksEnabled: false,
            intervalBreakMinutes: 90,
            intervalBreakDurationMinutes: 5
        },
        tasks: []
    };
}

// Normalise an arbitrary parsed object into a valid schedule (defensive: the
// file is user-editable and produced by an older version).
function normalize(obj) {
    var s = emptySchedule();
    if (obj && typeof obj === "object") {
        if (obj.settings && typeof obj.settings === "object") {
            if (typeof obj.settings.intervalBreaksEnabled === "boolean")
                s.settings.intervalBreaksEnabled = obj.settings.intervalBreaksEnabled;
            if (isFiniteNum(obj.settings.intervalBreakMinutes))
                s.settings.intervalBreakMinutes = obj.settings.intervalBreakMinutes;
            if (isFiniteNum(obj.settings.intervalBreakDurationMinutes))
                s.settings.intervalBreakDurationMinutes = obj.settings.intervalBreakDurationMinutes;
        }
        if (Array.isArray(obj.tasks)) {
            for (var i = 0; i < obj.tasks.length; i++) {
                var t = normalizeTask(obj.tasks[i]);
                if (t) s.tasks.push(t);
            }
        }
    }
    return s;
}

function normalizeTask(t) {
    if (!t || typeof t !== "object") return null;
    var id = t.id ? String(t.id) : genId();
    var title = t.title ? String(t.title) : "Untitled";
    var color = isValidColor(t.color) ? t.color : "#3daee9";
    var notify = (typeof t.notify === "boolean") ? t.notify : true;

    // One-time task: a point-in-time reminder (a date + a notification time),
    // NOT a range. The blank days/start/end keep it out of the weekday timeline
    // and the widget's current-task logic — it only ever fires a notification.
    if (isValidDate(t.date)) {
        var time = isValidTime(t.time) ? t.time : (isValidTime(t.start) ? t.start : null);
        if (!time) return null;
        return {
            id: id, title: title, color: color, notify: notify,
            date: t.date, time: time,
            days: [], start: "", end: "", isBreak: false, leadMinutes: 0
        };
    }

    // Recurring task: a weekday range block.
    if (!isValidTime(t.start) || !isValidTime(t.end)) return null;
    if (toMinutes(t.end) <= toMinutes(t.start)) return null;
    var days = [];
    if (Array.isArray(t.days)) {
        for (var i = 0; i < t.days.length; i++) {
            var d = parseInt(t.days[i], 10);
            if (d >= 1 && d <= 7 && days.indexOf(d) === -1) days.push(d);
        }
    }
    days.sort();
    return {
        id: id,
        title: title,
        color: color,
        days: days,
        start: t.start,
        end: t.end,
        isBreak: !!t.isBreak,
        // notify when the block starts; lead = minutes BEFORE start to fire it
        // (e.g. gym 18:00 with leadMinutes 15 → reminder at 17:45).
        notify: notify,
        leadMinutes: (isFiniteNum(t.leadMinutes) && t.leadMinutes >= 0)
            ? Math.floor(t.leadMinutes) : 0,
        date: "", time: ""
    };
}

// Is this a one-time (dated) reminder rather than a recurring block?
function isOneTime(task) {
    return !!(task && task.date);
}

// The minute-of-day at which a task's start reminder should fire.
function reminderMinute(task) {
    return toMinutes(task.start) - (task.leadMinutes > 0 ? task.leadMinutes : 0);
}

// Effective end of a task as an EXCLUSIVE minute boundary. Times are treated as
// "start at the beginning of the minute, end at the end of the minute", so an
// end of 23:59 means the block runs through 23:59:59 — i.e. to end of day (24:00).
// This is what stops the last minute of a midnight-spanning block reading as free.
function effectiveEndMinute(task) {
    var e = toMinutes(task.end);
    return e === 23 * 60 + 59 ? 24 * 60 : e;
}

// ---- small helpers -------------------------------------------------------

function isFiniteNum(n) { return typeof n === "number" && isFinite(n); }

function isValidTime(s) {
    if (typeof s !== "string") return false;
    var m = /^([0-9]{1,2}):([0-9]{2})$/.exec(s);
    if (!m) return false;
    var h = parseInt(m[1], 10), mi = parseInt(m[2], 10);
    return h >= 0 && h <= 23 && mi >= 0 && mi <= 59;
}

function isValidColor(c) {
    return typeof c === "string" && /^#[0-9a-fA-F]{6}$/.test(c);
}

// "YYYY-MM-DD" (a real calendar date). Used only by one-time tasks.
function isValidDate(s) {
    if (typeof s !== "string") return false;
    var m = /^([0-9]{4})-([0-9]{2})-([0-9]{2})$/.exec(s);
    if (!m) return false;
    var mo = parseInt(m[2], 10), da = parseInt(m[3], 10);
    return mo >= 1 && mo <= 12 && da >= 1 && da <= 31;
}

function toMinutes(hhmm) {
    var m = /^([0-9]{1,2}):([0-9]{2})$/.exec(hhmm);
    if (!m) return 0;
    return parseInt(m[1], 10) * 60 + parseInt(m[2], 10);
}

function pad2(n) { return (n < 10 ? "0" : "") + n; }

// Local calendar date of a JS Date as "YYYY-MM-DD".
function formatDate(date) {
    return date.getFullYear() + "-" + pad2(date.getMonth() + 1) + "-" + pad2(date.getDate());
}

function minutesToHHMM(min) {
    min = ((min % 1440) + 1440) % 1440;
    return pad2(Math.floor(min / 60)) + ":" + pad2(min % 60);
}

// ISO weekday 1..7 for a JS Date (getDay(): 0=Sun..6=Sat).
function isoDay(date) {
    var d = date.getDay();
    return d === 0 ? 7 : d;
}

function minutesOfDay(date) {
    return date.getHours() * 60 + date.getMinutes();
}

// Unique-across-sessions id. The timestamp differs between runs; the counter
// disambiguates ids minted within the same millisecond. Both Date.now() and
// the counter are available in QML and node (the only runtimes this file uses).
var _idCounter = 0;
function genId() {
    _idCounter += 1;
    var t = (typeof Date !== "undefined" && Date.now) ? Date.now() : 0;
    return "t" + t.toString(36) + "_" + _idCounter;
}

// ---- core queries --------------------------------------------------------

// All tasks scheduled on the given ISO weekday, sorted by start time then end.
function tasksForDay(schedule, iso) {
    var out = [];
    var tasks = (schedule && schedule.tasks) || [];
    for (var i = 0; i < tasks.length; i++) {
        var days = tasks[i].days;
        if (days && days.indexOf(iso) !== -1) out.push(tasks[i]);
    }
    out.sort(function (a, b) {
        var d = toMinutes(a.start) - toMinutes(b.start);
        return d !== 0 ? d : toMinutes(a.end) - toMinutes(b.end);
    });
    return out;
}

// Convenience: today's RECURRING tasks for a Date (one-time tasks excluded —
// they have no weekday and never appear in the timeline/current-task logic).
function tasksForDate(schedule, date) {
    return tasksForDay(schedule, isoDay(date));
}

// One-time reminders falling on the given calendar Date, sorted by time.
function oneTimeTasksOnDate(schedule, date) {
    var key = formatDate(date);
    var out = [];
    var tasks = (schedule && schedule.tasks) || [];
    for (var i = 0; i < tasks.length; i++) {
        if (tasks[i].date === key) out.push(tasks[i]);
    }
    out.sort(function (a, b) { return toMinutes(a.time) - toMinutes(b.time); });
    return out;
}

// All one-time reminders, sorted by date then time (for the planner list).
function oneTimeTasks(schedule) {
    var out = [];
    var tasks = (schedule && schedule.tasks) || [];
    for (var i = 0; i < tasks.length; i++) {
        if (isOneTime(tasks[i])) out.push(tasks[i]);
    }
    out.sort(function (a, b) {
        if (a.date !== b.date) return a.date < b.date ? -1 : 1;
        return toMinutes(a.time) - toMinutes(b.time);
    });
    return out;
}

// The task active right now (start <= now < end). Strictly-sequential model:
// if blocks overlap, the earliest-starting active block wins (first in sorted order).
function currentTask(schedule, date) {
    var now = minutesOfDay(date);
    var today = tasksForDate(schedule, date);
    for (var i = 0; i < today.length; i++) {
        if (toMinutes(today[i].start) <= now && now < effectiveEndMinute(today[i])) {
            return today[i];
        }
    }
    return null;
}

// The next task starting strictly after `now` today (null if none left today).
function nextTask(schedule, date) {
    var now = minutesOfDay(date);
    var today = tasksForDate(schedule, date);
    for (var i = 0; i < today.length; i++) {
        if (toMinutes(today[i].start) > now) return today[i];
    }
    return null;
}

// Fraction 0..1 of the way through a task at the given time (0 if not started,
// 1 if past). Safe for any task/time pair.
function progress(task, date) {
    if (!task) return 0;
    var now = minutesOfDay(date);
    var s = toMinutes(task.start), e = toMinutes(task.end);
    if (e <= s) return 0;
    if (now <= s) return 0;
    if (now >= e) return 1;
    return (now - s) / (e - s);
}

// Minutes remaining in the current task (null if no current task).
function remainingMinutes(task, date) {
    if (!task) return null;
    return Math.max(0, effectiveEndMinute(task) - minutesOfDay(date));
}

// The next scheduled *break* block starting at or after `now` today.
// Used to fire "take a break" popups for breaks the user explicitly planned.
function nextBreakBlock(schedule, date) {
    var now = minutesOfDay(date);
    var today = tasksForDate(schedule, date);
    for (var i = 0; i < today.length; i++) {
        if (today[i].isBreak && toMinutes(today[i].start) >= now) return today[i];
    }
    return null;
}

// Build a timeline for a weekday: the sorted tasks plus synthetic "free" gaps
// between them, within [dayStart, dayEnd] (minutes). Each entry:
//   { kind: "task"|"free", task?, start:"HH:MM", end:"HH:MM", startMin, endMin }
function timeline(schedule, iso, dayStartMin, dayEndMin) {
    if (dayStartMin === undefined) dayStartMin = 6 * 60;   // 06:00
    if (dayEndMin === undefined) dayEndMin = 23 * 60;      // 23:00
    var tasks = tasksForDay(schedule, iso);
    var entries = [];
    var cursor = dayStartMin;
    // expand window to include any task outside the default bounds
    for (var i = 0; i < tasks.length; i++) {
        if (toMinutes(tasks[i].start) < cursor) cursor = toMinutes(tasks[i].start);
        if (effectiveEndMinute(tasks[i]) > dayEndMin) dayEndMin = effectiveEndMinute(tasks[i]);
    }
    for (var j = 0; j < tasks.length; j++) {
        var s = toMinutes(tasks[j].start);
        var ee = effectiveEndMinute(tasks[j]); // 23:59 → end of day, so no free sliver
        if (s > cursor) {
            entries.push(makeEntry("free", null, cursor, s));
        }
        // task block keeps its real start/end labels but occupies through ee
        entries.push({
            kind: "task",
            task: tasks[j],
            start: tasks[j].start,
            end: tasks[j].end,
            startMin: s,
            endMin: ee
        });
        if (ee > cursor) cursor = ee;
    }
    if (cursor < dayEndMin) {
        entries.push(makeEntry("free", null, cursor, dayEndMin));
    }
    return entries;
}

function makeEntry(kind, task, startMin, endMin) {
    return {
        kind: kind,
        task: task,
        start: minutesToHHMM(startMin),
        end: minutesToHHMM(endMin),
        startMin: startMin,
        endMin: endMin
    };
}

// Timeline for a specific calendar Date: the recurring weekday timeline PLUS
// any one-time reminders on that date, overlaid as zero-duration "reminder"
// point markers, sorted in by time. Used by the widget's click-through popup.
function timelineForDate(schedule, date, dayStartMin, dayEndMin) {
    var entries = timeline(schedule, isoDay(date), dayStartMin, dayEndMin);
    var reminders = oneTimeTasksOnDate(schedule, date);
    for (var i = 0; i < reminders.length; i++) {
        var m = toMinutes(reminders[i].time);
        entries.push({
            kind: "reminder",
            task: reminders[i],
            start: reminders[i].time,
            end: reminders[i].time,
            startMin: m,
            endMin: m
        });
    }
    entries.sort(function (a, b) {
        if (a.startMin !== b.startMin) return a.startMin - b.startMin;
        // at the same minute, show the block/free before the point reminder
        var rank = function (e) { return e.kind === "reminder" ? 1 : 0; };
        return rank(a) - rank(b);
    });
    return entries;
}

// Overlap conflicts (for the planner to warn about). Returns array of pairs
// { day, a, b } where two tasks scheduled on the same weekday overlap in time.
function conflicts(schedule) {
    var out = [];
    for (var day = 1; day <= 7; day++) {
        var t = tasksForDay(schedule, day);
        for (var i = 0; i < t.length; i++) {
            for (var k = i + 1; k < t.length; k++) {
                var aS = toMinutes(t[i].start), aE = toMinutes(t[i].end);
                var bS = toMinutes(t[k].start), bE = toMinutes(t[k].end);
                if (aS < bE && bS < aE) {
                    out.push({ day: day, a: t[i], b: t[k] });
                }
            }
        }
    }
    return out;
}

// Short human label for a task's time span, e.g. "09:00–11:00".
function rangeLabel(task) {
    if (!task) return "";
    return task.start + "–" + task.end;
}

var DAY_NAMES = ["", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
function dayName(iso) { return DAY_NAMES[iso] || ""; }

// ---- exports -------------------------------------------------------------
// Guarded so QML (where `module` is undefined) simply skips this block.
var API = {
    emptySchedule: emptySchedule,
    normalize: normalize,
    normalizeTask: normalizeTask,
    isValidTime: isValidTime,
    isValidColor: isValidColor,
    isValidDate: isValidDate,
    formatDate: formatDate,
    isOneTime: isOneTime,
    toMinutes: toMinutes,
    minutesToHHMM: minutesToHHMM,
    isoDay: isoDay,
    minutesOfDay: minutesOfDay,
    genId: genId,
    tasksForDay: tasksForDay,
    tasksForDate: tasksForDate,
    oneTimeTasksOnDate: oneTimeTasksOnDate,
    oneTimeTasks: oneTimeTasks,
    currentTask: currentTask,
    nextTask: nextTask,
    progress: progress,
    remainingMinutes: remainingMinutes,
    nextBreakBlock: nextBreakBlock,
    reminderMinute: reminderMinute,
    effectiveEndMinute: effectiveEndMinute,
    timeline: timeline,
    timelineForDate: timelineForDate,
    conflicts: conflicts,
    rangeLabel: rangeLabel,
    dayName: dayName
};

if (typeof module !== "undefined" && module.exports) {
    module.exports = API;
}
