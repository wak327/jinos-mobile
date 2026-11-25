// One Start tile. Small tiles show a monochrome glyph. Wide tiles are live:
// the newest notification for that app, or the battery for "jinos:battery".
// They turn the accent colour only when there is something new.
// Press and hold for edit mode: unpin and resize buttons on the tile.

import QtQuick

import org.kde.kirigami as Kirigami
import org.kde.plasma.private.mobileshell as MobileShell

Rectangle {
    id: tile

    property string tileId
    property string size: "small"
    property real unit
    property real gap
    property var app            // { name, icon } or null
    property color accent
    property string fontFamily
    property bool editing: false
    property var notices: []    // this app's notifications, newest first: { created, summary, body }
    property var seenAt         // Date this app was last opened from Start, or undefined

    signal activated()
    signal longPressed()
    signal unpinRequested()
    signal resizeRequested()

    readonly property bool isBattery: tileId === "jinos:battery"
    readonly property bool isWide: size === "wide"
    // New = arrived after the app was last opened from Start.
    readonly property var fresh: notices.filter(n => !seenAt || n.created > seenAt)
    readonly property int unread: isBattery ? 0 : fresh.length
    readonly property bool lit: unread > 0 || (isBattery && MobileShell.BatteryInfo.percent <= 15 && !MobileShell.BatteryInfo.pluggedIn)
    readonly property var latest: isWide && fresh.length > 0 ? fresh[0] : null

    // Monochrome glyphs from the Breeze theme for the apps jinOS knows. Use the
    // -symbolic names: masking a full-colour icon gives a solid white shape.
    readonly property var glyphs: ({
        "org.gnome.Calls.desktop": "call-start-symbolic",
        "sm.puri.Chatty.desktop": "mail-message-symbolic",
        "org.jinos.Contacts.desktop": "im-user-symbolic",
        "org.jinos.Camera.desktop": "camera-photo-symbolic",
        "org.jinos.Gallery.desktop": "view-preview-symbolic",
        "org.kde.mobile.plasmasettings.desktop": "settings-configure-symbolic",
        "org.jinos.About.desktop": "help-about-symbolic",
        "org.gnome.Console.desktop": "utilities-terminal-symbolic",
        "jinos:battery": "battery-good-symbolic"
    })

    width: isWide ? 2 * unit + gap : unit
    height: unit
    radius: 10
    color: lit ? accent : "#161616"
    scale: editing ? 0.94 : (press.pressed ? 0.96 : 1)
    Behavior on scale { NumberAnimation { duration: 100 } }
    Behavior on color { ColorAnimation { duration: 200 } }

    Kirigami.Icon {
        anchors.centerIn: tile.isWide ? undefined : parent
        x: 12
        y: 12
        width: tile.isWide ? 22 : Math.round(tile.unit * 0.36)
        height: width
        source: tile.glyphs[tile.tileId] || (tile.app ? tile.app.icon : "application-x-executable")
        isMask: tile.glyphs[tile.tileId] !== undefined
        color: "white"
    }

    // Unread count, top right of wide tiles.
    Text {
        visible: tile.isWide && tile.unread > 0
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 10
        color: "white"
        font.family: tile.fontFamily
        font.weight: Font.Light
        font.pixelSize: 26
        text: tile.unread
    }

    // Large battery figure, Windows Phone style.
    Text {
        visible: tile.isBattery && MobileShell.BatteryInfo.isVisible
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 8
        color: "white"
        font.family: tile.fontFamily
        font.weight: Font.Thin
        font.pixelSize: 34
        text: MobileShell.BatteryInfo.percent
    }

    Column {
        visible: tile.isWide
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 12
        spacing: 2

        Text {
            width: parent.width
            visible: text !== ""
            elide: Text.ElideRight
            color: "white"
            font.family: tile.fontFamily
            font.pixelSize: 14
            text: tile.latest ? tile.latest.summary : ""
            textFormat: Text.PlainText
        }
        Text {
            width: parent.width
            elide: Text.ElideRight
            color: tile.lit ? "white" : "#bdbdbd"
            font.family: tile.fontFamily
            font.pixelSize: 12
            text: {
                if (tile.isBattery) {
                    return MobileShell.BatteryInfo.percent + "%" + (MobileShell.BatteryInfo.pluggedIn ? " · charging" : "");
                }
                if (tile.latest && tile.latest.body) {
                    return tile.latest.body;
                }
                return tile.app ? tile.app.name : "";
            }
            textFormat: Text.PlainText
        }
    }

    MouseArea {
        id: press
        anchors.fill: parent
        onClicked: tile.activated()
        onPressAndHold: tile.longPressed()
    }

    // Edit mode: unpin (top right) and resize (bottom right).
    component EditButton: Rectangle {
        id: button
        property string icon
        property string label
        signal triggered()
        width: 32
        height: 32
        radius: 16
        color: "white"
        Kirigami.Icon {
            anchors.centerIn: parent
            width: 16
            height: 16
            source: button.icon
            isMask: true
            color: "black"
        }
        Accessible.role: Accessible.Button
        Accessible.name: button.label
        MouseArea {
            anchors.fill: parent
            anchors.margins: -8
            onClicked: button.triggered()
        }
    }

    EditButton {
        visible: tile.editing
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: -8
        icon: "window-close-symbolic"
        label: "Unpin"
        onTriggered: tile.unpinRequested()
    }
    EditButton {
        visible: tile.editing && !tile.isBattery
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: -8
        icon: tile.isWide ? "zoom-out-symbolic" : "zoom-in-symbolic"
        label: tile.isWide ? "Make small" : "Make wide"
        onTriggered: tile.resizeRequested()
    }
}
