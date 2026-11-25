// jinOS Home: a familiar phone home screen for Plasma Mobile.
// Clock, a grid of app icons, a dock, and an app drawer (swipe up).
// Press and hold any app for a menu to add or remove it from home or dock.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.notificationmanager as NotificationManager
import org.kde.plasma.plasmoid
import org.kde.plasma.private.kicker as Kicker
import org.kde.plasma.private.mobileshell as MobileShell

import "logic.js" as Logic

ContainmentItem {
    id: root

    readonly property string fontFamily: "Inter"

    // ---- Apps ------------------------------------------------------------

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
        // GenericNameOnly: "description" is then the app's full name and
        // "compactName" its generic name, which Logic.shortName needs. The
        // drawer sorts and searches on "description" itself.
        appNameFormat: 1
        showTopLevelItems: false
        showRecentApps: false
        showRecentDocs: false
        showPowerSession: false
        showFavoritesPlaceholder: false
        Component.onCompleted: refresh()
    }
    readonly property var allApps: rootModel.count > 0 ? rootModel.modelForRow(0) : null

    property var apps: ({})   // desktop file id -> { name, icon }

    Instantiator {
        id: appIndex
        model: root.allApps
        delegate: QtObject {
            readonly property string appId: Logic.appId(model.favoriteId)
            readonly property string name: Logic.shortName(model.description, model.compactName)
            readonly property var icon: model.decoration
        }
        onObjectAdded: rebuildApps.restart()
        onObjectRemoved: rebuildApps.restart()
    }
    Timer {
        id: rebuildApps
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

    // The configured dock may name apps that aren't installed (yet); only installed ones count.
    readonly property var dockApps: Logic.installed(Plasmoid.configuration.dock, apps).slice(0, Logic.DOCK_SIZE)
    readonly property var homeApps: Logic.installed(Plasmoid.configuration.home, apps)

    function launch(id) {
        Plasmoid.configuration.seen = Logic.markSeen(Plasmoid.configuration.seen, id, new Date());
        MobileShell.AppLaunch.launchOrActivateApp(id);
        drawer.close();
    }

    function toggle(key, id) {
        const list = Plasmoid.configuration[key];
        if (Logic.contains(list, id)) {
            Plasmoid.configuration[key] = Logic.remove(list, id);
        } else if (key !== "dock" || root.dockApps.length < Logic.DOCK_SIZE) {
            Plasmoid.configuration[key] = Logic.add(list, id, 0);
        }
    }

    // ---- Notification badges ----------------------------------------------

    // All notifications, grouped by app here. Plasma's own per-app filter and
    // unread count don't match what a badge needs (see the jinOS Start README).
    property var notices: ({})

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
            const items = [];
            for (let i = 0; i < noticeIndex.count; i++) {
                items.push(noticeIndex.objectAt(i));
            }
            root.notices = Logic.groupNotices(items);
        }
    }

    readonly property var badges: {
        const seen = Logic.parseSeen(Plasmoid.configuration.seen);
        const result = {};
        for (const id in root.notices) {
            result[id] = Logic.unread(root.notices[id], seen[id]);
        }
        return result;
    }

    // ---- Clock -----------------------------------------------------------

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

    // ---- Screen ----------------------------------------------------------

    MobileShell.HomeScreen {
        id: homeScreen
        anchors.fill: parent
        plasmoidItem: root

        onHomeTriggered: drawer.close()
        onResetHomeScreenPosition: drawer.close()

        contentItem: Item {
            // Darken the top and bottom of the wallpaper so text stays readable.
            Rectangle {
                anchors.top: parent.top
                width: parent.width
                height: 260
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.55) }
                    GradientStop { position: 1; color: "transparent" }
                }
            }
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 260
                gradient: Gradient {
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.55) }
                }
            }

            Item {
                id: home
                anchors.fill: parent
                anchors.topMargin: homeScreen.topMargin
                anchors.bottomMargin: homeScreen.bottomMargin
                opacity: 1 - drawer.progress

                // Swipe up anywhere on the home page to open the drawer.
                DragHandler {
                    id: swipeUp
                    target: null
                    xAxis.enabled: false
                    onActiveChanged: {
                        if (active) {
                            drawer.dragging = true;
                        } else if (drawer.progress > 0.25) {
                            drawer.open();
                        } else {
                            drawer.close();
                        }
                    }
                    onTranslationChanged: {
                        if (active) {
                            drawer.progress = Math.max(0, Math.min(1, -translation.y / root.height));
                        }
                    }
                }

                ColumnLayout {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: dockArea.top
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    anchors.topMargin: 28
                    spacing: 0

                    Text {
                        text: Qt.formatTime(now.date, "HH:mm")
                        color: "white"
                        font.family: root.fontFamily
                        font.weight: Font.Light
                        font.pixelSize: 64
                        Layout.leftMargin: 8
                    }
                    Text {
                        text: Qt.formatDate(now.date, "dddd, d MMMM")
                        color: Qt.rgba(1, 1, 1, 0.85)
                        font.family: root.fontFamily
                        font.pixelSize: 17
                        Layout.leftMargin: 10
                        Layout.bottomMargin: 32
                    }

                    Grid {
                        id: homeGrid
                        Layout.fillWidth: true
                        columns: 4
                        rowSpacing: 8
                        readonly property real cell: Math.floor(width / 4)
                        Repeater {
                            model: root.homeApps
                            delegate: AppIcon {
                                id: homeIcon
                                required property string modelData
                                width: homeGrid.cell
                                appId: modelData
                                name: root.apps[modelData].name
                                source: root.apps[modelData].icon
                                badge: root.badges[modelData] || 0
                                fontFamily: root.fontFamily
                                onActivated: root.launch(modelData)
                                onMenuRequested: appMenu.show(homeIcon, modelData, root.apps[modelData].name)
                            }
                        }
                    }

                    Text {
                        visible: root.homeApps.length === 0
                        Layout.fillWidth: true
                        Layout.leftMargin: 10
                        Layout.rightMargin: 10
                        wrapMode: Text.Wrap
                        color: Qt.rgba(1, 1, 1, 0.75)
                        font.family: root.fontFamily
                        font.pixelSize: 15
                        text: "Swipe up for all apps. Press and hold an app to add it here."
                    }

                    Item { Layout.fillHeight: true }
                }

                Column {
                    id: dockArea
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 12
                    spacing: 6

                    // Tap or swipe up on the handle for all apps.
                    Item {
                        width: parent.width
                        height: 26
                        Text {
                            anchors.centerIn: parent
                            text: "⌃"
                            color: Qt.rgba(1, 1, 1, 0.8)
                            font.pixelSize: 22
                        }
                        Accessible.role: Accessible.Button
                        Accessible.name: "All apps"
                        TapHandler { onTapped: drawer.open() }
                    }

                    Rectangle {
                        width: parent.width
                        height: 88
                        radius: 28
                        color: Qt.rgba(1, 1, 1, 0.16)
                        visible: root.dockApps.length > 0

                        // Four apps fill the dock; fewer sit together in the middle.
                        Row {
                            anchors.centerIn: parent
                            spacing: root.dockApps.length === Logic.DOCK_SIZE
                                ? Math.max(0, (parent.width - 16 - Logic.DOCK_SIZE * 72) / (Logic.DOCK_SIZE - 1))
                                : 16
                            Repeater {
                                model: root.dockApps
                                delegate: AppIcon {
                                    id: dockIcon
                                    required property string modelData
                                    width: 72
                                    showLabel: false
                                    appId: modelData
                                    name: root.apps[modelData].name
                                    source: root.apps[modelData].icon
                                    badge: root.badges[modelData] || 0
                                    fontFamily: root.fontFamily
                                    onActivated: root.launch(modelData)
                                    onMenuRequested: appMenu.show(dockIcon, modelData, root.apps[modelData].name)
                                }
                            }
                        }
                    }
                }
            }

            AppDrawer {
                id: drawer
                width: parent.width
                height: parent.height
                model: root.allApps
                badges: root.badges
                fontFamily: root.fontFamily
                topMargin: homeScreen.topMargin
                bottomMargin: homeScreen.bottomMargin
                onLaunchRequested: id => root.launch(id)
                onMenuRequested: (item, id, name) => appMenu.show(item, id, name)
            }
        }
    }

    // ---- Press-and-hold menu ----------------------------------------------

    QQC2.Menu {
        id: appMenu
        property string appId
        property string appName
        readonly property bool inHome: Logic.contains(Plasmoid.configuration.home, appId)
        readonly property bool inDock: Logic.contains(Plasmoid.configuration.dock, appId)
        readonly property bool dockFull: root.dockApps.length >= Logic.DOCK_SIZE

        function show(item, id, name) {
            appId = id;
            appName = name;
            popup(item);
        }

        QQC2.MenuItem {
            text: "Open " + appMenu.appName
            icon.name: "media-playback-start-symbolic"
            onTriggered: root.launch(appMenu.appId)
        }
        QQC2.MenuItem {
            text: appMenu.inHome ? "Remove from home screen" : "Add to home screen"
            icon.name: appMenu.inHome ? "list-remove-symbolic" : "list-add-symbolic"
            onTriggered: root.toggle("home", appMenu.appId)
        }
        QQC2.MenuItem {
            text: appMenu.inDock ? "Remove from dock" : (appMenu.dockFull ? "Dock is full" : "Add to dock")
            enabled: appMenu.inDock || !appMenu.dockFull
            icon.name: appMenu.inDock ? "list-remove-symbolic" : "list-add-symbolic"
            onTriggered: root.toggle("dock", appMenu.appId)
        }
    }
}
