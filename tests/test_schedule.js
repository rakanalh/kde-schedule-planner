// Node test suite for the shared scheduling brain.
// Run: node tests/test_schedule.js
const S = require("../shared/schedule.js");

let pass = 0, fail = 0;
function eq(actual, expected, msg) {
    const a = JSON.stringify(actual), e = JSON.stringify(expected);
    if (a === e) { pass++; }
    else { fail++; console.error(`FAIL: ${msg}\n   expected ${e}\n   got      ${a}`); }
}
function ok(cond, msg) { if (cond) pass++; else { fail++; console.error(`FAIL: ${msg}`); } }

// 2026-06-22 is a Monday (ISO day 1); 2026-06-27 is a Saturday (ISO 6).
const mon = (h, m) => new Date(2026, 5, 22, h, m, 0);
const sat = (h, m) => new Date(2026, 5, 27, h, m, 0);

eq(S.isoDay(mon(0, 0)), 1, "Monday is ISO 1");
eq(S.isoDay(sat(0, 0)), 6, "Saturday is ISO 6");
eq(S.toMinutes("09:30"), 570, "toMinutes 09:30");
eq(S.minutesToHHMM(570), "09:30", "minutesToHHMM 570");
eq(S.minutesOfDay(mon(9, 30)), 570, "minutesOfDay 9:30");

ok(S.isValidTime("23:59") && !S.isValidTime("24:00") && !S.isValidTime("9:5x"), "isValidTime");
ok(S.isValidColor("#3daee9") && !S.isValidColor("blue"), "isValidColor");

const sched = S.normalize({
    settings: { intervalBreaksEnabled: true, intervalBreakMinutes: 60 },
    tasks: [
        { id: "a", title: "Deep Work", color: "#3daee9", days: [1, 2, 3, 4, 5], start: "09:00", end: "11:00" },
        { id: "b", title: "Lunch", color: "#27ae60", days: [1, 2, 3, 4, 5], start: "12:30", end: "13:00", isBreak: true },
        { id: "c", title: "Email", color: "#f67400", days: [1], start: "11:00", end: "11:30" },
        { id: "bad", title: "Bad", days: [1], start: "10:00", end: "09:00" }, // end<=start -> dropped
        { id: "wknd", title: "Errands", days: [6], start: "10:00", end: "12:00" }
    ]
});

eq(sched.tasks.length, 4, "invalid task dropped, 4 remain");
eq(sched.settings.intervalBreakMinutes, 60, "settings carried");
eq(sched.settings.intervalBreakDurationMinutes, 5, "settings default filled");

// tasksForDay Monday -> a, c, b sorted by start: 09:00, 11:00, 12:30
const monTasks = S.tasksForDay(sched, 1);
eq(monTasks.map(t => t.id), ["a", "c", "b"], "Monday tasks sorted by start");
eq(S.tasksForDay(sched, 6).map(t => t.id), ["wknd"], "Saturday only errands");
eq(S.tasksForDay(sched, 7).map(t => t.id), [], "Sunday empty");

// currentTask
eq(S.currentTask(sched, mon(9, 30)).id, "a", "9:30 -> Deep Work");
eq(S.currentTask(sched, mon(11, 15)).id, "c", "11:15 -> Email");
eq(S.currentTask(sched, mon(12, 45)).id, "b", "12:45 -> Lunch (break)");
ok(S.currentTask(sched, mon(8, 0)) === null, "8:00 -> nothing");
ok(S.currentTask(sched, mon(11, 0)).id === "c", "boundary 11:00 belongs to Email (start inclusive)");
ok(S.currentTask(sched, mon(11, 30)) === null, "11:30 -> nothing (end exclusive)");

// nextTask
eq(S.nextTask(sched, mon(8, 0)).id, "a", "before day -> next is Deep Work");
eq(S.nextTask(sched, mon(9, 30)).id, "c", "during Deep Work -> next is Email");
ok(S.nextTask(sched, mon(13, 0)) === null, "after last -> no next");

// progress + remaining
eq(S.progress(monTasks[0], mon(10, 0)), 0.5, "halfway through Deep Work");
eq(S.progress(monTasks[0], mon(8, 0)), 0, "before start -> 0");
eq(S.progress(monTasks[0], mon(12, 0)), 1, "after end -> 1");
eq(S.remainingMinutes(S.currentTask(sched, mon(9, 30)), mon(9, 30)), 90, "90 min left at 9:30");

// nextBreakBlock
eq(S.nextBreakBlock(sched, mon(9, 0)).id, "b", "next break is Lunch");
ok(S.nextBreakBlock(sched, mon(13, 0)) === null, "no break after lunch");

// timeline with free gaps (Monday)
const tl = S.timeline(sched, 1);
const kinds = tl.map(e => e.kind + ":" + (e.task ? e.task.id : e.start + "-" + e.end));
// expect: free 06:00-09:00, task a, task c (11:00-11:30 adjacent), free 11:30-12:30, task b, free 13:00-23:00
eq(kinds, [
    "free:06:00-09:00", "task:a", "task:c", "free:11:30-12:30", "task:b", "free:13:00-23:00"
], "timeline gaps + tasks");

// conflicts: add an overlapping task on Monday
const conf = S.normalize({
    tasks: [
        { title: "X", days: [1], start: "09:00", end: "10:00" },
        { title: "Y", days: [1], start: "09:30", end: "10:30" },
        { title: "Z", days: [2], start: "09:00", end: "10:00" }
    ]
});
eq(S.conflicts(conf).length, 1, "one overlap on Monday");
eq(S.conflicts(sched).length, 0, "sample schedule has no conflicts");

eq(S.dayName(1), "Mon", "dayName 1");
eq(S.rangeLabel(monTasks[0]), "09:00–11:00", "rangeLabel");

// notify / leadMinutes defaults + reminderMinute
const notif = S.normalize({ tasks: [
    { title: "Gym", days: [1], start: "18:00", end: "19:00", leadMinutes: 15 },
    { title: "Plain", days: [1], start: "08:00", end: "09:00" },
    { title: "Muted", days: [1], start: "07:00", end: "08:00", notify: false, leadMinutes: -5 }
]});
eq(notif.tasks[0].notify, true, "notify defaults true");
eq(notif.tasks[0].leadMinutes, 15, "leadMinutes carried");
eq(notif.tasks[1].leadMinutes, 0, "leadMinutes defaults 0");
eq(notif.tasks[2].notify, false, "notify=false honored");
eq(notif.tasks[2].leadMinutes, 0, "negative leadMinutes clamped to 0");
// reminderMinute: Gym 18:00 - 15 = 17:45 = 1065
eq(S.reminderMinute(notif.tasks[0]), 17 * 60 + 45, "reminderMinute applies lead");
eq(S.reminderMinute(notif.tasks[1]), 8 * 60, "reminderMinute = start when no lead");

// genId: ids minted within a session must be unique (regression: a deterministic
// counter that reset per process overwrote existing tasks on the next launch).
const ids = {};
for (let i = 0; i < 50; i++) { const id = S.genId(); ok(!ids[id], "genId unique #" + i); ids[id] = 1; }
// normalize must mint ids for id-less tasks and keep them distinct
const minted = S.normalize({ tasks: [
    { title: "A", days: [1], start: "08:00", end: "09:00" },
    { title: "B", days: [1], start: "09:00", end: "10:00" }
]});
ok(minted.tasks[0].id !== minted.tasks[1].id && minted.tasks[0].id && minted.tasks[1].id,
   "normalize mints distinct ids");

// 23:59 end means "through end of day" — the last minute must NOT read as free,
// and the whole-day timeline must not leave a 23:59–00:00 sliver.
const late = S.normalize({ tasks: [
    { id: "evening", title: "Evening", days: [1], start: "21:45", end: "23:59" }
]});
eq(S.effectiveEndMinute(late.tasks[0]), 24 * 60, "23:59 end → 24:00 effective");
eq((S.currentTask(late, mon(23, 59)) || {}).id, "evening", "23:59 is inside the block, not free");
eq((S.currentTask(late, mon(23, 30)) || {}).id, "evening", "23:30 inside block");
eq(S.remainingMinutes(late.tasks[0], mon(23, 59)), 1, "1 min left at 23:59");
const lateTl = S.timeline(late, 1, 0, 24 * 60);
const lastLate = lateTl[lateTl.length - 1];
eq(lastLate.kind, "task", "no trailing free sliver after a 23:59 block");
eq(lastLate.end, "23:59", "block still displays its real 23:59 end label");
eq(lastLate.endMin, 24 * 60, "block occupies through end of day");
// a normal mid-day end is unaffected (still exclusive, no 1-min weirdness)
eq(S.effectiveEndMinute(S.normalizeTask({ days: [1], start: "09:00", end: "11:00" })),
   11 * 60, "non-23:59 end unchanged");

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
