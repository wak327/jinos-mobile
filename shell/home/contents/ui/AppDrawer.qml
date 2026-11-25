// All apps, alphabetically, with search. Slides up over the home page.
// progress: 0 = closed, 1 = open; the home page drives it while dragging.

import QtQuick
import QtQuick.Controls as QQC2

import org.kde.kitemmodels as KItemModels

import "logic.js" as Logic

Rectangle {
    id: drawer

    property var model
    property var badges: ({})     // app id -> count
    property string fontFamily
    property real topMargin
    property real bottomMargin
    property real progress: 0
    property bool dragging: false

    signal launchRequested(string id)
    signal menuRequested(Item item, string id, string name)

    function open() { dragging = false; progress = 1; }
    function close() {
        dragging = false;
        progress = 0;
        search.text = "";
        search.focus = false;
        grid.positionViewAtBeginning();
    }

    y: (1 - progress) * height
    visible: progress > 0.001
    color: Qt.rgba(0.06, 0.06, 0.08, 0.97)
    Behavior on progress {
        enabled: !drawer.dragging
        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
    }

    // Swallow taps so they don't reach the home page underneath.
    MouseArea { anchors.fill: parent }

    // Pull handle: drag it down (or tap it) to close.
    Item {
        id: handle
        anchors.top: parent.top
        anchors.topMargin: drawer.topMargin
        width: parent.width
        height: 28
        Rectangle {
            anchors.centerIn: parent
            width: 40
            height: 5
            radius: 2.5
            color: Qt.rgba(1, 1, 1, 0.4)
        }
        TapHandler { onTapped: drawer.close() }
        DragHandler {
            target: null
            xAxis.enabled: false
            onActiveChanged: {
                if (active) {
                    drawer.dragging = true;
                } else if (drawer.progress < 0.75) {
                    drawer.close();
                } else {
                    drawer.open();
                }
            }
            onTranslationChanged: {
                if (active) {
                    drawer.progress = Math.max(0, Math.min(1, 1 - translation.y / drawer.height));
                }
            }
        }
    }

    QQC2.TextField {
        id: search
        anchors.top: handle.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        placeholderText: "Search apps"
        font.family: drawer.fontFamily
        font.pixelSize: 16
        color: "white"
        placeholderTextColor: Qt.rgba(1, 1, 1, 0.5)
        leftPadding: 16
        topPadding: 10
        bottomPadding: 10
        background: Rectangle { color: Qt.rgba(1, 1, 1, 0.1); radius: height / 2 }
        Keys.onReturnPressed: {
            if (grid.count > 0) {
                grid.itemAtIndex(0).activated();
            }
        }
    }

    GridView {
        id: grid
        anchors.top: search.bottom
        anchors.topMargin: 16
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        anchors.bottom: parent.bottom
        anchors.bottomMargin: drawer.bottomMargin
        clip: true
        cellWidth: Math.floor(width / 4)
        cellHeight: 104
        boundsBehavior: Flickable.DragOverBounds

        model: KItemModels.KSortFilterProxyModel {
            sourceModel: drawer.model
            filterRoleName: "description"
            sortRoleName: "description"
            sortCaseSensitivity: Qt.CaseInsensitive
            filterString: search.text
            filterCaseSensitivity: Qt.CaseInsensitive
        }

        // Pulling the list down past its top closes the drawer, like on most phones.
        onDragEnded: {
            if (contentY < originY - 90) {
                drawer.close();
            }
        }

        delegate: Item {
            id: cell
            required property var model
            readonly property string appId: Logic.appId(model.favoriteId)
            readonly property string name: Logic.shortName(model.description, model.compactName)
            width: grid.cellWidth
            height: grid.cellHeight
            function activated() { drawer.launchRequested(appId); }
            AppIcon {
                id: icon
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                appId: cell.appId
                name: cell.name
                source: cell.model.decoration
                badge: drawer.badges[cell.appId] || 0
                fontFamily: drawer.fontFamily
                onActivated: cell.activated()
                onMenuRequested: drawer.menuRequested(icon, cell.appId, cell.name)
            }
        }

        Text {
            anchors.centerIn: parent
            visible: grid.count === 0 && search.text !== ""
            text: "No apps match “" + search.text + "”"
            color: Qt.rgba(1, 1, 1, 0.6)
            font.family: drawer.fontFamily
            font.pixelSize: 15
        }
    }
}
