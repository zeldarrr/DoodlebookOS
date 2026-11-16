/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

Item {
    id: card
    property string initialText: ""
    signal save(string text)
    implicitWidth: 300
    implicitHeight: 220

    M3Colors { id: pal }

    // settings (Configurer… > Note / Apparence)
    readonly property var cfg: Plasmoid.configuration
    readonly property color bgColor: pal.container(cfg.colorRole, cfg.customColor)
    readonly property color fgColor: pal.onContainer(cfg.colorRole, cfg.customColor)
    readonly property real fs: (cfg.fontScale || 100) / 100
    readonly property int pad: cfg.padding || 20

    Timer { id: saveTimer; interval: 700; onTriggered: card.save(edit.text) }

    Rectangle {
        anchors.fill: parent
        radius: card.cfg.cornerRadius
        color: Qt.rgba(card.bgColor.r, card.bgColor.g, card.bgColor.b, card.cfg.bgOpacity / 100)
        border.width: card.cfg.outline ? 1 : 0
        border.color: pal.alpha(card.fgColor, 0.22)

        Kirigami.Icon {
            id: icon
            visible: card.cfg.showHeader
            x: card.pad
            y: Math.round(card.pad * 0.9)
            width: Math.round(20 * card.fs)
            height: width
            source: card.cfg.headerIcon.length > 0 ? card.cfg.headerIcon : "document-edit"
            isMask: true
            color: card.fgColor
        }
        Text {
            visible: card.cfg.showHeader
            anchors.left: icon.right
            anchors.leftMargin: 8
            anchors.verticalCenter: icon.verticalCenter
            text: card.cfg.headerText.length > 0 ? card.cfg.headerText : "Note"
            font.family: pal.font
            font.pixelSize: Math.round(15 * card.fs)
            font.weight: Font.DemiBold
            color: card.fgColor
        }

        Flickable {
            id: flick
            anchors.fill: parent
            anchors.topMargin: card.cfg.showHeader ? icon.y + icon.height + 12 : card.pad
            anchors.leftMargin: card.pad
            anchors.rightMargin: card.pad
            anchors.bottomMargin: Math.round(card.pad * 0.9)
            contentHeight: edit.contentHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height

            TextEdit {
                id: edit
                width: flick.width
                height: Math.max(flick.height, contentHeight)
                text: card.initialText
                wrapMode: TextEdit.Wrap
                selectByMouse: true
                horizontalAlignment: card.cfg.textAlign === "center" ? TextEdit.AlignHCenter
                                   : (card.cfg.textAlign === "right" ? TextEdit.AlignRight : TextEdit.AlignLeft)
                font.family: card.cfg.monospace ? "monospace" : pal.font
                font.pixelSize: Math.round(15 * card.fs)
                color: card.fgColor
                selectionColor: pal.alpha(card.fgColor, 0.25)
                selectedTextColor: card.fgColor
                persistentSelection: false
                onTextChanged: if (activeFocus) saveTimer.restart()
                onActiveFocusChanged: if (!activeFocus && saveTimer.running) { saveTimer.stop(); card.save(text); }
                onCursorRectangleChanged: {
                    var r = cursorRectangle;
                    if (r.y < flick.contentY) flick.contentY = r.y;
                    else if (r.y + r.height > flick.contentY + flick.height) flick.contentY = r.y + r.height - flick.height;
                }
                Text {
                    visible: edit.length === 0 && !edit.activeFocus
                    width: parent.width
                    horizontalAlignment: edit.horizontalAlignment
                    text: card.cfg.placeholder.length > 0 ? card.cfg.placeholder : "Écris quelque chose…"
                    font: edit.font
                    color: pal.alpha(card.fgColor, 0.55)
                }
            }
        }
    }
    Component.onDestruction: if (saveTimer.running) card.save(edit.text)
}
