// One app: its icon, an optional label, and a red badge with the number of
// new notifications. Tap to open, press and hold for the app's menu.

import QtQuick

import org.kde.kirigami as Kirigami

Item {
    id: icon

    property string appId
    property string name
    property var source
    property int badge: 0
    property bool showLabel: true
    property real iconSize: 56
    property string fontFamily

    signal activated()
    signal menuRequested()

    implicitWidth: iconSize + 24
    implicitHeight: iconSize + (showLabel ? 30 : 8)

    Accessible.role: Accessible.Button
    Accessible.name: badge > 0 ? name + ", " + badge + " new" : name
    Accessible.onPressAction: icon.activated()

    Kirigami.Icon {
        id: image
        anchors.horizontalCenter: parent.horizontalCenter
        y: 4
        width: icon.iconSize
        height: icon.iconSize
        source: icon.source || "application-x-executable"
        scale: tap.pressed ? 0.88 : 1
        Behavior on scale { NumberAnimation { duration: 90 } }
    }

    Rectangle {
        visible: icon.badge > 0
        anchors.horizontalCenter: image.right
        anchors.verticalCenter: image.top
        anchors.horizontalCenterOffset: -6
        anchors.verticalCenterOffset: 6
        height: 22
        width: Math.max(height, count.implicitWidth + 12)
        radius: height / 2
        color: "#e01b24"
        border.color: "#ffffff"
        border.width: 1.5
        Text {
            id: count
            anchors.centerIn: parent
            text: icon.badge > 99 ? "99+" : icon.badge
            color: "white"
            font.family: icon.fontFamily
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }
    }

    Text {
        visible: icon.showLabel
        anchors.top: image.bottom
        anchors.topMargin: 6
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: icon.name
        color: "white"
        font.family: icon.fontFamily
        font.pixelSize: 13
        style: Text.Raised
        styleColor: Qt.rgba(0, 0, 0, 0.6)
    }

    TapHandler {
        id: tap
        onTapped: icon.activated()
        onLongPressed: icon.menuRequested()
    }
}
