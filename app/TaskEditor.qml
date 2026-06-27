/*
 * Add/edit dialog for a single time block.
 * Emits accepted(task) with a fully-formed task object.
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "schedule.js" as Sched

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

    signal taskAccepted(var task)

    property string editId: ""
    property var selectedDays: []
    property string selectedColor: palette[0]

    readonly property var palette: ["#3daee9", "#27ae60", "#f67400", "#da4453", "#9b59b6", "#1abc9c", "#fdbc4b", "#7f8c8d"]

    title: editId === "" ? i18n("Add task") : i18n("Edit task")
    preferredWidth: Kirigami.Units.gridUnit * 26
    padding: Kirigami.Units.largeSpacing * 2
    standardButtons: Kirigami.Dialog.Ok | Kirigami.Dialog.Cancel

    // ---- public API ----
    function openFor(task) {
        if (task) {
            editId = task.id;
            titleField.text = task.title;
            selectedColor = task.color;
            selectedDays = task.days.slice();
            setTime(startHour, startMin, task.start);
            setTime(endHour, endMin, task.end);
            breakSwitch.checked = task.isBreak;
            notifySwitch.checked = task.notify;
            leadBox.value = task.leadMinutes;
        } else {
            editId = "";
            titleField.text = "";
            selectedColor = palette[0];
            selectedDays = [Sched.isoDay(new Date())];
            startHour.value = 9;
            startMin.value = 0;
            endHour.value = 10;
            endMin.value = 0;
            breakSwitch.checked = false;
            notifySwitch.checked = true;
            leadBox.value = 0;
        }
        open();
    }

    // open a fresh task pre-filled from a clicked free slot (start time + day).
    // The end defaults to a 1-hour block, but never past the slot's end or 23:59.
    function openNew(prefill) {
        editId = "";
        titleField.text = "";
        selectedColor = palette[0];
        breakSwitch.checked = false;
        notifySwitch.checked = true;
        leadBox.value = 0;
        selectedDays = [prefill.iso];
        var sM = prefill.startMin;
        var eM = Math.min(sM + 60, prefill.endMin, 23 * 60 + 59);
        if (eM <= sM)
            eM = Math.min(sM + 30, 23 * 60 + 59);
        setTime(startHour, startMin, Sched.minutesToHHMM(sM));
        setTime(endHour, endMin, Sched.minutesToHHMM(eM));
        open();
    }

    function setTime(hourBox, minBox, hhmm) {
        var m = Sched.toMinutes(hhmm);
        hourBox.value = Math.floor(m / 60);
        minBox.value = m % 60;
    }
    function fmt(hourBox, minBox) {
        return Sched.minutesToHHMM(hourBox.value * 60 + minBox.value);
    }

    readonly property string startStr: fmt(startHour, startMin)
    readonly property string endStr: fmt(endHour, endMin)
    readonly property bool timesValid: Sched.toMinutes(endStr) > Sched.toMinutes(startStr)
    readonly property bool formValid: titleField.text.trim().length > 0 && selectedDays.length > 0 && timesValid

    onAccepted: {
        if (!formValid)
            return;
        dialog.taskAccepted({
            id: editId === "" ? Sched.genId() : editId,
            title: titleField.text.trim(),
            color: selectedColor,
            days: selectedDays.slice().sort(),
            start: startStr,
            end: endStr,
            isBreak: breakSwitch.checked,
            notify: notifySwitch.checked,
            leadMinutes: leadBox.value
        });
    }

    // disable OK while invalid
    Component.onCompleted: standardButton(Kirigami.Dialog.Ok).enabled = Qt.binding(function () {
        return formValid;
    })

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        Kirigami.FormLayout {
            Layout.fillWidth: true

            QQC2.TextField {
                id: titleField
                Kirigami.FormData.label: i18n("Title:")
                placeholderText: i18n("e.g. Deep Work")
            }

            RowLayout {
                Kirigami.FormData.label: i18n("From:")
                QQC2.SpinBox {
                    id: startHour
                    from: 0
                    to: 23
                    editable: true
                }
                QQC2.Label {
                    text: ":"
                }
                QQC2.SpinBox {
                    id: startMin
                    from: 0
                    to: 59
                    stepSize: 5
                    editable: true
                }
            }
            RowLayout {
                Kirigami.FormData.label: i18n("To:")
                QQC2.SpinBox {
                    id: endHour
                    from: 0
                    to: 23
                    editable: true
                }
                QQC2.Label {
                    text: ":"
                }
                QQC2.SpinBox {
                    id: endMin
                    from: 0
                    to: 59
                    stepSize: 5
                    editable: true
                }
            }

            QQC2.Switch {
                id: breakSwitch
                Kirigami.FormData.label: i18n("This is a break:")
                text: i18n("Pop up “take a break” when it starts")
            }

            QQC2.Switch {
                id: notifySwitch
                Kirigami.FormData.label: i18n("Notify me:")
                text: i18n("Show a notification when it starts")
            }

            QQC2.SpinBox {
                id: leadBox
                Kirigami.FormData.label: i18n("Remind me:")
                enabled: notifySwitch.checked
                from: 0
                to: 120
                stepSize: 5
                textFromValue: function (v) {
                    return v === 0 ? i18n("at start time") : v + i18n(" min before");
                }
            }
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: !dialog.timesValid
            type: Kirigami.MessageType.Error
            text: i18n("End time must be after the start time.")
        }

        // ---- days ----
        QQC2.Label {
            text: i18n("Repeat on:")
            font.bold: true
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
                    checked: dialog.selectedDays.indexOf(iso) !== -1
                    onClicked: {
                        var d = dialog.selectedDays.slice();
                        var at = d.indexOf(iso);
                        if (at === -1)
                            d.push(iso);
                        else
                            d.splice(at, 1);
                        dialog.selectedDays = d;
                    }
                }
            }
        }
        RowLayout {
            spacing: Kirigami.Units.smallSpacing
            QQC2.Button {
                text: i18n("Every day")
                flat: true
                onClicked: dialog.selectedDays = [1, 2, 3, 4, 5, 6, 7]
            }
            QQC2.Button {
                text: i18n("Weekdays")
                flat: true
                onClicked: dialog.selectedDays = [1, 2, 3, 4, 5]
            }
            QQC2.Button {
                text: i18n("Clear")
                flat: true
                onClicked: dialog.selectedDays = []
            }
        }

        // ---- color ----
        QQC2.Label {
            text: i18n("Color:")
            font.bold: true
        }
        RowLayout {
            spacing: Kirigami.Units.smallSpacing
            Repeater {
                model: dialog.palette
                delegate: Rectangle {
                    required property string modelData
                    width: Kirigami.Units.gridUnit * 1.6
                    height: width
                    radius: width / 2
                    color: modelData
                    border.width: dialog.selectedColor === modelData ? 3 : 0
                    border.color: Kirigami.Theme.textColor
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: dialog.selectedColor = modelData
                    }
                }
            }
        }
    }
}
