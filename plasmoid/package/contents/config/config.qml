import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18nc("@title:group", "General")
        icon: "view-calendar-day"
        source: "ConfigGeneral.qml"
    }
}
