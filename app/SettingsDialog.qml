/*
 * Interval-break settings (the "nudge every N minutes" feature). Scheduled
 * break blocks are edited as normal tasks; this only covers the background
 * cadence reminder.
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.Dialog {
    id: dialog

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

    signal settingsAccepted(var settings)

    title: i18n("Break settings")
    preferredWidth: Kirigami.Units.gridUnit * 24
    padding: Kirigami.Units.largeSpacing * 2
    standardButtons: Kirigami.Dialog.Ok | Kirigami.Dialog.Cancel

    function openWith(settings) {
        var s = settings || {};
        enabledSwitch.checked = !!s.intervalBreaksEnabled;
        everyBox.value = s.intervalBreakMinutes > 0 ? s.intervalBreakMinutes : 90;
        durationBox.value = s.intervalBreakDurationMinutes > 0 ? s.intervalBreakDurationMinutes : 5;
        open();
    }

    onAccepted: {
        dialog.settingsAccepted({
            intervalBreaksEnabled: enabledSwitch.checked,
            intervalBreakMinutes: everyBox.value,
            intervalBreakDurationMinutes: durationBox.value
        });
    }

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: i18n("Get a “take a break” popup at a fixed cadence, on top of any break blocks you schedule.")
            opacity: 0.8
        }

        Kirigami.FormLayout {
            Layout.fillWidth: true

            QQC2.Switch {
                id: enabledSwitch
                Kirigami.FormData.label: i18n("Interval breaks:")
                text: i18n("Enabled")
            }
            QQC2.SpinBox {
                id: everyBox
                Kirigami.FormData.label: i18n("Remind every:")
                enabled: enabledSwitch.checked
                from: 5
                to: 480
                stepSize: 5
                textFromValue: function (v) {
                    return v + " min";
                }
            }
            QQC2.SpinBox {
                id: durationBox
                Kirigami.FormData.label: i18n("Break length:")
                enabled: enabledSwitch.checked
                from: 1
                to: 60
                stepSize: 1
                textFromValue: function (v) {
                    return v + " min";
                }
            }
        }
    }
}
