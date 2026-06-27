/*
 * A vertical timeline of a single weekday: planned blocks plus free gaps.
 * Read-only preview used in the planner.
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "schedule.js" as Sched

ColumnLayout {
    id: tl

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
    property int iso: 1
    property bool highlightNow: false

    // emitted when a free slot is clicked, so the planner can pre-fill Add task
    signal freeSlotClicked(int startMin, int endMin)

    // span the whole day (midnight to midnight) so nothing is cut off
    readonly property var entries: schedule ? Sched.timeline(schedule, iso, 0, 24 * 60) : []
    readonly property int nowMin: Sched.minutesOfDay(new Date())

    spacing: Kirigami.Units.smallSpacing

    Repeater {
        model: tl.entries
        delegate: MouseArea {
            id: row
            required property var modelData
            Layout.fillWidth: true
            implicitHeight: inner.implicitHeight + Kirigami.Units.smallSpacing

            readonly property bool isTask: modelData.kind === "task"
            readonly property bool isFree: !isTask
            readonly property var task: modelData.task
            readonly property bool isCurrent: tl.highlightNow && isTask
                && modelData.startMin <= tl.nowMin && tl.nowMin < modelData.endMin
            // a task whose end time has already passed today
            readonly property bool isPast: tl.highlightNow && isTask
                && tl.nowMin >= modelData.endMin

            hoverEnabled: isFree
            cursorShape: isFree ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (isFree) tl.freeSlotClicked(modelData.startMin, modelData.endMin)

            // hover highlight to show a free slot is clickable
            Rectangle {
                anchors.fill: parent
                visible: row.isFree && row.containsMouse
                color: Kirigami.Theme.highlightColor
                opacity: 0.12
                radius: Kirigami.Units.smallSpacing
            }

            RowLayout {
                id: inner
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Kirigami.Units.largeSpacing
                opacity: row.isPast ? 0.45 : 1.0

                QQC2.Label {
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 3
                    Layout.alignment: Qt.AlignTop
                    text: row.modelData.start
                    font.family: "monospace"
                    font.bold: row.isCurrent
                }

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: Kirigami.Units.smallSpacing
                    Layout.minimumHeight: Kirigami.Units.gridUnit * 1.4
                    Layout.fillHeight: true
                    radius: width / 2
                    color: row.isTask ? row.task.color : Kirigami.Theme.disabledTextColor
                    opacity: row.isTask ? 1 : 0.35
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    Kirigami.Icon {
                        visible: row.isTask && row.task.isBreak
                        source: "media-playback-pause"
                        implicitWidth: Kirigami.Units.iconSizes.small
                        implicitHeight: Kirigami.Units.iconSizes.small
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: row.isTask ? row.task.title : i18n("Free")
                        opacity: row.isTask ? 1 : 0.45
                        font.bold: row.isCurrent
                        font.strikeout: row.isPast
                    }
                    QQC2.Label {
                        visible: row.isFree && row.containsMouse
                        text: i18n("+ Add")
                        color: Kirigami.Theme.highlightColor
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                    }
                    QQC2.Label {
                        visible: row.isCurrent
                        text: i18n("now")
                        color: Kirigami.Theme.highlightColor
                        font: Kirigami.Theme.smallFont
                    }
                    QQC2.Label {
                        text: row.modelData.end
                        font.family: "monospace"
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        opacity: 0.5
                    }
                }
            }
        }
    }

    QQC2.Label {
        visible: tl.entries.length === 0
        text: i18n("Nothing scheduled on %1.", Sched.dayName(tl.iso))
        opacity: 0.6
    }
}
