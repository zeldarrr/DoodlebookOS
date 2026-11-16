/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: card
    property string dayKey: Qt.formatDate(new Date(), "yyyy-MM-dd")
    property int monthOffset: 0
    implicitWidth: 340
    implicitHeight: 340

    M3Colors { id: pal }

    readonly property var today: { var p = dayKey.split("-"); return new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2])); }
    readonly property var shown: new Date(today.getFullYear(), today.getMonth() + monthOffset, 1)
    readonly property int firstDay: Qt.locale().firstDayOfWeek   // 0 = Sunday … 6, Qt.Monday = 1
    readonly property string title: {
        var t = Qt.locale().standaloneMonthName(shown.getMonth(), Locale.LongFormat);
        return t.charAt(0).toUpperCase() + t.slice(1) + (shown.getFullYear() !== today.getFullYear() ? " " + shown.getFullYear() : "");
    }
    readonly property var cells: {
        var y = shown.getFullYear(), m = shown.getMonth();
        var lead = (new Date(y, m, 1).getDay() - firstDay + 7) % 7;
        var out = [];
        for (var i = 0; i < 42; i++) {
            var d = new Date(y, m, 1 - lead + i);
            out.push({ n: d.getDate(), inMonth: d.getMonth() === m,
                       isToday: d.getFullYear() === today.getFullYear() && d.getMonth() === today.getMonth() && d.getDate() === today.getDate(),
                       weekend: d.getDay() === 0 || d.getDay() === 6 });
        }
        return out;
    }
    readonly property int rows: cells[35].inMonth ? 6 : 5

    component NavBtn: Rectangle {
        id: nb
        property string icon: ""
        signal clicked()
        width: 36
        height: 36
        radius: 18
        color: nbMa.pressed ? pal.statePress : (nbMa.containsMouse ? pal.stateHover : "transparent")
        Kirigami.Icon { anchors.centerIn: parent; width: 18; height: 18; source: nb.icon; isMask: true; color: pal.surfaceTextVariant }
        MouseArea { id: nbMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: nb.clicked() }
    }

    Rectangle {
        anchors.fill: parent
        radius: 32
        color: pal.surface

        Item {
            id: header
            x: 20
            y: 14
            width: parent.width - 32
            height: 40
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: card.title
                font.family: pal.font
                font.pixelSize: 19
                font.weight: Font.DemiBold
                font.variableAxes: { "ROND": 100 }
                color: pal.surfaceText
                MouseArea { anchors.fill: parent; cursorShape: card.monthOffset !== 0 ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: card.monthOffset = 0 }
            }
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                NavBtn { icon: "go-previous"; onClicked: card.monthOffset-- }
                NavBtn { icon: "go-next"; onClicked: card.monthOffset++ }
            }
        }

        Grid {
            id: grid
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: header.bottom
            anchors.topMargin: 6
            columns: 7
            readonly property real cell: Math.floor((card.width - 28) / 7)

            Repeater {
                model: 7
                Text {
                    required property int index
                    width: grid.cell
                    height: 26
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: Qt.locale().dayName((card.firstDay + index) % 7, Locale.NarrowFormat).toUpperCase()
                    font.family: pal.font
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: pal.surfaceTextVariant
                }
            }
            Repeater {
                model: card.rows * 7
                Item {
                    id: day
                    required property int index
                    readonly property var c: card.cells[index]
                    width: grid.cell
                    height: Math.min(grid.cell, (card.height - 100) / card.rows)
                    Rectangle {
                        anchors.centerIn: parent
                        width: Math.min(parent.width, parent.height) - 4
                        height: width
                        radius: day.c.isToday ? width * 0.34 : width / 2   // today: M3 rounded "cookie" square
                        color: day.c.isToday ? pal.primary : "transparent"
                    }
                    Text {
                        anchors.centerIn: parent
                        text: day.c.n
                        font.family: pal.font
                        font.pixelSize: 14
                        font.weight: day.c.isToday ? Font.Bold : Font.Normal
                        color: day.c.isToday ? pal.primaryText
                             : !day.c.inMonth ? pal.alpha(pal.surfaceText, 0.3)
                             : day.c.weekend ? pal.tertiary : pal.surfaceText
                    }
                }
            }
        }
    }
}
