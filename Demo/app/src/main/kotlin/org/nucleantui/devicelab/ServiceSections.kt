package org.nucleantui.devicelab

import android.view.View
import android.widget.Button
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.TextView
import org.nucleantui.devicelab.bridge.DeviceLabBridge
import org.nucleantui.devicelab.bridge.LabBiometrics
import org.nucleantui.devicelab.bridge.LabClipboard
import org.nucleantui.devicelab.bridge.LabLocation
import org.nucleantui.devicelab.bridge.LabNetwork
import org.nucleantui.devicelab.bridge.LabNotifications
import org.nucleantui.devicelab.bridge.LabSpeech
import java.text.DateFormat
import java.util.Date

// ── AndroidNetwork ───────────────────────────────────────────────────────────

class NetworkSection(private val activity: MainActivity) : Section {
    override val title = "Network"
    private lateinit var network: LabNetwork
    private lateinit var state: TextView
    private lateinit var details: TextView

    override fun build(ui: Ui): View = with(ui) {
        network = LabNetwork.init(activity.arena)
        card(title) {
            state = label().apply { textSize = 18f }
            details = label(secondary = true)
            hint("Live from the default-network callback. On the emulator: airplane mode or Wi-Fi in quick settings, or `adb shell svc wifi disable`.")
            network.observe(Runnable { update() })
            update()
        }
    }

    private fun update() {
        state.text = when {
            !network.isConnected -> "Offline"
            network.isValidated -> "Online"
            else -> "Connected, internet not confirmed"
        }
        details.text = if (!network.isConnected) "" else listOf(
            "Via: ${network.transports.joinToString().ifEmpty { "—" }}",
            "Metered: ${if (network.isMetered) "yes" else "no"}",
            "Bandwidth: ↓ ${network.downstreamBandwidth / 1000} Mbit/s · ↑ ${network.upstreamBandwidth / 1000} Mbit/s",
        ).joinToString("\n")
    }
}

// ── AndroidLocation ──────────────────────────────────────────────────────────

class LocationSection(private val activity: MainActivity) : Section {
    override val title = "Location"
    private lateinit var location: LabLocation
    private lateinit var access: TextView
    private lateinit var allow: Button
    private lateinit var toggle: Button
    private lateinit var fix: TextView
    private lateinit var status: TextView

    override fun build(ui: Ui): View = with(ui) {
        location = LabLocation.init(activity.arena)
        card(title) {
            access = label()
            row {
                allow = button("Allow location") {
                    location.requestAccess().onMain(activity) { _, error -> error?.let { status.showError("Asking failed", it) } }
                }
                toggle = button("Start updates") {
                    try {
                        if (location.isUpdating) location.stop() else location.start()
                    } catch (e: Exception) {
                        status.showError("Could not start", e)
                    }
                }
            }
            row {
                button("One fix") {
                    status.text = "Waiting for a position…"
                    location.requestFix().onMain(activity) { _, error ->
                        status.text = if (error != null) "No fix: ${error.swiftMessage}" else "Got a fresh position."
                    }
                }
                button("Address") {
                    status.text = "Looking up the address…"
                    location.lookUpAddresses().onMain(activity) { lines, error ->
                        status.text = when {
                            error != null -> "Geocoding failed: ${error.swiftMessage}"
                            lines.isNullOrEmpty() -> "No address for this position."
                            else -> lines.joinToString("\n")
                        }
                    }
                }
            }
            fix = label(monospace = true)
            status = label(secondary = true)
            hint("On the emulator: Extended controls → Location (a point, or play a route), or `adb emu geo fix 10.75 59.91`.")
            location.observe(Runnable { update() })
            update()
        }
    }

    private fun update() {
        access.text = "Access: ${location.authorization}" +
            (if (location.isEnabled) "" else " · location is switched off in settings") +
            (if (location.isUpdating) " · following ${location.provider}" else "")
        allow.shown(location.authorization != "precise")
        toggle.text = if (location.isUpdating) "Stop updates" else "Start updates"
        toggle.isEnabled = location.authorization != "denied"
        fix.text = if (!location.isHasFix) "No position yet." else listOf(
            "%.6f, %.6f".format(location.latitude, location.longitude),
            "altitude ${location.altitude.orDash("%.1f m")} · accuracy ${location.accuracy.orDash("±%.0f m")}",
            "speed ${location.speed.orDash("%.1f m/s")} · bearing ${location.bearing.orDash("%.0f°")}",
            "${location.fixProvider} · ${DateFormat.getTimeInstance().format(Date(location.time))}",
        ).joinToString("\n")
    }

    override fun onResume() {
        location.refresh()
    }
}

// ── AndroidClipboard (+ AndroidShare) ────────────────────────────────────────

class ClipboardSection(private val activity: MainActivity) : Section {
    override val title = "Clipboard"
    private lateinit var clipboard: LabClipboard
    private lateinit var content: TextView

    override fun build(ui: Ui): View = with(ui) {
        clipboard = LabClipboard.init(activity.arena)
        card(title) {
            content = label(monospace = true)
            val input = field("Text to copy", "Hello from Swift on Android")
            val status = label(secondary = true)
            row {
                button("Copy") { runCatching { clipboard.setText(input.text.toString()) }.onFailure { status.showError("Copy failed", it) } }
                button("Clear") { clipboard.clear() }
                button("Share…") { runCatching { DeviceLabBridge.shareText(input.text.toString()) }.onFailure { status.showError("Sharing failed", it) } }
            }
            hint("Follows the clipboard while the app is in front — copy something in another app and come back. On the emulator the host's clipboard is shared too.")
            clipboard.observe(Runnable { update() })
            update()
        }
    }

    private fun update() {
        content.text = if (clipboard.isHasText) "“${clipboard.text}”" else "(no text)"
        content.append("\n${clipboard.changeCount} changes seen")
    }

    override fun onFocus() {
        // Android only lets the focused app read the clipboard: catch up on what changed meanwhile.
        clipboard.refresh()
    }
}

// ── AndroidNotifications ─────────────────────────────────────────────────────

class NotificationsSection(private val activity: MainActivity) : Section {
    override val title = "Notifications"
    private lateinit var notifications: LabNotifications
    private lateinit var state: TextView
    private lateinit var allow: Button
    private lateinit var channelGroup: RadioGroup
    private lateinit var tapped: TextView
    private var channelID = ""
    private var lastPosted = -1

    override fun build(ui: Ui): View = with(ui) {
        notifications = LabNotifications.init(activity.arena)
        channelID = notifications.defaultChannelID
        card(title) {
            state = label()
            allow = button("Allow notifications") {
                notifications.requestAccess().onMain(activity) { _, _ -> }
            }
            label("Channel:")
            channelGroup = RadioGroup(activity).apply {
                setOnCheckedChangeListener { group, id ->
                    (group.findViewById<RadioButton>(id)?.tag as? String)?.let { channelID = it }
                }
            }
            addView(channelGroup)
            val channelName = field("New channel's name", "Alerts")
            row {
                for (importance in listOf("low", "default", "high")) {
                    button("+ $importance") {
                        val name = channelName.text.toString().ifBlank { importance }
                        runCatching { notifications.createChannel(name.lowercase().replace(' ', '-'), name, importance) }
                    }
                }
            }
            val titleField = field("Title", "Device Lab")
            val body = field("Text", "Posted from Swift through NotificationManager.")
            val status = label(secondary = true)
            row {
                button("Post") {
                    runCatching { notifications.post(titleField.text.toString(), body.text.toString(), channelID) }
                        .onSuccess { lastPosted = it; status.text = "Posted #$it on “$channelID” — tap it in the shade." }
                        .onFailure { status.showError("Posting failed", it) }
                }
                button("Update last") {
                    if (lastPosted < 0) return@button
                    val stamp = DateFormat.getTimeInstance().format(Date())
                    runCatching { notifications.update(lastPosted, titleField.text.toString(), "${body.text} (updated $stamp)") }
                        .onSuccess { status.text = "Updated #$lastPosted in place." }
                        .onFailure { status.showError("Updating failed", it) }
                }
                button("Cancel all") { notifications.cancelAll() }
            }
            tapped = label()
            hint("Tapping one brings the app back through onNewIntent; the card shows which. Channels can be tuned by the user in the app's notification settings. Remote push is not exercised.")
            notifications.observe(Runnable { update() })
            update()
        }
    }

    private fun update() {
        state.text = (if (notifications.isAuthorized) "Allowed" else "Not allowed") +
            " · ${notifications.activeCount} in the shade"
        allow.shown(!notifications.isAuthorized)
        tapped.text = if (notifications.lastTapped < 0) "No notification tapped yet."
        else "Last tapped: #${notifications.lastTapped} (${notifications.tapCount} taps)"

        channelGroup.setOnCheckedChangeListener(null)
        channelGroup.removeAllViews()
        for (channel in notifications.getChannels(activity.arena)) {
            channelGroup.addView(RadioButton(activity).apply {
                id = View.generateViewId()
                tag = channel.id
                text = "${channel.name} (${channel.importance})"
                isChecked = channel.id == channelID
            })
        }
        channelGroup.setOnCheckedChangeListener { group, id ->
            (group.findViewById<RadioButton>(id)?.tag as? String)?.let { channelID = it }
        }
    }

    override fun onResume() {
        notifications.refresh()
    }
}

// ── AndroidSpeech ────────────────────────────────────────────────────────────

class SpeechSection(private val activity: MainActivity) : Section {
    override val title = "Text to speech"
    private lateinit var speech: LabSpeech
    private lateinit var state: TextView
    private lateinit var speak: Button

    override fun build(ui: Ui): View = with(ui) {
        speech = LabSpeech.init(activity.arena)
        card(title) {
            state = label()
            val input = field("Text to say", "Hello! This sentence was spoken through Swift.")
            val status = label(secondary = true)
            row {
                speak = button("Speak") { runCatching { speech.speak(input.text.toString()) }.onFailure { status.showError("Speaking failed", it) } }
                button("Stop") { speech.stop() }
            }
            slider("Rate", 200, 100) { speech.setRate(maxOf(it, 10) / 100f) }
            slider("Pitch", 200, 100) { speech.setPitch(maxOf(it, 10) / 100f) }
            hint("The emulator's audio plays on the computer's speakers.")
            speech.observe(Runnable { update() })
            update()
        }
    }

    private fun update() {
        state.text = when {
            speech.isInitializationFailed -> "No text-to-speech engine could start."
            !speech.isReady -> "Starting the engine…"
            speech.isSpeaking -> "Speaking… (${speech.engine})"
            else -> "Ready · ${speech.engine} · rate %.1f · pitch %.1f".format(speech.rate, speech.pitch)
        }
        speak.isEnabled = speech.isReady
    }
}

// ── AndroidBiometrics ────────────────────────────────────────────────────────

class BiometricsSection(private val activity: MainActivity) : Section {
    override val title = "Biometrics"
    private lateinit var biometrics: LabBiometrics
    private lateinit var state: TextView
    private lateinit var authenticate: Button
    private lateinit var result: TextView

    override fun build(ui: Ui): View = with(ui) {
        biometrics = LabBiometrics.init(activity.arena)
        card(title) {
            state = label()
            authenticate = button("Authenticate") {
                result.text = "Waiting for the user…"
                biometrics.authenticate("Device Lab", "Confirm it's you").onMain(activity) { ok, error ->
                    result.text = when {
                        error != null -> "Failed: ${error.swiftMessage}"
                        ok == true -> "Authenticated ✓"
                        else -> "Cancelled"
                    }
                }
            }
            result = label(secondary = true)
            hint("On the emulator: set a screen lock and enroll a fingerprint in Settings → Security, then touch it with `adb -e emu finger touch 1` (or Extended controls → Fingerprint).")
            biometrics.observe(Runnable { update() })
            update()
        }
    }

    private fun update() {
        state.text = "Availability: ${biometrics.availability}" +
            if (biometrics.failedAttempts > 0) " · ${biometrics.failedAttempts} unrecognised attempts" else ""
        authenticate.isEnabled = biometrics.availability == "available" && !biometrics.isAuthenticating
    }

    override fun onResume() {
        biometrics.refresh()
    }
}
