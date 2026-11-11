package org.nucleantui.devicelab

import android.view.View
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import org.nucleantui.devicelab.bridge.LabAppFiles
import org.nucleantui.devicelab.bridge.LabDocument
import org.nucleantui.devicelab.bridge.LabDocuments
import java.text.DateFormat
import java.util.Date

// ── AndroidFiles ─────────────────────────────────────────────────────────────

class FilesSection(private val activity: MainActivity) : Section {
    override val title = "Files"
    private lateinit var files: LabAppFiles
    private lateinit var documents: LabDocuments
    private lateinit var usage: TextView
    private lateinit var listing: LinearLayout
    private lateinit var path: EditText
    private lateinit var content: EditText
    private lateinit var status: TextView
    private lateinit var documentInfo: TextView
    private var document: LabDocument? = null

    override fun build(ui: Ui): View = with(ui) {
        files = LabAppFiles.init(activity.arena)
        documents = LabDocuments.init(activity.arena)
        card(title) {
            label("The app's own directory — private, no permission needed:")
            label(files.directory, secondary = true, monospace = true).textSize = 11f
            usage = label(secondary = true)
            listing = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
            addView(listing)
            path = field("Path, e.g. notes/hello.txt", "notes/hello.txt")
            content = field("Contents", "Written from Swift with java.io through swift-java.")
            status = label(secondary = true)
            row {
                button("Write") { attempt { files.writeText(path.text.toString(), content.text.toString()); status.text = "Wrote ${path.text}." } }
                button("Read") { attempt { content.setText(files.readText(path.text.toString())); status.text = "Read ${path.text}." } }
                button("Delete") { attempt { files.delete(path.text.toString()); status.text = "Deleted ${path.text}." } }
            }

            label("Documents, through the system pickers — anywhere the user chooses:").setPadding(0, dp(12), 0, 0)
            row {
                button("Open…") { openDocument() }
                button("Save as…") { saveDocument() }
            }
            documentInfo = label(monospace = true)
            hint("The pickers are the system's own (DocumentsUI): on the emulator, Downloads and the app-less \"Internal storage\" are there to save to and open from.")
            files.observe(Runnable { update() })
            update()
        }
    }

    private fun attempt(block: () -> Unit) {
        try {
            block()
        } catch (e: Exception) {
            status.showError("Failed", e)
        }
    }

    private fun update() {
        usage.text = "%,d bytes used · %.1f GB free on the volume".format(files.usedBytes, files.availableBytes / 1e9)
        listing.removeAllViews()
        val entries = files.getEntries(activity.arena)
        if (entries.isEmpty()) {
            listing.addView(TextView(activity).apply { text = "(empty)" })
        }
        for (entry in entries) {
            listing.addView(TextView(activity).apply {
                val kind = if (entry.isDirectory) "📁" else "📄"
                text = "$kind ${entry.name}  ·  %,d bytes  ·  %s".format(
                    entry.size, DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT).format(Date(entry.modified)))
                setPadding(0, 6, 0, 6)
                if (!entry.isDirectory) setOnClickListener { path.setText(entry.path) }
            })
        }
    }

    private fun openDocument() {
        documents.open(arrayOf(), activity.arena).onMain(activity) { picked, error ->
            if (error != null) {
                documentInfo.showError("Opening failed", error)
                return@onMain
            }
            val opened = picked?.takeIf { it.isPresent }?.get() ?: run { documentInfo.text = "Cancelled."; return@onMain }
            document = opened
            documentInfo.text = describe(opened) + "\nReading…"
            opened.readText().onMain(activity) { text, readError ->
                documentInfo.text = describe(opened) + "\n" +
                    (text?.take(300)?.let { "“$it”" } ?: "Reading failed: ${readError?.swiftMessage}")
            }
        }
    }

    private fun saveDocument() {
        val name = path.text.toString().substringAfterLast('/').ifEmpty { "note.txt" }
        documents.create(name, "text/plain", activity.arena).onMain(activity) { created, error ->
            if (error != null) {
                documentInfo.showError("Saving failed", error)
                return@onMain
            }
            val target = created?.takeIf { it.isPresent }?.get() ?: run { documentInfo.text = "Cancelled."; return@onMain }
            document = target
            target.writeText(content.text.toString()).onMain(activity) { _, writeError ->
                documentInfo.text = if (writeError != null) "Writing failed: ${writeError.swiftMessage}" else "Saved.\n" + describe(target)
            }
        }
    }

    private fun describe(document: LabDocument): String =
        "${document.name} · ${document.mimeType.ifEmpty { "unknown type" }} · " +
            (if (document.size >= 0) "%,d bytes".format(document.size) else "size unknown")
}
