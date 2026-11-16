import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import "i18n.js" as I18n

Item {
    id: editRoot

    function i18n(k, a1, a2) { return I18n.t(k, a1, a2); }

    property var fullRep: null
    property int selectedTileIndex: -1

    // Drag & drop reordering state (the move is committed on release, so the
    // Repeater is not rebuilt under the cursor while dragging)
    property int dragFromIndex: -1
    property int dropTargetIndex: -1

    // Custom tile creator
    property bool creatingTile: false

    // M3 shared-axis transition between "Edit tiles" and "New tile"
    property real switchT: 1.0
    readonly property real switchEased: 1 - Math.pow(1 - switchT, 4)
    NumberAnimation { id: switchAnim; target: editRoot; property: "switchT"; from: 0; to: 1; duration: 520 }
    onCreatingTileChanged: switchAnim.restart()
    property string newTileName: ""
    property string newTileCommand: ""
    property string newTileIcon: "system-run-symbolic"

    readonly property real dpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1.0
    function snap(val) {
        return Math.round(val * dpr) / dpr;
    }

    readonly property string appFontFamily: "Google Sans Flex"
    readonly property color accent: fullRep ? fullRep.effectiveAccentColor : Kirigami.Theme.highlightColor
    readonly property color onAccent: (accent.r * 0.299 + accent.g * 0.587 + accent.b * 0.114) > 0.6 ? "#111827" : Kirigami.Theme.highlightedTextColor
    readonly property color trackBg: fullRep ? fullRep.oneUiTrackBg : Kirigami.Theme.alternateBackgroundColor
    function textAlpha(a) {
        return Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, a);
    }

    implicitHeight: editHeader.height + editScroll.anchors.topMargin + editCol.implicitHeight + snap(16.0)

    signal closeRequested()

    // ---------------------------------------------------------------- actions
    function removeTileAt(i) {
        if (!fullRep || !fullRep.activeTiles) return;
        if (i < 0 || i >= fullRep.activeTiles.length) return;
        var arr = fullRep.activeTiles.slice();
        arr.splice(i, 1);
        fullRep.activeTiles = arr;
        selectedTileIndex = -1;
        fullRep.saveActiveTiles();
    }

    function deleteSelected() {
        removeTileAt(selectedTileIndex);
    }

    function addTile(tileId) {
        if (!fullRep || !fullRep.activeTiles) return;
        if (fullRep.activeTiles.indexOf(tileId) !== -1) return;
        var arr = fullRep.activeTiles.slice();
        arr.push(tileId);
        fullRep.activeTiles = arr;
        if (fullRep.setTileSpan) {
            fullRep.setTileSpan(tileId, 2);
        }
        selectedTileIndex = arr.length - 1;
        fullRep.saveActiveTiles();
    }

    function resetTiles() {
        if (!fullRep || !fullRep.defaultTiles) return;
        fullRep.activeTiles = fullRep.defaultTiles.slice();
        fullRep.tileSpans = {};
        selectedTileIndex = -1;
        fullRep.saveActiveTiles();
    }

    function moveTile(fromIndex, toIndex) {
        if (!fullRep || !fullRep.activeTiles) return;
        if (fromIndex === toIndex) return;
        if (fromIndex < 0 || fromIndex >= fullRep.activeTiles.length) return;
        if (toIndex < 0 || toIndex >= fullRep.activeTiles.length) return;

        var arr = fullRep.activeTiles.slice();
        var item = arr.splice(fromIndex, 1)[0];
        arr.splice(toIndex, 0, item);
        fullRep.activeTiles = arr;
        selectedTileIndex = toIndex;
        fullRep.saveActiveTiles();
    }

    function openCreator() {
        newTileName = "";
        newTileCommand = "";
        newTileIcon = "system-run-symbolic";
        creatingTile = true;
        Qt.callLater(function() {
            nameField.forceActiveFocus();
            editScroll.contentY = Math.max(0, editScroll.contentHeight - editScroll.height);
        });
    }

    function createCustomTile() {
        var name = newTileName.trim();
        var cmd = newTileCommand.trim();
        if (!fullRep || name.length === 0 || cmd.length === 0) return;
        fullRep.addCustomTile(name, newTileIcon.trim(), cmd);
        selectedTileIndex = fullRep.activeTiles.length - 1;
        creatingTile = false;
        editScroll.contentY = 0;
    }

    readonly property var categories: [
        {
            id: "lacznosc",
            title: i18n("Connectivity"),
            icon: Qt.resolvedUrl("icons/wifi.svg"),
            tiles: [
                { id: "wifi", name: i18n("Wi-Fi"), icon: Qt.resolvedUrl("icons/wifi.svg") },
                { id: "bluetooth", name: i18n("Bluetooth"), icon: Qt.resolvedUrl("icons/bluetooth.svg") },
                { id: "airplane", name: i18n("Airplane mode"), icon: Qt.resolvedUrl("icons/airplane.svg") },
                { id: "quickshare", name: i18n("Quick Share"), icon: Qt.resolvedUrl("icons/quickshare.svg") }
            ]
        },
        {
            id: "system",
            title: i18n("System & power"),
            icon: Qt.resolvedUrl("icons/laptop_screen.svg"),
            tiles: [
                { id: "battery_saver", name: i18n("Power & battery"), icon: Qt.resolvedUrl("icons/battery_saver.svg") },
                { id: "dark_mode", name: i18n("Dark theme"), icon: Qt.resolvedUrl("icons/dark_mode.svg") },
                { id: "night_light", name: i18n("Night Light"), icon: Qt.resolvedUrl("icons/moon.svg") },
                { id: "modes", name: i18n("Do not disturb"), icon: Qt.resolvedUrl("icons/modes.svg") },
                { id: "caffeine", name: i18n("Stay awake"), icon: Qt.resolvedUrl("icons/coffee.svg") },
                { id: "game_mode", name: i18n("Game mode"), icon: Qt.resolvedUrl("icons/gamepad.svg") }
            ]
        },
        {
            id: "narzedzia",
            title: i18n("Tools"),
            icon: Qt.resolvedUrl("icons/settings.svg"),
            tiles: [
                { id: "screenshot", name: i18n("Screenshot"), icon: Qt.resolvedUrl("icons/screenshot.svg") },
                { id: "screen_record", name: i18n("Screen record"), icon: Qt.resolvedUrl("icons/screen_record.svg") },
                { id: "mic", name: i18n("Microphone access"), icon: Qt.resolvedUrl("icons/mic.svg") },
                { id: "clipboard", name: i18n("Clipboard"), icon: Qt.resolvedUrl("icons/clipboard.svg") },
                { id: "keyboard", name: i18n("Keyboard"), icon: Qt.resolvedUrl("icons/keyboard.svg") }
            ]
        }
    ]

    readonly property var iconSuggestions: [
        "system-run-symbolic", "utilities-terminal-symbolic", "folder-symbolic", "internet-web-browser-symbolic",
        "camera-photo-symbolic", "audio-headphones-symbolic", "applications-games-symbolic", "media-playback-start-symbolic",
        "mail-unread-symbolic", "starred-symbolic", "system-lock-screen-symbolic", "weather-clear-symbolic"
    ]

    // ------------------------------------------------------------------ header
    Rectangle {
        id: editHeader
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: snap(32.0)
        color: "transparent"
        z: 10

        Rectangle {
            id: backBtn
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: snap(32.0)
            height: snap(32.0)
            radius: snap(8.0)
            color: backMouse.pressed ? editRoot.textAlpha(0.18) : (backMouse.containsMouse ? editRoot.textAlpha(0.1) : "transparent")

            Kirigami.Icon {
                anchors.centerIn: parent
                width: snap(24.0)
                height: snap(24.0)
                source: Qt.resolvedUrl("icons/arrow_back.svg")
                isMask: true
                color: Kirigami.Theme.textColor
            }

            MouseArea {
                id: backMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    if (editRoot.creatingTile) {
                        editRoot.creatingTile = false;
                    } else {
                        editRoot.closeRequested();
                    }
                }
            }
        }

        PlasmaComponents3.Label {
            anchors.centerIn: parent
            text: editRoot.creatingTile ? i18n("New tile") : i18n("Edit tiles")
            font.family: editRoot.appFontFamily
            font.pixelSize: snap(13.6)
            font.weight: Font.DemiBold
            color: Kirigami.Theme.textColor
        }

        // "Remove" pill: only for an explicitly selected tile (used to silently drop the last tile)
        Rectangle {
            id: delBtn
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: snap(68.0)
            height: snap(30.4)
            radius: height / 2
            color: editRoot.accent
            visible: !editRoot.creatingTile

            readonly property bool canDelete: editRoot.selectedTileIndex >= 0
            opacity: canDelete ? (delMouse.pressed ? 0.75 : (delMouse.containsMouse ? 0.90 : 1.0)) : 0.35
            Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }

            PlasmaComponents3.Label {
                anchors.centerIn: parent
                text: i18n("Remove")
                font.family: editRoot.appFontFamily
                font.pixelSize: snap(10.4)
                font.weight: Font.DemiBold
                color: editRoot.onAccent
            }

            MouseArea {
                id: delMouse
                anchors.fill: parent
                enabled: delBtn.canDelete
                hoverEnabled: true
                onClicked: editRoot.deleteSelected()
            }
        }
    }

    // --------------------------------------------------------------- content
    Flickable {
        id: editScroll
        anchors.top: editHeader.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.topMargin: snap(9.6)
        contentWidth: width
        contentHeight: editCol.implicitHeight + snap(16.0)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: editRoot.dragFromIndex < 0
        Behavior on contentY { NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic } }

        PlasmaComponents3.ScrollBar.vertical: PlasmaComponents3.ScrollBar { }

        WheelHandler {
            target: editScroll
        }

        ColumnLayout {
            opacity: Math.min(1, editRoot.switchT * 1.6)
            transform: Translate { x: (1 - editRoot.switchEased) * snap(48) * (editRoot.creatingTile ? 1 : -1) }
            id: editCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: snap(14.4)

            // 1. Active tiles (what is currently on the panel)
            Rectangle {
                id: activeTilesContainer
                Layout.fillWidth: true
                radius: snap(16.0)
                color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.45)
                border.width: snap(1.2)
                border.color: Qt.rgba(editRoot.accent.r, editRoot.accent.g, editRoot.accent.b, 0.4)
                implicitHeight: activeGrid.implicitHeight + snap(16.0)

                MouseArea {
                    anchors.fill: parent
                    z: -1
                    onClicked: editRoot.selectedTileIndex = -1
                }

                GridLayout {
                    id: activeGrid
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: snap(8.0)
                    columns: 4
                    rowSpacing: snap(7.2)
                    columnSpacing: snap(7.2)

                    Repeater {
                        model: fullRep ? fullRep.activeTiles : []

                        Rectangle {
                            id: tileItem
                            required property string modelData
                            required property int index
                            readonly property int tileIndex: index

                            readonly property int span: fullRep ? fullRep.getTileSpan(modelData) : 2
                            readonly property bool isCompact: span === 1
                            readonly property bool isSelected: editRoot.selectedTileIndex === index
                            readonly property bool isDragged: editRoot.dragFromIndex === index
                            readonly property bool isDropTarget: editRoot.dropTargetIndex === index && editRoot.dragFromIndex !== index

                            Layout.columnSpan: span
                            Layout.fillWidth: true
                            Layout.preferredWidth: isCompact ? snap(68.0) : snap(143.2)
                            Layout.preferredHeight: snap(49.6)
                            radius: snap(14.4)
                            color: isDropTarget ? Qt.rgba(editRoot.accent.r, editRoot.accent.g, editRoot.accent.b, 0.28) : editRoot.trackBg
                            Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }
                            border.width: (isSelected || isDropTarget) ? snap(1.6) : 0
                            border.color: editRoot.accent

                            z: isDragged ? 50 : 1
                            scale: isDragged ? 1.06 : 1.0
                            opacity: isDragged ? 0.92 : 1.0
                            Behavior on scale { NumberAnimation { duration: Kirigami.Units.shortDuration; easing.type: Easing.OutCubic } }
                            transform: Translate { id: dragShift; x: 0; y: 0 }

                            // Resize handle (1 segment <-> 2 segments) on the selected tile
                            Rectangle {
                                id: selHandle
                                visible: tileItem.isSelected
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.right: parent.right
                                anchors.rightMargin: snap(2.4)
                                width: snap(16.0)
                                height: snap(28.8)
                                radius: snap(6.0)
                                color: editRoot.accent
                                z: 10

                                Kirigami.Icon {
                                    anchors.centerIn: parent
                                    width: snap(12.0)
                                    height: snap(12.0)
                                    source: Qt.resolvedUrl("icons/arrow_right.svg")
                                    rotation: tileItem.isCompact ? 0 : 180
                                    isMask: true
                                    color: editRoot.onAccent
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -snap(6.4)
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: fullRep.setTileSpan(tileItem.modelData, tileItem.span === 2 ? 1 : 2)
                                }
                            }

                            // Android-style "–" badge: remove this tile in one click
                            Rectangle {
                                id: removeBadge
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.topMargin: -snap(4.0)
                                anchors.leftMargin: -snap(4.0)
                                width: snap(18.0)
                                height: width
                                radius: width / 2
                                z: 11
                                visible: !tileItem.isDragged
                                color: removeMouse.containsMouse ? Kirigami.Theme.negativeTextColor : editRoot.accent
                                Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }

                                Kirigami.Icon {
                                    anchors.centerIn: parent
                                    width: snap(12.0)
                                    height: width
                                    source: Qt.resolvedUrl("icons/remove.svg")
                                    isMask: true
                                    color: removeMouse.containsMouse ? "#ffffff" : editRoot.onAccent
                                }

                                MouseArea {
                                    id: removeMouse
                                    anchors.fill: parent
                                    anchors.margins: -snap(3.0)
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: editRoot.removeTileAt(tileItem.index)
                                }
                            }

                            Kirigami.Icon {
                                visible: tileItem.isCompact
                                anchors.centerIn: parent
                                width: snap(20.8)
                                height: width
                                source: fullRep ? fullRep.getTileIcon(tileItem.modelData) : ""
                                isMask: fullRep ? fullRep.tileIconIsMask(tileItem.modelData) : true
                                color: Kirigami.Theme.textColor
                            }

                            RowLayout {
                                visible: !tileItem.isCompact
                                anchors.fill: parent
                                anchors.leftMargin: snap(10.0)
                                anchors.rightMargin: tileItem.isSelected ? snap(20.0) : snap(8.0)
                                spacing: snap(8.0)

                                Kirigami.Icon {
                                    Layout.alignment: Qt.AlignVCenter
                                    Layout.preferredWidth: snap(19.2)
                                    Layout.preferredHeight: snap(19.2)
                                    source: fullRep ? fullRep.getTileIcon(tileItem.modelData) : ""
                                    isMask: fullRep ? fullRep.tileIconIsMask(tileItem.modelData) : true
                                    color: Kirigami.Theme.textColor
                                }

                                PlasmaComponents3.Label {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    text: fullRep ? fullRep.getTileTitle(tileItem.modelData) : tileItem.modelData
                                    font.family: editRoot.appFontFamily
                                    font.pixelSize: snap(11.2)
                                    font.weight: Font.DemiBold
                                    color: Kirigami.Theme.textColor
                                    elide: Text.ElideRight
                                }
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: parent.radius
                                color: Kirigami.Theme.textColor
                                opacity: tileMouse.pressed ? 0.14 : (tileMouse.containsMouse ? 0.06 : 0)
                            }

                            MouseArea {
                                id: tileMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: editRoot.dragFromIndex >= 0 ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                preventStealing: true
                                property real startX: 0
                                property real startY: 0

                                onPressed: (mouse) => {
                                    startX = mouse.x;
                                    startY = mouse.y;
                                }

                                onPositionChanged: (mouse) => {
                                    if (!pressed) return;
                                    var dx = mouse.x - startX;
                                    var dy = mouse.y - startY;
                                    if (editRoot.dragFromIndex < 0 && (Math.abs(dx) > 8 || Math.abs(dy) > 8)) {
                                        editRoot.dragFromIndex = tileItem.index;
                                        editRoot.selectedTileIndex = -1;
                                    }
                                    if (editRoot.dragFromIndex === tileItem.index) {
                                        dragShift.x = dx;
                                        dragShift.y = dy;
                                        // Hit-test the grid under the cursor (works with mixed 1/2-segment tiles)
                                        var p = mapToItem(activeGrid, mouse.x, mouse.y);
                                        var target = -1;
                                        for (var i = 0; i < activeGrid.children.length; i++) {
                                            var c = activeGrid.children[i];
                                            if (c === tileItem || c.tileIndex === undefined || !c.visible) continue;
                                            if (p.x >= c.x && p.x <= c.x + c.width && p.y >= c.y && p.y <= c.y + c.height) {
                                                target = c.tileIndex;
                                                break;
                                            }
                                        }
                                        editRoot.dropTargetIndex = target;
                                    }
                                }

                                onReleased: {
                                    if (editRoot.dragFromIndex === tileItem.index) {
                                        var from = editRoot.dragFromIndex;
                                        var to = editRoot.dropTargetIndex;
                                        dragShift.x = 0;
                                        dragShift.y = 0;
                                        editRoot.dragFromIndex = -1;
                                        editRoot.dropTargetIndex = -1;
                                        if (to >= 0 && to !== from) {
                                            editRoot.moveTile(from, to);
                                        }
                                    }
                                }

                                onCanceled: {
                                    dragShift.x = 0;
                                    dragShift.y = 0;
                                    editRoot.dragFromIndex = -1;
                                    editRoot.dropTargetIndex = -1;
                                }

                                onClicked: {
                                    if (editRoot.dragFromIndex >= 0) return;
                                    editRoot.selectedTileIndex = (editRoot.selectedTileIndex === tileItem.index) ? -1 : tileItem.index;
                                }
                            }
                        }
                    }
                }
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                Layout.topMargin: -snap(6.0)
                horizontalAlignment: Text.AlignHCenter
                text: i18n("Drag to reorder · select a tile to resize it")
                font.family: editRoot.appFontFamily
                font.pixelSize: snap(9.2)
                color: Kirigami.Theme.disabledTextColor
                wrapMode: Text.Wrap
            }

            // Reusable circular "available tile" button
            component AvailableTile: Item {
                id: avail
                property string tileId: ""
                property string label: ""
                property string iconSource: ""
                property bool iconIsMask: true
                property bool deletable: false
                readonly property bool isAdded: editRoot.fullRep && editRoot.fullRep.activeTiles ? (editRoot.fullRep.activeTiles.indexOf(tileId) !== -1) : false
                signal deleteRequested()

                Layout.fillWidth: true
                implicitHeight: editRoot.snap(70.4)

                ColumnLayout {
                    anchors.centerIn: parent
                    width: parent.width
                    spacing: editRoot.snap(4.8)

                    Item {
                        Layout.alignment: Qt.AlignHCenter
                        width: editRoot.snap(44.8)
                        height: editRoot.snap(44.8)

                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: editRoot.trackBg
                            opacity: avail.isAdded ? 0.35 : 1.0
                            scale: circArea.pressed && !avail.isAdded ? 0.92 : 1.0
                            Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }
                            Behavior on scale { NumberAnimation { duration: Kirigami.Units.shortDuration; easing.type: Easing.OutCubic } }

                            Kirigami.Icon {
                                anchors.centerIn: parent
                                width: editRoot.snap(20.8)
                                height: editRoot.snap(20.8)
                                source: avail.iconSource
                                isMask: avail.iconIsMask
                                color: Kirigami.Theme.textColor
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: parent.radius
                                color: Kirigami.Theme.textColor
                                opacity: (!avail.isAdded && circArea.pressed) ? 0.22 : ((!avail.isAdded && circArea.containsMouse) ? 0.10 : 0)
                            }
                        }

                        // "+" badge (top-right) while not on the panel
                        Rectangle {
                            visible: !avail.isAdded
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.topMargin: -editRoot.snap(1.6)
                            anchors.rightMargin: -editRoot.snap(1.6)
                            width: editRoot.snap(16.0)
                            height: editRoot.snap(16.0)
                            radius: width / 2
                            color: editRoot.accent
                            z: 2

                            Kirigami.Icon {
                                anchors.centerIn: parent
                                width: editRoot.snap(11.0)
                                height: width
                                source: Qt.resolvedUrl("icons/add.svg")
                                isMask: true
                                color: editRoot.onAccent
                            }
                        }

                        // Delete badge (top-left) for user-defined tiles
                        Rectangle {
                            visible: avail.deletable
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.topMargin: -editRoot.snap(1.6)
                            anchors.leftMargin: -editRoot.snap(1.6)
                            width: editRoot.snap(16.0)
                            height: editRoot.snap(16.0)
                            radius: width / 2
                            color: delCustomMouse.containsMouse ? Kirigami.Theme.negativeTextColor : editRoot.textAlpha(0.25)
                            z: 3

                            Kirigami.Icon {
                                anchors.centerIn: parent
                                width: editRoot.snap(10.0)
                                height: width
                                source: Qt.resolvedUrl("icons/delete.svg")
                                isMask: true
                                color: delCustomMouse.containsMouse ? "#ffffff" : Kirigami.Theme.textColor
                            }

                            MouseArea {
                                id: delCustomMouse
                                anchors.fill: parent
                                anchors.margins: -editRoot.snap(3.0)
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: avail.deleteRequested()
                            }
                        }

                        MouseArea {
                            id: circArea
                            anchors.fill: parent
                            hoverEnabled: !avail.isAdded
                            cursorShape: avail.isAdded ? Qt.ArrowCursor : Qt.PointingHandCursor
                            onClicked: {
                                if (!avail.isAdded) {
                                    editRoot.addTile(avail.tileId);
                                }
                            }
                        }
                    }

                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: avail.label
                        font.family: editRoot.appFontFamily
                        font.pixelSize: editRoot.snap(8.8)
                        color: Kirigami.Theme.textColor
                        opacity: avail.isAdded ? 0.35 : 1.0
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        lineHeight: 0.95
                    }
                }
            }

            component CategoryTitle: RowLayout {
                id: catTitle
                property string title: ""
                property string iconSource: ""
                spacing: editRoot.snap(6.4)
                Layout.fillWidth: true

                Kirigami.Icon {
                    Layout.preferredWidth: editRoot.snap(16.0)
                    Layout.preferredHeight: editRoot.snap(16.0)
                    source: catTitle.iconSource
                    isMask: true
                    color: Kirigami.Theme.textColor
                }

                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    text: catTitle.title
                    font.family: editRoot.appFontFamily
                    font.pixelSize: editRoot.snap(12.0)
                    font.weight: Font.DemiBold
                    color: Kirigami.Theme.textColor
                }
            }

            // 2. Built-in tile catalogue
            Repeater {
                model: editRoot.creatingTile ? [] : editRoot.categories

                ColumnLayout {
                    id: catCol
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: snap(9.6)

                    CategoryTitle {
                        title: catCol.modelData.title
                        iconSource: catCol.modelData.icon
                    }

                    GridLayout {
                        columns: 4
                        Layout.fillWidth: true
                        rowSpacing: snap(11.2)
                        columnSpacing: snap(4.8)

                        Repeater {
                            model: catCol.modelData.tiles

                            AvailableTile {
                                required property var modelData
                                tileId: modelData.id
                                label: modelData.name
                                iconSource: modelData.icon
                            }
                        }
                    }
                }
            }

            // 3. "My tiles": user-defined shortcuts + creator
            ColumnLayout {
                Layout.fillWidth: true
                spacing: snap(9.6)
                visible: !editRoot.creatingTile

                CategoryTitle {
                    title: i18n("My tiles")
                    iconSource: Qt.resolvedUrl("icons/touch.svg")
                }

                GridLayout {
                    columns: 4
                    Layout.fillWidth: true
                    rowSpacing: snap(11.2)
                    columnSpacing: snap(4.8)

                    Repeater {
                        model: fullRep ? fullRep.customTiles : []

                        AvailableTile {
                            required property var modelData
                            tileId: modelData.id
                            label: modelData.name
                            iconSource: modelData.icon.length > 0 ? modelData.icon : Qt.resolvedUrl("icons/touch.svg")
                            iconIsMask: fullRep ? fullRep.tileIconIsMask(modelData.id) : true
                            deletable: true
                            onDeleteRequested: {
                                editRoot.selectedTileIndex = -1;
                                fullRep.removeCustomTile(modelData.id);
                            }
                        }
                    }

                    // "Create tile" button
                    Item {
                        Layout.fillWidth: true
                        implicitHeight: snap(70.4)

                        ColumnLayout {
                            anchors.centerIn: parent
                            width: parent.width
                            spacing: snap(4.8)

                            Rectangle {
                                Layout.alignment: Qt.AlignHCenter
                                width: snap(44.8)
                                height: snap(44.8)
                                radius: width / 2
                                color: createMouse.containsMouse ? Qt.rgba(editRoot.accent.r, editRoot.accent.g, editRoot.accent.b, 0.22) : "transparent"
                                border.width: snap(1.2)
                                border.color: Qt.rgba(editRoot.accent.r, editRoot.accent.g, editRoot.accent.b, 0.8)
                                scale: createMouse.pressed ? 0.92 : 1.0
                                Behavior on scale { NumberAnimation { duration: Kirigami.Units.shortDuration; easing.type: Easing.OutCubic } }
                                Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }

                                Kirigami.Icon {
                                    anchors.centerIn: parent
                                    width: snap(20.8)
                                    height: width
                                    source: Qt.resolvedUrl("icons/add.svg")
                                    isMask: true
                                    color: editRoot.accent
                                }

                                MouseArea {
                                    id: createMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: editRoot.openCreator()
                                }
                            }

                            PlasmaComponents3.Label {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: i18n("Create tile")
                                font.family: editRoot.appFontFamily
                                font.pixelSize: snap(8.8)
                                color: Kirigami.Theme.textColor
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                            }
                        }
                    }
                }
            }

            // 4. Custom tile creator (inline card)
            Rectangle {
                id: creatorCard
                visible: editRoot.creatingTile
                Layout.fillWidth: true
                radius: snap(16.0)
                color: editRoot.trackBg
                implicitHeight: creatorCol.implicitHeight + snap(24.0)

                ColumnLayout {
                    id: creatorCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: snap(12.0)
                    spacing: snap(9.6)

                    // Live preview, exactly as it will appear on the panel
                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: snap(151.2)
                        Layout.preferredHeight: snap(50.4)
                        radius: height / 2
                        color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.6)

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: snap(12.0)
                            anchors.rightMargin: snap(12.0)
                            spacing: snap(9.6)

                            Kirigami.Icon {
                                Layout.preferredWidth: snap(19.2)
                                Layout.preferredHeight: snap(19.2)
                                source: editRoot.newTileIcon.length > 0 ? editRoot.newTileIcon : Qt.resolvedUrl("icons/touch.svg")
                                isMask: editRoot.newTileIcon.length === 0 || /-symbolic$/.test(editRoot.newTileIcon)
                                color: Kirigami.Theme.textColor
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                PlasmaComponents3.Label {
                                    Layout.fillWidth: true
                                    text: editRoot.newTileName.length > 0 ? editRoot.newTileName : i18n("Tile name")
                                    opacity: editRoot.newTileName.length > 0 ? 1.0 : 0.5
                                    font.family: editRoot.appFontFamily
                                    font.pixelSize: snap(12.4)
                                    font.weight: Font.Medium
                                    elide: Text.ElideRight
                                }
                                PlasmaComponents3.Label {
                                    Layout.fillWidth: true
                                    text: i18n("Shortcut")
                                    font.family: editRoot.appFontFamily
                                    font.pixelSize: snap(9.6)
                                    color: Kirigami.Theme.disabledTextColor
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }

                    PlasmaComponents3.Label {
                        text: i18n("Name")
                        font.family: editRoot.appFontFamily
                        font.pixelSize: snap(10.4)
                        font.weight: Font.Medium
                    }
                    PlasmaComponents3.TextField {
                        id: nameField
                        Layout.fillWidth: true
                        placeholderText: i18n("e.g. Terminal")
                        text: editRoot.newTileName
                        onTextChanged: editRoot.newTileName = text
                        onAccepted: commandField.forceActiveFocus()
                    }

                    PlasmaComponents3.Label {
                        text: i18n("Command")
                        font.family: editRoot.appFontFamily
                        font.pixelSize: snap(10.4)
                        font.weight: Font.Medium
                    }
                    PlasmaComponents3.TextField {
                        id: commandField
                        Layout.fillWidth: true
                        placeholderText: i18n("e.g. konsole, firefox, dolphin ~/Downloads")
                        text: editRoot.newTileCommand
                        onTextChanged: editRoot.newTileCommand = text
                        onAccepted: editRoot.createCustomTile()
                    }

                    PlasmaComponents3.Label {
                        text: i18n("Icon")
                        font.family: editRoot.appFontFamily
                        font.pixelSize: snap(10.4)
                        font.weight: Font.Medium
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 6
                        rowSpacing: snap(6.4)
                        columnSpacing: snap(6.4)

                        Repeater {
                            model: editRoot.iconSuggestions

                            Rectangle {
                                required property string modelData
                                readonly property bool chosen: editRoot.newTileIcon === modelData
                                Layout.alignment: Qt.AlignHCenter
                                width: snap(36.0)
                                height: width
                                radius: chosen ? snap(12.0) : width / 2
                                color: chosen ? editRoot.accent : (iconPickMouse.containsMouse ? editRoot.textAlpha(0.12) : "transparent")
                                Behavior on radius { NumberAnimation { duration: Kirigami.Units.shortDuration; easing.type: Easing.OutCubic } }
                                Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }

                                Kirigami.Icon {
                                    anchors.centerIn: parent
                                    width: snap(18.0)
                                    height: width
                                    source: parent.modelData
                                    isMask: true
                                    color: parent.chosen ? editRoot.onAccent : Kirigami.Theme.textColor
                                }

                                MouseArea {
                                    id: iconPickMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        editRoot.newTileIcon = parent.modelData;
                                        iconField.text = parent.modelData;
                                    }
                                }
                            }
                        }
                    }

                    PlasmaComponents3.TextField {
                        id: iconField
                        Layout.fillWidth: true
                        placeholderText: i18n("…or any icon name (e.g. firefox)")
                        text: editRoot.newTileIcon
                        onTextChanged: editRoot.newTileIcon = text
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: snap(4.0)
                        spacing: snap(8.0)

                        Item { Layout.fillWidth: true }

                        PlasmaComponents3.Button {
                            text: i18n("Cancel")
                            onClicked: editRoot.creatingTile = false
                        }

                        PlasmaComponents3.Button {
                            text: i18n("Add")
                            icon.name: "list-add"
                            enabled: editRoot.newTileName.trim().length > 0 && editRoot.newTileCommand.trim().length > 0
                            onClicked: editRoot.createCustomTile()
                        }
                    }
                }
            }

            // 5. Reset
            Item {
                visible: !editRoot.creatingTile
                Layout.fillWidth: true
                Layout.preferredHeight: snap(40.0)
                Layout.topMargin: snap(8.0)
                Layout.bottomMargin: snap(19.2)

                Rectangle {
                    anchors.centerIn: parent
                    implicitWidth: snap(88.0)
                    implicitHeight: snap(30.4)
                    radius: height / 2
                    color: editRoot.accent
                    opacity: resetArea.pressed ? 0.75 : (resetArea.containsMouse ? 0.90 : 1.0)
                    Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }

                    PlasmaComponents3.Label {
                        anchors.centerIn: parent
                        text: i18n("Reset")
                        font.family: editRoot.appFontFamily
                        font.pixelSize: snap(10.4)
                        font.weight: Font.DemiBold
                        color: editRoot.onAccent
                    }

                    MouseArea {
                        id: resetArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: editRoot.resetTiles()
                    }
                }
            }
        }
    }
}
