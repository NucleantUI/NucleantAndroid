package org.nucleantui.devicelab

import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.SeekBar
import android.widget.TextView
import org.nucleantui.devicelab.bridge.DeviceLabBridge
import org.nucleantui.devicelab.bridge.LabBattery
import org.nucleantui.devicelab.bridge.LabDevice
import org.nucleantui.devicelab.bridge.LabFlashlight
import org.nucleantui.devicelab.bridge.LabSensor
import org.nucleantui.devicelab.bridge.LabSensors
import org.nucleantui.devicelab.bridge.LabVibrator

// ── AndroidDevice ────────────────────────────────────────────────────────────

class DeviceSection(private val activity: MainActivity) : Section {
    override val title = "Device"
    private lateinit var device: LabDevice
    private lateinit var memory: TextView
    private lateinit var keepOn: Button
    private lateinit var brightness: TextView
    private lateinit var slider: SeekBar

    override fun build(ui: Ui): View = with(ui) {
        device = LabDevice.init(activity.arena)
        card(title) {
            label("${device.manufacturer} ${device.model} — ${device.brand} ${device.deviceName}")
            label("Android ${device.release} · API ${device.sdkLevel}" + if (device.isEmulator) " · emulator" else "")
            label("ABIs: ${device.supportedABIs.joinToString()}", secondary = true)
            label(
                "Screen ${device.screenWidth}×${device.screenHeight} px · ${device.screenDPI} dpi · " +
                    "density ${"%.2f".format(device.screenDensity)}",
                secondary = true,
            )
            memory = label(secondary = true)
            row {
                keepOn = button("") { device.setKeepsScreenOn(!device.isKeepsScreenOn) }
                button("Refresh memory") { device.refresh() }
            }
            brightness = label()
            slider = slider("Brightness", 100, 50) { device.setScreenBrightness(it / 100.0) }
            button("Follow system brightness") { device.setScreenBrightness(-1.0) }
            label(device.fingerprint, secondary = true, monospace = true).textSize = 11f
            device.observe(Runnable { update() })
            update()
        }
    }

    private fun update() {
        val gb = 1024.0 * 1024 * 1024
        memory.text = "Memory: %.1f of %.1f GB available".format(device.availableMemory / gb, device.totalMemory / gb) +
            if (device.isLowOnMemory) " · LOW" else ""
        keepOn.text = if (device.isKeepsScreenOn) "Let the screen sleep" else "Keep the screen on"
        val value = device.screenBrightness
        brightness.text = if (value < 0) "Brightness: follows the system" else "Brightness: ${(value * 100).toInt()}% (this window)"
        if (value >= 0) slider.progress = (value * 100).toInt()
    }

    override fun onResume() {
        device.refresh()
    }
}

// ── AndroidFlashlight ────────────────────────────────────────────────────────

class FlashlightSection(private val activity: MainActivity) : Section {
    override val title = "Flashlight"
    private var light: LabFlashlight? = null
    private lateinit var status: TextView
    private lateinit var toggle: Button
    private lateinit var brightness: SeekBar

    override fun build(ui: Ui): View = with(ui) {
        card(title) {
            status = label()
            toggle = button("Turn on") {
                try {
                    light?.let { if (it.isOn) it.turnOff() else it.turnOn(brightness.progress / 100.0) }
                } catch (e: Exception) {
                    status.showError("Flashlight failed", e)
                }
            }
            brightness = slider("Brightness", 100, 100) { progress ->
                light?.takeIf { it.isOn }?.let { runCatching { it.turnOn(maxOf(progress, 1) / 100.0) } }
            }
            hint("Follows the torch however it is switched — try the quick-settings flashlight tile. Recent emulator images emulate a torch with brightness levels.")

            light = DeviceLabBridge.makeFlashlight(activity.arena).orElse(null)
            val light = light
            if (light == null) {
                status.text = "This device has no flash unit."
                toggle.isEnabled = false
                (brightness.parent as View).shown(false)
            } else {
                (brightness.parent as View).shown(light.isSupportsBrightness)
                light.observe(Runnable { update() })
                update()
            }
        }
    }

    private fun update() {
        val light = light ?: return
        val levels = if (light.isSupportsBrightness) "${light.maximumLevel} brightness levels" else "on/off only"
        status.text = when {
            !light.isAvailable -> "Flash of camera ${light.cameraID} · in use by another app"
            else -> "Flash of camera ${light.cameraID} · $levels · " +
                if (light.isOn) "on at level ${light.level}" else "off"
        }
        toggle.text = if (light.isOn) "Turn off" else "Turn on"
        toggle.isEnabled = light.isAvailable
        if (light.isSupportsBrightness) brightness.progress = light.level * 100 / maxOf(light.maximumLevel, 1)
    }
}

// ── AndroidHaptics ───────────────────────────────────────────────────────────

class HapticsSection(private val activity: MainActivity) : Section {
    override val title = "Haptics"

    override fun build(ui: Ui): View = with(ui) {
        val vibrator = LabVibrator.init(activity.arena)
        card(title) {
            label(
                (if (vibrator.isHasVibrator) "Has a vibrator" else "No vibrator") + " · " +
                    if (vibrator.isHasAmplitudeControl) "intensity control" else "on/off only",
            )
            var intensity = 1.0
            if (vibrator.isHasAmplitudeControl) {
                slider("Intensity", 100, 100) { intensity = maxOf(it, 1) / 100.0 }
            }
            val status = label(secondary = true)
            fun attempt(block: () -> Unit) = try { block() } catch (e: Exception) { status.showError("Vibration failed", e) }
            row {
                button("Tap 40 ms") { attempt { vibrator.vibrate(40, intensity) } }
                button("Buzz 400 ms") { attempt { vibrator.vibrate(400, intensity) } }
            }
            row {
                button("Heartbeat") {
                    attempt {
                        vibrator.vibratePattern(longArrayOf(60, 120, 60, 700), doubleArrayOf(intensity, 0.0, intensity * 0.6, 0.0), true)
                    }
                }
                button("Stop") { vibrator.cancel() }
            }
            label("Standard feedback (follows the system's touch-feedback setting):")
            for (chunk in vibrator.feedbackNames.toList().chunked(3)) {
                row {
                    for (name in chunk) {
                        button(name) {
                            attempt { if (!vibrator.performFeedback(name)) status.text = "The system skipped '$name' (touch feedback off?)" }
                        }
                    }
                }
            }
            label("System effects (✓ tuned for this device, ≈ approximated):")
            for (chunk in vibrator.effectNames.toList().chunked(2)) {
                row {
                    for (name in chunk) {
                        val mark = when (vibrator.effectSupport(name)) { 1 -> " ✓"; 0 -> " ≈"; else -> "" }
                        button(name + mark) { attempt { vibrator.playEffect(name) } }
                    }
                }
            }
            hint("The emulator accepts every vibration but has no motor: `adb logcat | grep -i vibrat` shows them arrive.")
        }
    }
}

// ── AndroidBattery ───────────────────────────────────────────────────────────

class BatterySection(private val activity: MainActivity) : Section {
    override val title = "Battery"
    private lateinit var battery: LabBattery
    private lateinit var level: TextView
    private lateinit var details: TextView

    override fun build(ui: Ui): View = with(ui) {
        battery = LabBattery.init(activity.arena)
        card(title) {
            level = label().apply { textSize = 28f }
            details = label(secondary = true)
            hint("Live from Android's battery broadcast. On the emulator: Extended controls → Battery, or `adb emu power capacity 30` / `adb emu power ac off`.")
            battery.observe(Runnable { update() })
            update()
        }
    }

    private fun update() {
        val percent = battery.level.let { if (it.isNaN()) "—" else "${(it * 100).toInt()}%" }
        level.text = "$percent " + if (battery.isCharging) "⚡" else ""
        details.text = listOf(
            "State: ${battery.state}",
            "Power: ${battery.powerSource}",
            "Health: ${battery.health}",
            "Temperature: ${battery.temperature.orDash("%.1f °C")}",
            "Voltage: ${battery.voltage.orDash("%.2f V")}",
            "Technology: ${battery.technology.ifEmpty { "—" }}",
            "Battery saver: ${if (battery.isPowerSaveMode) "on" else "off"}",
        ).joinToString("\n")
    }
}

// ── AndroidSensors ───────────────────────────────────────────────────────────

class SensorsSection(private val activity: MainActivity) : Section {
    override val title = "Sensors"
    private var rate = "ui"

    override fun build(ui: Ui): View = with(ui) {
        val sensors = LabSensors.init(activity.arena).getAll(activity.arena)
        card(title) {
            label("${sensors.size} sensors. Tap one to start or stop its readings, at:")
            addView(RadioGroup(activity).apply {
                orientation = RadioGroup.HORIZONTAL
                for (choice in listOf("normal", "ui", "game", "fastest")) {
                    addView(RadioButton(activity).apply {
                        id = View.generateViewId()
                        text = choice
                        isChecked = choice == rate
                        setOnClickListener { rate = choice }
                    })
                }
            })
            for (sensor in sensors) {
                addView(sensorRow(ui, sensor))
            }
            hint("On the emulator they are virtual: Extended controls → Virtual sensors moves the device and changes light, pressure, proximity…")
        }
    }

    private fun sensorRow(ui: Ui, sensor: LabSensor): View = with(ui) {
        LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, dp(6), 0, dp(6))
            val name = label(sensor.name)
            label(
                "${sensor.typeName.removePrefix("android.sensor.")} · range ${sensor.maximumRange} ${sensor.unit} · " +
                    "${sensor.power} mA · ${sensor.vendor}",
                secondary = true,
            ).textSize = 12f
            val reading = label(monospace = true).apply { shown(false) }
            setOnClickListener {
                if (sensor.isRunning) {
                    sensor.stopObserving()
                    sensor.stop()
                    reading.shown(false)
                    name.text = sensor.name
                } else if (sensor.isNeedsPermission && !sensor.isAuthorized) {
                    reading.shown(true)
                    reading.text = "Needs the activity-recognition permission…"
                    sensor.requestAccess().onMain(activity) { granted, _ ->
                        reading.text = if (granted == true) "Allowed — tap again to start." else "Not allowed."
                    }
                } else {
                    val started = runCatching { sensor.start(rate) }.getOrDefault(false)
                    reading.shown(true)
                    if (!started) {
                        reading.text = "The sensor did not start."
                        return@setOnClickListener
                    }
                    name.text = "● ${sensor.name}"
                    reading.text = "Waiting for a reading…"
                    sensor.observe(Runnable {
                        val values = sensor.values.joinToString("  ") { "%.3f".format(it) }
                        reading.text = "$values ${sensor.unit}   (accuracy ${sensor.accuracy}, ${sensor.rate})"
                    })
                }
            }
        }
    }
}
