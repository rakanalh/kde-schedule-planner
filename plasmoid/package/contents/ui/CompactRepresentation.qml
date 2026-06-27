/*
 * Compact (panel) view: a small pill showing the block you should be working
 * on right now, with a thin progress bar. Click to open the timeline popup.
 */
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

MouseArea {
    id: compact

    property var plasmoidItem

    readonly property var task: plasmoidItem ? plasmoidItem.currentTask : null
    readonly property var next: plasmoidItem ? plasmoidItem.nextTask : null
    readonly property real progress: plasmoidItem ? plasmoidItem.currentProgress : 0

    Layout.minimumWidth: Kirigami.Units.gridUnit * 6
    Layout.preferredWidth: row.implicitWidth + Kirigami.Units.largeSpacing * 2

    hoverEnabled: true
    onClicked: plasmoidItem.expanded = !plasmoidItem.expanded

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: Kirigami.Units.smallSpacing

        Rectangle {
            id: dot
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: Kirigami.Units.gridUnit * 0.7
            implicitHeight: implicitWidth
            radius: width / 2
            color: compact.task ? compact.task.color : Kirigami.Theme.disabledTextColor
            border.width: compact.task && compact.task.isBreak ? 2 : 0
            border.color: Kirigami.Theme.backgroundColor
        }

        // title and remaining time on a single line so it fits the panel height
        Kirigami.Heading {
            level: 5
            Layout.alignment: Qt.AlignVCenter
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: compact.task ? compact.task.title + " · " + i18np("%1 min left", "%1 min left", plasmoidItem.remainingMinutes) : (compact.next ? i18n("Free until %1", compact.next.start) : i18n("Free"))
        }
    }

    // thin progress bar pinned to the bottom of the pill
    Rectangle {
        visible: plasmoidItem && plasmoidItem.Plasmoid.configuration.showProgressBar && compact.task !== null
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Math.max(2, Kirigami.Units.smallSpacing / 2)
        color: Kirigami.Theme.backgroundColor
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * Math.max(0, Math.min(1, compact.progress))
            color: compact.task ? compact.task.color : "transparent"
        }
    }
}
