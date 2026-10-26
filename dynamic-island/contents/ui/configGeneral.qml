import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import org.kde.kirigami 2.20 as Kirigami

Kirigami.FormLayout {
    id: page

    // The cfg_ prefix binds this field to the `userName` entry in config/main.xml.
    property alias cfg_userName: nameField.text

    TextField {
        id: nameField
        Kirigami.FormData.label: "What's your name?"
        placeholderText: "Shown in the idle greeting"
    }

    Label {
        visible: nameField.text.trim() === ""
        Layout.fillWidth: true
        text: "Leave empty to use DI_USER_NAME from ~/.config/dynamic-island.env"
        opacity: 0.7
        wrapMode: Text.WordWrap
        font: Kirigami.Theme.smallFont
    }
}
