// jinOS Start: the Quiet Metro home screen.
// Page 1 is the clock and tiles; swipe left for the app list.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.plasma.plasmoid
import org.kde.plasma.private.kicker as Kicker
import org.kde.plasma.private.mobileshell as MobileShell
import org.kde.notificationmanager as NotificationManager

ContainmentItem {
    id: root

    readonly property color accent: Plasmoid.configuration.accentColor
    readonly property string fontFamily: "Inter"

    // desktop file id -> { name, icon }, rebuilt whenever the app list changes
    property var apps: ({})

    function appId(favoriteId) {
        return (favoriteId || "").replace(/^applications:/, "");
    }

    function launch(id) {
        MobileShell.AppLaunch.launchOrActivateApp(id);
    }

    function tileEntries() {
        return Plasmoid.configuration.tiles.map(entry => {
            const parts = entry.split("|");
            return { id: parts[0], size: parts[1] === "wide" ? "wide" : "small" };
        }).filter(t => t.id === "jinos:battery" ? MobileShell.BatteryInfo.isVisible : root.apps[t.id] !== undefined);
    }

    function isPinned(id) {
        return Plasmoid.configuration.tiles.some(entry => entry.split("|")[0] === id);
    }

    property string editingTile: ""

    function resizeTile(id) {
        Plasmoid.configuration.tiles = Plasmoid.configuration.tiles.map(entry => {
            const parts = entry.split("|");
            return parts[0] === id ? id + "|" + (parts[1] === "wide" ? "small" : "wide") : entry;
        });
    }

    function seenFor(id) {
        try {
            const iso = JSON.parse(Plasmoid.configuration.seen)[id];
            return iso ? new Date(iso) : undefined;
        } catch (e) {
            return undefined;
        }
    }

    function markSeen(id) {
        let seen = {};
        try { seen = JSON.parse(Plasmoid.configuration.seen); } catch (e) {}
        seen[id] = new Date().toISOString();
        Plasmoid.configuration.seen = JSON.stringify(seen);
    }

    function togglePin(id) {
        const tiles = Plasmoid.configuration.tiles.slice();
        const index = tiles.findIndex(entry => entry.split("|")[0] === id);
        if (index >= 0) {
            tiles.splice(index, 1);
        } else {
            tiles.push(id + "|small");
        }
        Plasmoid.configuration.tiles = tiles;
    }

    function goHome() {
        root.editingTile = "";
        pages.setCurrentIndex(0);
        startPage.contentY = startPage.originY;
        appList.reset();
    }

    // KDE's app menu. A standalone Kicker.AppsModel comes back empty under
    // Plasma Mobile; the "All Applications" row of RootModel is what Kickoff uses.
    Kicker.RootModel {
        id: rootModel
        autoPopulate: false
        appletInterface: root
        flat: true
        sorted: true
        showSeparators: false
        showAllApps: true
        showAllAppsCategorized: false
        showTopLevelItems: false
        showRecentApps: false
        showRecentDocs: false
        showPowerSession: false
        showFavoritesPlaceholder: false
        Component.onCompleted: refresh()
    }
    readonly property var allApps: rootModel.count > 0 ? rootModel.modelForRow(0) : null

    Instantiator {
        id: appIndex
        model: root.allApps
        delegate: QtObject {
            readonly property string appId: root.appId(model.favoriteId)
            readonly property string name: model.display
            readonly property var icon: model.decoration
        }
        onObjectAdded: rebuild.restart()
        onObjectRemoved: rebuild.restart()
    }

    Timer {
        id: rebuild
        interval: 50
        onTriggered: {
            const map = {};
            for (let i = 0; i < appIndex.count; i++) {
                const entry = appIndex.objectAt(i);
                if (entry && entry.appId) {
                    map[entry.appId] = { name: entry.name, icon: entry.icon };
                }
            }
            root.apps = map;
        }
    }

    // All notifications, grouped by app here. Plasma's own per-app filter and
    // "unread" count did not match what a live tile needs.
    property var notices: ({})   // desktop entry -> [{ created, summary, body }], newest first

    function plain(text) {
        return (text || "").replace(/<[^>]*>/g, " ").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
            .replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&amp;/g, "&").replace(/\s+/g, " ").trim();
    }

    NotificationManager.Notifications {
        id: allNotifications
        showNotifications: true
        showJobs: false
        showExpired: true
        showDismissed: false
        groupMode: NotificationManager.Notifications.GroupDisabled
        sortMode: NotificationManager.Notifications.SortByDate
        sortOrder: Qt.DescendingOrder
    }

    Instantiator {
        id: noticeIndex
        model: allNotifications
        delegate: QtObject {
            readonly property string desktopEntry: model.desktopEntry || ""
            readonly property var created: model.created
            readonly property string summary: model.summary || ""
            readonly property string body: model.body || ""
        }
        onObjectAdded: rebuildNotices.restart()
        onObjectRemoved: rebuildNotices.restart()
    }

    Timer {
        id: rebuildNotices
        interval: 50
        onTriggered: {
            const map = {};
            for (let i = 0; i < noticeIndex.count; i++) {
                const n = noticeIndex.objectAt(i);
                if (!n || !n.desktopEntry) {
                    continue;
                }
                const key = n.desktopEntry + ".desktop";
                (map[key] = map[key] || []).push({
                    created: n.created,
                    summary: root.plain(n.summary),
                    body: root.plain(n.body)
                });
            }
            root.notices = map;
        }
    }

    QtObject {
        id: now
        property date date: new Date()
    }
    Timer {
        interval: 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: now.date = new Date()
    }

    MobileShell.HomeScreen {
        id: homeScreen
        anchors.fill: parent
        plasmoidItem: root

        onHomeTriggered: root.goHome()
        onResetHomeScreenPosition: root.goHome()

        contentItem: Rectangle {
            color: "black"

            QQC2.SwipeView {
                id: pages
                anchors.fill: parent
                anchors.topMargin: homeScreen.topMargin
                anchors.bottomMargin: homeScreen.bottomMargin
                clip: true

                // ---- Page 1: clock and tiles ----
                Flickable {
                    id: startPage
                    contentHeight: Math.max(startColumn.height + 48, height)
                    boundsBehavior: Flickable.DragOverBounds

                    // Tapping empty space leaves tile edit mode.
                    MouseArea {
                        width: startPage.width
                        height: startPage.contentHeight
                        onClicked: root.editingTile = ""
                    }

                    ColumnLayout {
                        id: startColumn
                        x: 16
                        y: 24
                        width: startPage.width - 32
                        spacing: 0

                        Text {
                            text: Qt.formatTime(now.date, "HH:mm")
                            color: "white"
                            font.family: root.fontFamily
                            font.weight: Font.Thin
                            font.pixelSize: 72
                        }
                        Text {
                            text: Qt.formatDate(now.date, "dddd, MMMM d")
                            color: "#8a8a8a"
                            font.family: root.fontFamily
                            font.weight: Font.Light
                            font.pixelSize: 16
                            Layout.bottomMargin: 28
                        }

                        Flow {
                            id: tiles
                            readonly property real unit: Math.floor((width - 3 * spacing) / 4)
                            Layout.fillWidth: true
                            spacing: 6

                            Repeater {
                                model: root.tileEntries()
                                delegate: Tile {
                                    required property var modelData
                                    tileId: modelData.id
                                    size: modelData.size
                                    unit: tiles.unit
                                    gap: tiles.spacing
                                    app: root.apps[modelData.id] || null
                                    accent: root.accent
                                    fontFamily: root.fontFamily
                                    editing: root.editingTile === modelData.id
                                    seenAt: root.seenFor(modelData.id)
                                    notices: root.notices[modelData.id] || []
                                    onActivated: {
                                        if (root.editingTile !== "") {
                                            root.editingTile = "";
                                        } else if (modelData.id !== "jinos:battery") {
                                            root.markSeen(modelData.id);
                                            root.launch(modelData.id);
                                        }
                                    }
                                    onLongPressed: root.editingTile = modelData.id
                                    onUnpinRequested: {
                                        root.editingTile = "";
                                        root.togglePin(modelData.id);
                                    }
                                    onResizeRequested: root.resizeTile(modelData.id)
                                }
                            }
                        }

                        Text {
                            visible: root.tileEntries().length === 0
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            color: "#8a8a8a"
                            font.family: root.fontFamily
                            font.weight: Font.Light
                            font.pixelSize: 16
                            text: "Nothing pinned. Open all apps, then press and hold an app to pin it here."
                        }

                        Text {
                            text: "all apps  ›"
                            color: "#8a8a8a"
                            font.family: root.fontFamily
                            font.pixelSize: 14
                            Layout.alignment: Qt.AlignRight
                            Layout.topMargin: 20
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -12
                                onClicked: pages.setCurrentIndex(1)
                            }
                        }
                    }
                }

                // ---- Page 2: all apps ----
                AppList {
                    id: appList
                    model: root.allApps
                    accent: root.accent
                    fontFamily: root.fontFamily
                    isPinned: id => root.isPinned(id)
                    appIdFor: favoriteId => root.appId(favoriteId)
                    onLaunchRequested: id => root.launch(id)
                    onPinToggled: id => root.togglePin(id)
                }
            }
        }
    }
}
