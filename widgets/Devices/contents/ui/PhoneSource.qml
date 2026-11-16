// SPDX-License-Identifier: GPL-3.0-or-later
// KDE Connect phones with a battery, for main.qml (kept apart so a missing KDE Connect only hides phones).
import QtQuick
import org.kde.kdeconnect as KDEConnect

Item {
    id: src
    property var phones: []

    function rebuildPhones() {
        var out = [];
        for (var i = 0; i < phoneInst.count; i++) {
            var p = phoneInst.objectAt(i);
            if (!p || p.charge < 0) continue;
            out.push({ key: p.devId, name: p.devName, kind: p.devType === "tablet" ? "tablet" : "smartphone",
                       percent: p.charge, charging: p.charging, deviceId: p.devId });
        }
        if (JSON.stringify(out) !== JSON.stringify(phones)) phones = out;
    }

    Instantiator {
        id: phoneInst
        model: KDEConnect.DevicesModel {
            displayFilter: KDEConnect.DevicesModel.Paired | KDEConnect.DevicesModel.Reachable
        }
        delegate: QtObject {
            id: ph
            readonly property string devId: model.deviceId || ""
            readonly property KDEConnect.DeviceDbusInterface device: devId ? KDEConnect.DeviceDbusInterfaceFactory.create(devId) : null
            readonly property string devName: device && device.name ? String(device.name) : String(model.name || devId)
            readonly property string devType: device ? String(device.type || "") : ""
            readonly property KDEConnect.PluginChecker chk: KDEConnect.PluginChecker { pluginName: "battery"; device: ph.device }
            readonly property QtObject battery: chk.available ? KDEConnect.DeviceBatteryDbusInterfaceFactory.create(ph.devId) : null
            readonly property int charge: battery && battery.charge !== undefined ? battery.charge : -1
            readonly property bool charging: battery ? Boolean(battery.isCharging) : false
            onChargeChanged: Qt.callLater(src.rebuildPhones)
            onChargingChanged: Qt.callLater(src.rebuildPhones)
            onDevNameChanged: Qt.callLater(src.rebuildPhones)
        }
        onObjectAdded: Qt.callLater(src.rebuildPhones)
        onObjectRemoved: Qt.callLater(src.rebuildPhones)
    }
}
