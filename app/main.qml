/*
 * My Schedule — standalone planner (QML-only Kirigami app).
 * Authors the shared schedule.json that the panel widget reads.
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "schedule.js" as Sched

Kirigami.ApplicationWindow {
    id: app

    // i18n()/i18np() shim — this app runs via the bare `qml` runtime, which does
    // not inject KDE's KLocalizedContext. English-only personal tool, so these
    // light passthroughs honour %1/%2 placeholders and plural selection.
    function i18n() {
        var s = arguments[0];
        for (var i = 1; i < arguments.length; i++)
            s = s.split("%" + i).join(arguments[i]);
        return s;
    }
    function i18np() {
        var n = arguments[2];
        var s = (n === 1) ? arguments[0] : arguments[1];
        return s.split("%1").join(n);
    }

    title: i18n("Schedule Planner")
    width: Kirigami.Units.gridUnit * 44
    height: Kirigami.Units.gridUnit * 34
    minimumWidth: Kirigami.Units.gridUnit * 30
    minimumHeight: Kirigami.Units.gridUnit * 24

    // ---- shared state ----------------------------------------------------
    property var schedule: Sched.emptySchedule()
    property var conflicts: []

    Storage {
        id: storage
        onLoaded: function (s) {
            app.schedule = s;
            app.refreshDerived();
        }
        onSaveDone: function (ok) {
            if (!ok) showPassiveError(i18n("Could not save the schedule."));
        }
        onParseError: function (msg) { showPassiveError(msg); }
    }

    function refreshDerived() {
        conflicts = Sched.conflicts(schedule);
    }

    function commit() {
        // force bindings to re-evaluate, then persist
        schedule = JSON.parse(JSON.stringify(schedule));
        refreshDerived();
        storage.save(schedule);
    }

    function addOrUpdateTask(task) {
        var tasks = schedule.tasks.slice();
        var idx = -1;
        for (var i = 0; i < tasks.length; i++) {
            if (tasks[i].id === task.id) { idx = i; break; }
        }
        if (idx >= 0) tasks[idx] = task; else tasks.push(task);
        schedule.tasks = tasks;
        commit();
    }

    function removeTask(id) {
        schedule.tasks = schedule.tasks.filter(function (t) { return t.id !== id; });
        commit();
    }

    function showPassiveError(msg) {
        showPassiveNotification(msg, "long");
    }

    // ---- editor dialog ---------------------------------------------------
    TaskEditor {
        id: editor
        onTaskAccepted: function (task) { app.addOrUpdateTask(task); }
    }

    SettingsDialog {
        id: settingsDialog
        onSettingsAccepted: function (settings) {
            app.schedule.settings = settings;
            app.commit();
        }
    }

    globalDrawer: Kirigami.GlobalDrawer {
        isMenu: true
        actions: [
            Kirigami.Action {
                text: i18n("Add task")
                icon.name: "list-add"
                onTriggered: editor.openFor(null)
            },
            Kirigami.Action {
                text: i18n("Break settings")
                icon.name: "configure"
                onTriggered: settingsDialog.openWith(app.schedule.settings)
            }
        ]
    }

    pageStack.initialPage: PlannerPage {
        schedule: app.schedule
        conflicts: app.conflicts
        onAddRequested: editor.openFor(null)
        onAddInSlotRequested: function (startMin, endMin, iso) {
            editor.openNew({ startMin: startMin, endMin: endMin, iso: iso });
        }
        onEditRequested: function (task) { editor.openFor(task); }
        onDeleteRequested: function (id) { app.removeTask(id); }
        onSettingsRequested: settingsDialog.openWith(app.schedule.settings)
    }

    Component.onCompleted: storage.load()
}
