/*
 * Full (popup) view: a vertical timeline of today — every planned block plus
 * the free gaps between them, the current block highlighted with a "now" line.
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import "../code/schedule.js" as Sched

PlasmaComponents.Page {
    id: full

    property var plasmoidItem

    Layout.minimumWidth: Kirigami.Units.gridUnit * 18
    Layout.minimumHeight: Kirigami.Units.gridUnit * 22
    Layout.preferredWidth: Kirigami.Units.gridUnit * 20
    Layout.preferredHeight: Kirigami.Units.gridUnit * 26

    // which day is shown: 0 = today, -1 = yesterday, +1 = tomorrow, …
    property int dayOffset: 0
    readonly property bool isToday: dayOffset === 0
    readonly property date selectedDate: {
        var base = plasmoidItem ? plasmoidItem.now : new Date();
        return new Date(base.getFullYear(), base.getMonth(), base.getDate() + dayOffset);
    }
    readonly property int selectedIso: Sched.isoDay(selectedDate)

    readonly property var entries: {
        if (!plasmoidItem) {
            return [];
        }
        var cfg = plasmoidItem.Plasmoid.configuration;
        return Sched.timeline(plasmoidItem.schedule, selectedIso,
                              cfg.timelineStartHour * 60, cfg.timelineEndHour * 60);
    }
    // "now" highlighting only makes sense when looking at today
    readonly property var currentTask: (plasmoidItem && isToday) ? plasmoidItem.currentTask : null
    readonly property int nowMin: plasmoidItem ? Sched.minutesOfDay(plasmoidItem.now) : 0

    function relativeLabel(offset) {
        if (offset === 0) return i18n("Today");
        if (offset === 1) return i18n("Tomorrow");
        if (offset === -1) return i18n("Yesterday");
        return Qt.formatDate(selectedDate, "dddd");
    }

    header: PlasmaComponents.ToolBar {
        contentItem: RowLayout {
            PlasmaComponents.ToolButton {
                icon.name: "go-previous"
                onClicked: full.dayOffset -= 1
                QQC2.ToolTip.text: i18n("Previous day")
                QQC2.ToolTip.visible: hovered
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Kirigami.Heading {
                    level: 4
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: full.relativeLabel(full.dayOffset)
                }
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    opacity: 0.7
                    font: Kirigami.Theme.smallFont
                    text: Qt.formatDate(full.selectedDate, "ddd, d MMM")
                }
            }
            PlasmaComponents.ToolButton {
                icon.name: "go-next"
                onClicked: full.dayOffset += 1
                QQC2.ToolTip.text: i18n("Next day")
                QQC2.ToolTip.visible: hovered
            }
            PlasmaComponents.ToolButton {
                icon.name: "go-jump-today"
                visible: !full.isToday
                onClicked: full.dayOffset = 0
                QQC2.ToolTip.text: i18n("Back to today")
                QQC2.ToolTip.visible: hovered
            }
            PlasmaComponents.ToolButton {
                icon.name: "view-calendar-day"
                onClicked: plasmoidItem.launchPlanner()
                QQC2.ToolTip.text: i18n("Plan my day…")
                QQC2.ToolTip.visible: hovered
            }
        }
    }

    ListView {
        id: timeline
        anchors.fill: parent
        model: full.entries
        spacing: 0
        clip: true
        reuseItems: true
        QQC2.ScrollBar.vertical: QQC2.ScrollBar {}

            delegate: Item {
                id: entryDelegate
                required property var modelData
                width: ListView.view.width

                readonly property bool isTask: modelData.kind === "task"
                readonly property var task: modelData.task
                readonly property bool isBreak: isTask && task.isBreak
                readonly property bool isCurrent: isTask && full.currentTask
                    && task.id === full.currentTask.id
                // a task whose end time has already passed today (only when viewing today)
                readonly property bool isPast: full.isToday && isTask
                    && full.nowMin >= modelData.endMin

                implicitHeight: rowLayout.implicitHeight + Kirigami.Units.smallSpacing * 2

                // subtle highlight band for the current block
                Rectangle {
                    anchors.fill: parent
                    visible: entryDelegate.isCurrent
                    color: Kirigami.Theme.highlightColor
                    opacity: 0.12
                    radius: Kirigami.Units.smallSpacing
                }

                RowLayout {
                    id: rowLayout
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Kirigami.Units.smallSpacing
                    anchors.rightMargin: Kirigami.Units.smallSpacing
                    spacing: Kirigami.Units.largeSpacing
                    // done blocks recede so the current/upcoming ones stand out
                    opacity: entryDelegate.isPast ? 0.45 : 1.0

                    // time column
                    ColumnLayout {
                        Layout.alignment: Qt.AlignTop
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 3
                        spacing: 0
                        QQC2.Label {
                            text: entryDelegate.modelData.start
                            font.family: "monospace"
                            font.bold: entryDelegate.isCurrent
                        }
                        QQC2.Label {
                            text: entryDelegate.modelData.end
                            font.family: "monospace"
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                            opacity: 0.55
                        }
                    }

                    // colored rail
                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.fillHeight: true
                        Layout.minimumHeight: Kirigami.Units.gridUnit * 1.6
                        implicitWidth: Kirigami.Units.smallSpacing
                        radius: width / 2
                        color: entryDelegate.isTask
                            ? entryDelegate.task.color
                            : Kirigami.Theme.disabledTextColor
                        opacity: entryDelegate.isTask ? 1 : 0.4
                    }

                    // title + meta
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        RowLayout {
                            spacing: Kirigami.Units.smallSpacing
                            Kirigami.Icon {
                                visible: entryDelegate.isBreak
                                source: "media-playback-pause"
                                implicitWidth: Kirigami.Units.iconSizes.small
                                implicitHeight: Kirigami.Units.iconSizes.small
                            }
                            QQC2.Label {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: entryDelegate.isTask ? entryDelegate.task.title : i18n("Free")
                                font.bold: entryDelegate.isCurrent
                                font.strikeout: entryDelegate.isPast
                                opacity: entryDelegate.isTask ? 1 : 0.5
                            }
                            PlasmaComponents.Label {
                                visible: entryDelegate.isCurrent
                                text: i18n("now")
                                font: Kirigami.Theme.smallFont
                                color: Kirigami.Theme.highlightColor
                            }
                        }
                        // progress bar for the current task
                        QQC2.ProgressBar {
                            visible: entryDelegate.isCurrent
                            Layout.fillWidth: true
                            Layout.topMargin: Kirigami.Units.smallSpacing
                            from: 0; to: 1
                            value: plasmoidItem ? plasmoidItem.currentProgress : 0
                        }
                    }
                }
            }

            // empty state
            QQC2.Label {
                anchors.centerIn: parent
                visible: timeline.count === 0
                text: i18n("Nothing planned.\nClick “Plan my day…” to add blocks.")
                horizontalAlignment: Text.AlignHCenter
                opacity: 0.6
            }
        }
}
