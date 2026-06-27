/*
 * The main planner page: a weekday preview timeline on top, the full list of
 * task blocks below, with edit/delete and a conflict banner.
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "schedule.js" as Sched

Kirigami.ScrollablePage {
    id: page

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

    property var schedule
    property var conflicts: []

    signal addRequested
    signal addInSlotRequested(int startMin, int endMin, int iso)
    signal editRequested(var task)
    signal deleteRequested(string id)
    signal settingsRequested

    title: i18n("My Day Plan")

    // default preview day = today
    property int previewIso: Sched.isoDay(new Date())

    readonly property var allTasks: {
        // flat list ordered chronologically by time of day (start, then end)
        var t = (schedule && schedule.tasks) ? schedule.tasks.slice() : [];
        t.sort(function (a, b) {
            var d = Sched.toMinutes(a.start) - Sched.toMinutes(b.start);
            return d !== 0 ? d : Sched.toMinutes(a.end) - Sched.toMinutes(b.end);
        });
        return t;
    }

    actions: [
        Kirigami.Action {
            text: i18n("Add task")
            icon.name: "list-add"
            onTriggered: page.addRequested()
        },
        Kirigami.Action {
            text: i18n("Break settings")
            icon.name: "configure"
            onTriggered: page.settingsRequested()
        }
    ]

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            type: Kirigami.MessageType.Warning
            visible: page.conflicts.length > 0
            text: i18np("%1 overlapping block on one of your days.", "%1 overlapping blocks across your days.", page.conflicts.length)
        }

        // ---- weekday selector ----
        Kirigami.Heading {
            level: 3
            text: i18n("Preview")
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            Repeater {
                model: 7
                delegate: QQC2.Button {
                    required property int index
                    readonly property int iso: index + 1
                    text: Sched.dayName(iso)
                    checkable: true
                    checked: page.previewIso === iso
                    onClicked: page.previewIso = iso
                }
            }
            Item {
                Layout.fillWidth: true
            }
        }

        TimelinePreview {
            Layout.fillWidth: true
            schedule: page.schedule
            iso: page.previewIso
            highlightNow: page.previewIso === Sched.isoDay(new Date())
            onFreeSlotClicked: function (startMin, endMin) {
                page.addInSlotRequested(startMin, endMin, page.previewIso);
            }
        }

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        // ---- all task blocks ----
        Kirigami.Heading {
            level: 3
            text: i18n("All blocks")
        }

        Kirigami.PlaceholderMessage {
            Layout.fillWidth: true
            visible: page.allTasks.length === 0
            icon.name: "view-calendar-day"
            text: i18n("No blocks yet")
            explanation: i18n("Add your first time block to start planning your day.")
            helpfulAction: Kirigami.Action {
                text: i18n("Add task")
                icon.name: "list-add"
                onTriggered: page.addRequested()
            }
        }

        Repeater {
            model: page.allTasks
            delegate: Kirigami.AbstractCard {
                required property var modelData
                Layout.fillWidth: true

                contentItem: RowLayout {
                    spacing: Kirigami.Units.largeSpacing

                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: Kirigami.Units.gridUnit * 0.6
                        implicitHeight: Kirigami.Units.gridUnit * 2.2
                        radius: width / 2
                        color: modelData.color
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing
                            Kirigami.Icon {
                                visible: modelData.isBreak
                                source: "media-playback-pause"
                                implicitWidth: Kirigami.Units.iconSizes.small
                                implicitHeight: Kirigami.Units.iconSizes.small
                            }
                            Kirigami.Heading {
                                level: 4
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: modelData.title
                            }
                        }
                        QQC2.Label {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            opacity: 0.7
                            text: Sched.rangeLabel(modelData) + "  ·  " + daysLabel(modelData.days)
                        }
                    }

                    // pin the action buttons to the right edge of every card
                    RowLayout {
                        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.ToolButton {
                            display: QQC2.AbstractButton.IconOnly
                            icon.name: "document-edit"
                            QQC2.ToolTip.text: i18n("Edit")
                            QQC2.ToolTip.visible: hovered
                            onClicked: page.editRequested(modelData)
                        }
                        QQC2.ToolButton {
                            display: QQC2.AbstractButton.IconOnly
                            icon.name: "edit-delete"
                            QQC2.ToolTip.text: i18n("Delete")
                            QQC2.ToolTip.visible: hovered
                            onClicked: page.deleteRequested(modelData.id)
                        }
                    }
                }
            }
        }
    }

    function daysLabel(days) {
        if (!days || days.length === 0)
            return i18n("no days");
        if (days.length === 7)
            return i18n("Every day");
        var wd = [1, 2, 3, 4, 5];
        if (days.length === 5 && wd.every(function (d) {
            return days.indexOf(d) !== -1;
        }))
            return i18n("Weekdays");
        return days.map(function (d) {
            return Sched.dayName(d);
        }).join(", ");
    }
}
