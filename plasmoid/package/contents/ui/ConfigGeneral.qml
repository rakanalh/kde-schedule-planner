import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCMUtils
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

KCMUtils.SimpleKCM {
    id: page

    property alias cfg_timelineStartHour: startHour.value
    property alias cfg_timelineEndHour: endHour.value
    property alias cfg_plannerCommand: plannerCommand.text
    property alias cfg_showProgressBar: showProgressBar.checked
    property alias cfg_playSound: playSound.checked

    Kirigami.FormLayout {
        QQC2.SpinBox {
            id: startHour
            Kirigami.FormData.label: i18n("Timeline starts at hour:")
            from: 0
            to: 23
        }
        QQC2.SpinBox {
            id: endHour
            Kirigami.FormData.label: i18n("Timeline ends at hour:")
            from: 1
            to: 24
        }
        QQC2.CheckBox {
            id: showProgressBar
            Kirigami.FormData.label: i18n("Panel display:")
            text: i18n("Show progress bar for the current task")
        }
        QQC2.CheckBox {
            id: playSound
            Kirigami.FormData.label: i18n("Notifications:")
            text: i18n("Ring a bell when a notification fires")
        }
        QQC2.TextField {
            id: plannerCommand
            Kirigami.FormData.label: i18n("Planner launch command:")
            Layout.minimumWidth: Kirigami.Units.gridUnit * 16
        }
        QQC2.Label {
            text: i18n("Opened when you click “Plan my day…”.")
            opacity: 0.7
            font: Kirigami.Theme.smallFont
        }
    }
}
