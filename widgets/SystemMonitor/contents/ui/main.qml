/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * DoodlebookOS Système: values are pushed by the ksystemstats daemon (no polling here), throttled
 * to one update every 2 s (temperatures every 4 s).
 */
import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.ksysguard.sensors as Sensors

PlasmoidItem {
    id: root
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    preferredRepresentation: fullRepresentation

    Sensors.Sensor { id: sCpu; sensorId: "cpu/all/usage"; updateRateLimit: 2000 }
    Sensors.Sensor { id: sRam; sensorId: "memory/physical/usedPercent"; updateRateLimit: 2000 }
    Sensors.Sensor { id: sRamUsed; sensorId: "memory/physical/used"; updateRateLimit: 4000 }
    // gpu/all averages with an idle iGPU, so show the busiest GPU instead
    Sensors.Sensor { id: sGpu0; sensorId: "gpu/gpu0/usage"; updateRateLimit: 2000 }
    Sensors.Sensor { id: sGpu1; sensorId: "gpu/gpu1/usage"; updateRateLimit: 2000 }
    Sensors.Sensor { id: sCpuTemp; sensorId: "cpu/all/averageTemperature"; updateRateLimit: 4000 }
    Sensors.Sensor { id: sGpuTemp0; sensorId: "gpu/gpu0/temperature"; updateRateLimit: 4000 }
    Sensors.Sensor { id: sGpuTemp1; sensorId: "gpu/gpu1/temperature"; updateRateLimit: 4000 }

    function num(v) { var n = Number(v); return isFinite(n) ? n : 0; }

    fullRepresentation: SysCard {
        cpu: root.num(sCpu.value)
        ram: root.num(sRam.value)
        gpu: Math.max(root.num(sGpu0.value), root.num(sGpu1.value))
        cpuTemp: root.num(sCpuTemp.value)
        gpuTemp: Math.max(root.num(sGpuTemp0.value), root.num(sGpuTemp1.value))
        ramUsedBytes: root.num(sRamUsed.value)
    }
}
