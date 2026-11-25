// The all-apps page: an alphabetical text list with accent letter headers.
// Tap to open; press and hold to pin or unpin on Start.

import QtQuick
import QtQuick.Controls as QQC2

import org.kde.kirigami as Kirigami
import org.kde.kitemmodels as KItemModels

Item {
    id: list

    property var model
    property color accent
    property string fontFamily
    property var isPinned: id => false
    property var appIdFor: favoriteId => favoriteId

    signal launchRequested(string id)
    signal pinToggled(string id)

    function reset() {
        search.text = "";
        view.positionViewAtBeginning();
    }

    QQC2.TextField {
        id: search
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 16
        placeholderText: "search apps"
        font.family: list.fontFamily
        font.pixelSize: 16
        color: "white"
        placeholderTextColor: "#6a6a6a"
        background: Rectangle { color: "#161616"; radius: 10 }
        leftPadding: 14
        topPadding: 10
        bottomPadding: 10
    }

    ListView {
        id: view
        anchors.top: search.bottom
        anchors.topMargin: 8
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        // Filter the model itself, so letter headers of non-matching apps disappear too.
        model: KItemModels.KSortFilterProxyModel {
            sourceModel: list.model
            filterRoleName: "display"
            filterString: search.text
            filterCaseSensitivity: Qt.CaseInsensitive
        }

        section.property: "display"
        section.criteria: ViewSection.FirstCharacter
        section.delegate: Text {
            required property string section
            leftPadding: 16
            topPadding: 8
            bottomPadding: 2
            text: section.toLowerCase()
            color: list.accent
            font.family: list.fontFamily
            font.weight: Font.Light
            font.pixelSize: 26
        }

        delegate: Item {
            id: row
            required property int index
            required property var model
            readonly property string appId: list.appIdFor(model.favoriteId)

            width: view.width
            height: 52

            Kirigami.Icon {
                id: icon
                anchors.verticalCenter: parent.verticalCenter
                x: 16
                width: 32
                height: 32
                source: row.model.decoration
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: icon.right
                anchors.leftMargin: 14
                anchors.right: pin.left
                elide: Text.ElideRight
                text: row.model.display
                color: "white"
                font.family: list.fontFamily
                font.weight: Font.Light
                font.pixelSize: 19
            }
            Rectangle {
                id: pin
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: 18
                width: 6
                height: 6
                radius: 3
                color: list.accent
                visible: list.isPinned(row.appId)
            }
            MouseArea {
                anchors.fill: parent
                onClicked: list.launchRequested(row.appId)
                onPressAndHold: list.pinToggled(row.appId)
            }
        }
    }
}
