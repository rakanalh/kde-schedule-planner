/*
 * Add/edit dialog for a task. Two kinds:
 *   • Recurring — a weekday time block (from–to), drives the widget/timeline.
 *   • One-time  — a dated point-in-time reminder (date + time); notification only.
 * Emits taskAccepted(task) with a raw object the brain will normalize.
 *
 * The date picker is hand-built from spinboxes on purpose: the kirigami-addons
 * DatePopup relies on i18nd/i18ndc, which the bare `qml` runtime doesn't provide.
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "schedule.js" as Sched

Kirigami.Dialog {
    id: dialog

    // i18n()/i18np() shim — this app runs via the bare `qml` runtime, which does
    // not inject KDE's KLocalizedContext.
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

    readonly property var monthNames: ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    readonly property var palette: ["#3daee9", "#27ae60", "#f67400", "#da4453", "#9b59b6", "#1abc9c", "#fdbc4b", "#7f8c8d"]

    property string editId: ""
    property bool isOneTime: false
    property var selectedDays: []
    property string selectedColor: palette[0]

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
            isOneTime = Sched.isOneTime(task);
            if (isOneTime) {
                var p = task.date.split("-");
                setDateBoxes(new Date(parseInt(p[0], 10), parseInt(p[1], 10) - 1, parseInt(p[2], 10)));
                setTime(startHour, startMin, task.time);
                selectedDays = [];
            } else {
                selectedDays = task.days.slice();
                setTime(startHour, startMin, task.start);
                setTime(endHour, endMin, task.end);
                breakSwitch.checked = task.isBreak;
                notifySwitch.checked = task.notify;
                leadBox.value = task.leadMinutes;
            }
        } else {
            resetToDefaults();
        }
        open();
    }

    // open a fresh recurring block pre-filled from a clicked free slot.
    function openNew(prefill) {
        resetToDefaults();
        selectedDays = [prefill.iso];
        var sM = prefill.startMin;
        var eM = Math.min(sM + 60, prefill.endMin, 23 * 60 + 59);
        if (eM <= sM)
            eM = Math.min(sM + 30, 23 * 60 + 59);
        setTime(startHour, startMin, Sched.minutesToHHMM(sM));
        setTime(endHour, endMin, Sched.minutesToHHMM(eM));
        open();
    }

    function resetToDefaults() {
        editId = "";
        titleField.text = "";
        selectedColor = palette[0];
        isOneTime = false;
        selectedDays = [Sched.isoDay(new Date())];
        setDateBoxes(new Date());
        startHour.value = 9;
        startMin.value = 0;
        endHour.value = 10;
        endMin.value = 0;
        breakSwitch.checked = false;
        notifySwitch.checked = true;
        leadBox.value = 0;
    }

    function setDateBoxes(d) {
        yearBox.value = d.getFullYear();
        monthBox.value = d.getMonth() + 1;
        dayBox.value = d.getDate();
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
    readonly property date oneTimeDate: new Date(yearBox.value, monthBox.value - 1, dayBox.value)
    readonly property bool dateValid: {
        var d = oneTimeDate;
        if (d.getMonth() !== monthBox.value - 1)
            return false; // day overflowed the month
        var today = new Date();
        today.setHours(0, 0, 0, 0);
        return d.getTime() >= today.getTime();
    }
    readonly property bool formValid: titleField.text.trim().length > 0 && (isOneTime ? dateValid : (selectedDays.length > 0 && timesValid))

    onAccepted: {
        if (!formValid)
            return;
        var id = editId === "" ? Sched.genId() : editId;
        if (isOneTime) {
            dialog.taskAccepted({
                "id": id,
                "title": titleField.text.trim(),
                "color": selectedColor,
                "date": Sched.formatDate(oneTimeDate),
                "time": startStr,
                "notify": true
            });
        } else {
            dialog.taskAccepted({
                "id": id,
                "title": titleField.text.trim(),
                "color": selectedColor,
                "days": selectedDays.slice().sort(),
                "start": startStr,
                "end": endStr,
                "isBreak": breakSwitch.checked,
                "notify": notifySwitch.checked,
                "leadMinutes": leadBox.value
            });
        }
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

            // ---- type selector ----
            RowLayout {
                Kirigami.FormData.label: i18n("Type:")
                spacing: 0
                QQC2.ButtonGroup {
                    id: typeGroup
                }
                QQC2.Button {
                    text: i18n("Recurring")
                    checkable: true
                    checked: !dialog.isOneTime
                    Layout.fillWidth: true
                    QQC2.ButtonGroup.group: typeGroup
                    onClicked: dialog.isOneTime = false
                }
                QQC2.Button {
                    text: i18n("One-time")
                    checkable: true
                    checked: dialog.isOneTime
                    Layout.fillWidth: true
                    QQC2.ButtonGroup.group: typeGroup
                    onClicked: dialog.isOneTime = true
                }
            }

            // ---- one-time: date (day / month / year) ----
            RowLayout {
                Kirigami.FormData.label: i18n("Date:")
                visible: dialog.isOneTime
                spacing: Kirigami.Units.smallSpacing
                QQC2.SpinBox {
                    id: dayBox
                    from: 1
                    to: new Date(yearBox.value, monthBox.value, 0).getDate()
                    editable: true
                }
                QQC2.SpinBox {
                    id: monthBox
                    from: 1
                    to: 12
                    editable: false
                    textFromValue: function (v) {
                        return dialog.monthNames[v - 1];
                    }
                }
                QQC2.SpinBox {
                    id: yearBox
                    from: new Date().getFullYear()
                    to: new Date().getFullYear() + 5
                    editable: true
                }
            }

            // ---- time: "At" (one-time) or "From" (recurring) ----
            RowLayout {
                Kirigami.FormData.label: dialog.isOneTime ? i18n("At:") : i18n("From:")
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
                visible: !dialog.isOneTime
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
                visible: !dialog.isOneTime
                Kirigami.FormData.label: i18n("This is a break:")
                text: i18n("Pop up “take a break” when it starts")
            }

            QQC2.Switch {
                id: notifySwitch
                visible: !dialog.isOneTime
                Kirigami.FormData.label: i18n("Notify me:")
                text: i18n("Show a notification when it starts")
            }

            QQC2.SpinBox {
                id: leadBox
                visible: !dialog.isOneTime
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
            visible: !dialog.isOneTime && !dialog.timesValid
            type: Kirigami.MessageType.Error
            text: i18n("End time must be after the start time.")
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: dialog.isOneTime && !dialog.dateValid
            type: Kirigami.MessageType.Error
            text: i18n("Pick today or a future date.")
        }

        // ---- days (recurring only) ----
        QQC2.Label {
            visible: !dialog.isOneTime
            text: i18n("Repeat on:")
            font.bold: true
        }
        RowLayout {
            visible: !dialog.isOneTime
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
            visible: !dialog.isOneTime
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
