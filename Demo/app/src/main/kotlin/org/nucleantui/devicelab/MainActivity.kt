package org.nucleantui.devicelab

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import org.nucleantui.devicelab.bridge.DeviceLabBridge
import org.swift.swiftkit.core.SwiftArena
import java.util.Optional

/**
 * Device Lab: what NucleantAndroid's Swift capability targets can do on this
 * device — one card per target.
 *
 * Everything below the views is Swift, reached through DeviceLabBridge
 * (jextract's Java for it). Each card follows its Swift model with
 * `observe(Runnable)`, so what it shows is whatever the `@Observable` model
 * holds, including changes Android pushes into it (the battery, the network,
 * the clipboard, MediaStore, sensors, location). This Activity forwards what
 * only an Activity gets: itself, permission answers, activity results (the
 * pickers, the camera app), and new intents (a tapped notification).
 */
class MainActivity : Activity() {
    /** Swift objects handed to Kotlin live until the garbage collector drops them. */
    val arena: SwiftArena = SwiftArena.ofAuto()

    private val sections = mutableListOf<Section>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        DeviceLabBridge.attachActivity(this)

        val ui = Ui(this)
        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(ui.dp(16), ui.dp(16), ui.dp(16), ui.dp(16))
        }
        val photos = PhotosSection(this)
        sections += listOf(
            DeviceSection(this),
            FlashlightSection(this),
            HapticsSection(this),
            CameraSection(this, photos),
            photos,
            FilesSection(this),
            BatterySection(this),
            NetworkSection(this),
            SensorsSection(this),
            LocationSection(this),
            ClipboardSection(this),
            NotificationsSection(this),
            SpeechSection(this),
            BiometricsSection(this),
        )
        for (section in sections) {
            column.addView(
                try {
                    section.build(ui)
                } catch (e: Exception) {
                    // One capability failing to start should not take the others down.
                    ui.card(section.title) { with(ui) { label("Could not start: ${e.message}") } }
                }
            )
        }
        setContentView(ScrollView(this).apply {
            fitsSystemWindows = true
            addView(column, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        })
    }

    override fun onResume() {
        super.onResume()
        // Settings the user may have changed elsewhere (a notification permission,
        // an enrolled fingerprint) have no callback; read them again.
        sections.forEach { runCatching { it.onResume() } }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) sections.forEach { runCatching { it.onFocus() } }
    }

    override fun onDestroy() {
        DeviceLabBridge.detachActivity(this)
        super.onDestroy()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (!DeviceLabBridge.activityResult(requestCode, resultCode, Optional.ofNullable<Any>(data))) {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        DeviceLabBridge.newIntent(intent)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (!DeviceLabBridge.permissionsResult(requestCode, permissions, grantResults)) {
            super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        }
    }
}

/** One card: one capability target. */
interface Section {
    val title: String
    fun build(ui: Ui): View
    fun onResume() {}
    /** The window gained focus: what Android only allows the focused app (reading the clipboard). */
    fun onFocus() {}
}

/** A TextView that shows what failed, for sections to report into. */
fun TextView.showError(what: String, error: Throwable) {
    text = "$what: ${error.swiftMessage}"
}
