package org.nucleantui.devicelab

import android.app.Dialog
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.RectF
import android.graphics.SurfaceTexture
import android.view.Gravity
import android.view.Surface
import android.view.TextureView
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.FrameLayout
import android.widget.GridLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.TextView
import org.nucleantui.devicelab.bridge.LabCamera
import org.nucleantui.devicelab.bridge.LabCameras
import org.nucleantui.devicelab.bridge.LabPhoto
import org.nucleantui.devicelab.bridge.LabPhotoAsset
import org.nucleantui.devicelab.bridge.LabPhotoLibrary
import org.nucleantui.devicelab.bridge.LabPixels
import org.nucleantui.devicelab.bridge.LibraryAccess
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

private fun photoName(): String = "DeviceLab_" + SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date()) + ".jpg"

/** "1024×768 RGBA · 3 MB · average #8A7F6C", from pixels Swift decoded. */
private fun describe(pixels: LabPixels): String =
    "decoded ${pixels.width}×${pixels.height} RGBA in Swift · ${pixels.byteCount / 1024} KB of pixels · " +
        "average colour #%06X".format(pixels.averageColor and 0xFFFFFF)

// ── AndroidCamera ────────────────────────────────────────────────────────────

class CameraSection(private val activity: MainActivity, private val photos: PhotosSection) : Section {
    override val title = "Camera"
    private lateinit var cameras: LabCameras
    private var list: List<LabCamera> = emptyList()
    private var selected: LabCamera? = null
    private var shown: LabPhoto? = null
    private var wantsPreview = false

    private lateinit var access: TextView
    private lateinit var allow: Button
    private lateinit var previewToggle: Button
    private lateinit var take: Button
    private lateinit var save: Button
    private lateinit var status: TextView
    private lateinit var texture: TextureView
    private lateinit var preview: ImageView

    override fun build(ui: Ui): View = with(ui) {
        cameras = LabCameras.init(activity.arena)
        list = cameras.getAll(activity.arena).toList()
        card(title) {
            access = label()
            allow = button("Allow camera") {
                cameras.requestAccess().onMain(activity) { _, error -> error?.let { status.showError("Asking failed", it) } }
            }
            val group = RadioGroup(activity)
            list.forEachIndexed { index, camera ->
                group.addView(RadioButton(activity).apply {
                    id = View.generateViewId()
                    tag = index
                    text = describe(camera)
                })
            }
            group.setOnCheckedChangeListener { radios, id ->
                val next = (radios.findViewById<RadioButton>(id)?.tag as? Int)?.let { list[it] }
                val previewing = selected?.isPreviewing == true
                selected?.stopPreview()
                selected = next
                if (previewing) startPreview()
                updateCamera()
            }
            addView(group)

            texture = TextureView(activity).apply {
                shown(false)
                surfaceTextureListener = object : TextureView.SurfaceTextureListener {
                    override fun onSurfaceTextureAvailable(surface: SurfaceTexture, width: Int, height: Int) {
                        if (wantsPreview) startPreview()
                    }

                    override fun onSurfaceTextureSizeChanged(surface: SurfaceTexture, width: Int, height: Int) = fitPreview()
                    override fun onSurfaceTextureDestroyed(surface: SurfaceTexture): Boolean {
                        selected?.stopPreview()
                        return true
                    }

                    override fun onSurfaceTextureUpdated(surface: SurfaceTexture) {}
                }
            }
            addView(texture, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(300)))
            row {
                previewToggle = button("Start preview") {
                    if (selected?.isPreviewing == true || wantsPreview) {
                        wantsPreview = false
                        selected?.stopPreview()
                    } else {
                        wantsPreview = true
                        texture.shown(true)
                        if (texture.isAvailable) startPreview()
                    }
                    updateCamera()
                }
                take = button("Take photo") { takePhoto() }
                save = button("Save") { saveShown() }.apply { isEnabled = false }
            }
            status = label(secondary = true)
            preview = ImageView(activity).apply {
                adjustViewBounds = true
                maxHeight = dp(360)
                shown(false)
            }
            addView(preview)
            hint("The preview streams into a TextureView's SurfaceTexture; photos taken while it runs come from that session. The emulator's back camera is a virtual 3D room (hold Alt and move the mouse), the front one a test pattern.")

            if (list.isEmpty()) status.text = "This device reports no cameras."
            (group.getChildAt(0) as? RadioButton)?.isChecked = true
            cameras.observe(Runnable { updateAccess() })
            for (camera in list) camera.observe(Runnable { if (camera === selected) updateCamera() })
            updateAccess()
        }
    }

    private fun describe(camera: LabCamera): String {
        val size = if (camera.largestPhotoWidth > 0) "${camera.largestPhotoWidth}×${camera.largestPhotoHeight}" else "no photo sizes"
        return "${camera.position.replaceFirstChar { it.uppercase() }} camera (id ${camera.id})\n" +
            "$size · ${camera.photoSizeCount} sizes · sensor ${camera.sensorOrientation}° · " +
            if (camera.isHasFlash) "flash" else "no flash"
    }

    private fun startPreview() {
        val camera = selected ?: return
        val surface = texture.surfaceTexture ?: return
        runCatching { camera.startPreview(surface) }.onFailure {
            wantsPreview = false
            status.showError("Preview failed", it)
        }
        updateCamera()
    }

    private fun updateAccess() {
        access.text = if (cameras.isAuthorized) "Camera access granted." else "Camera access not granted yet."
        allow.shown(!cameras.isAuthorized)
        updateCamera()
    }

    private fun updateCamera() {
        val camera = selected
        val authorized = cameras.isAuthorized
        take.isEnabled = camera != null && authorized && !camera.isCapturing
        take.text = if (camera?.isCapturing == true) "Taking…" else "Take photo"
        previewToggle.isEnabled = camera != null && authorized
        val previewing = camera?.isPreviewing == true
        previewToggle.text = if (previewing || wantsPreview) "Stop preview" else "Start preview"
        texture.shown(previewing || wantsPreview)
        if (previewing) {
            status.text = "Preview ${camera?.previewWidth}×${camera?.previewHeight} from the sensor"
            fitPreview()
        } else if (camera != null && camera.previewFailure.isNotEmpty()) {
            wantsPreview = false
            status.text = "Preview ended: ${camera.previewFailure}"
        }
    }

    /**
     * Size the view to the preview's aspect ratio and turn it for the display's
     * rotation. Camera2 already turns SurfaceTexture frames upright for the
     * device's natural orientation; what is left is the display being rotated.
     */
    private fun fitPreview() {
        val camera = selected ?: return
        val bufferWidth = camera.previewWidth.toFloat()
        val bufferHeight = camera.previewHeight.toFloat()
        if (bufferWidth <= 0 || bufferHeight <= 0 || texture.width == 0) return

        @Suppress("DEPRECATION")
        val rotation = activity.windowManager.defaultDisplay.rotation
        val sideways = rotation == Surface.ROTATION_90 || rotation == Surface.ROTATION_270
        // Natural orientation is portrait: the landscape buffer shows turned to portrait.
        val height = (texture.width * if (sideways) bufferHeight / bufferWidth else bufferWidth / bufferHeight).toInt()
        if (texture.layoutParams.height != height) {
            texture.layoutParams = texture.layoutParams.apply { this.height = height }
            return // laid out again, then onSurfaceTextureSizeChanged comes back here
        }
        val viewWidth = texture.width.toFloat()
        val viewHeight = texture.height.toFloat()
        val matrix = Matrix()
        val centerX = viewWidth / 2
        val centerY = viewHeight / 2
        if (sideways) {
            val viewRect = RectF(0f, 0f, viewWidth, viewHeight)
            val bufferRect = RectF(0f, 0f, bufferHeight, bufferWidth)
            bufferRect.offset(centerX - bufferRect.centerX(), centerY - bufferRect.centerY())
            matrix.setRectToRect(viewRect, bufferRect, Matrix.ScaleToFit.FILL)
            val scale = maxOf(viewHeight / bufferHeight, viewWidth / bufferWidth)
            matrix.postScale(scale, scale, centerX, centerY)
            matrix.postRotate(90f * (rotation - 2), centerX, centerY)
        } else if (rotation == Surface.ROTATION_180) {
            matrix.postRotate(180f, centerX, centerY)
        }
        texture.setTransform(matrix)
    }

    private fun takePhoto() {
        val camera = selected ?: return
        val started = System.currentTimeMillis()
        status.text = if (camera.isPreviewing) "Taking a photo from the preview…" else "Opening the ${camera.position} camera…"
        camera.takePhoto(12_000_000L, activity.arena).onMain(activity) { photo, error ->
            if (photo == null) {
                status.showError("Photo failed", error ?: IllegalStateException("no photo"))
                return@onMain
            }
            val bitmap = decodeBounded(photo.jpegData, 2048)?.rotated(photo.rotation)
            shown = photo
            preview.setImageBitmap(bitmap)
            preview.shown(bitmap != null)
            save.isEnabled = true
            status.text = "${photo.width}×${photo.height} JPEG · ${photo.jpegData.size / 1024} KB · " +
                "rotate ${photo.rotation}° to show · ${System.currentTimeMillis() - started} ms"
        }
    }

    private fun saveShown() {
        val photo = shown ?: return
        save.isEnabled = false
        photos.library.save(photo, photoName(), activity.arena).onMain(activity) { asset, error ->
            if (asset != null) {
                status.text = "Saved to Pictures/Device Lab as ${asset.name} — it shows up under Photos by itself."
            } else {
                status.showError("Saving failed", error ?: IllegalStateException("not saved"))
                save.isEnabled = true
            }
        }
    }
}

// ── AndroidPhotos (+ AndroidShare) ───────────────────────────────────────────

class PhotosSection(private val activity: MainActivity) : Section {
    override val title = "Photos"
    lateinit var library: LabPhotoLibrary
    private val thumbnails = HashMap<Long, Bitmap>()

    private lateinit var access: TextView
    private lateinit var allow: Button
    private lateinit var status: TextView
    private lateinit var picked: ImageView
    private lateinit var pickedInfo: TextView
    private lateinit var grid: GridLayout
    private var cell = 0

    override fun build(ui: Ui): View = with(ui) {
        library = LabPhotoLibrary.init("Device Lab", activity.arena)
        cell = (activity.resources.displayMetrics.widthPixels - dp(64) - 12) / 3
        card(title) {
            access = label()
            row {
                allow = button("Allow photos") {
                    library.requestAccess(activity.arena).onMain(activity) { _, error ->
                        error?.let { status.showError("Asking failed", it) }
                    }
                }
                button("Refresh") { runCatching { library.refresh() } }
            }
            row {
                button("Pick a photo") { pick() }
                button("Camera app") {
                    status.text = "Waiting for the camera app…"
                    library.captureWithCameraApp(photoName(), activity.arena).onMain(activity) { asset, error ->
                        status.text = when {
                            error != null -> "Camera app failed: ${error.swiftMessage}"
                            asset?.isPresent == true -> "The camera app saved ${asset.get().name}."
                            else -> "Cancelled."
                        }
                    }
                }
            }
            picked = ImageView(activity).apply {
                adjustViewBounds = true
                maxHeight = dp(240)
                shown(false)
            }
            addView(picked)
            pickedInfo = label(secondary = true).apply { shown(false) }
            status = label(secondary = true)
            grid = GridLayout(activity).apply { columnCount = 3 }
            addView(grid)
            hint("The grid follows MediaStore: photos saved here, by the camera app, or pushed with `adb push pic.jpg /sdcard/Pictures/` appear without a refresh. Picking needs no permission at all.")
            library.observe(Runnable { update() })
            update()
        }
    }

    private fun pick() {
        library.pickPhoto(activity.arena).onMain(activity) { image, error ->
            if (error != null) {
                status.showError("Picking failed", error)
                return@onMain
            }
            if (image == null || !image.isPresent) {
                status.text = "Nothing picked."
                return@onMain
            }
            val chosen = image.get()
            status.text = "Picked ${chosen.name} (${chosen.mimeType})"
            chosen.decode(1024, activity.arena).onMain(activity) { pixels, decodeError ->
                pickedInfo.shown(true)
                if (pixels == null) {
                    pickedInfo.showError("Decoding failed", decodeError ?: IllegalStateException("no pixels"))
                    return@onMain
                }
                pickedInfo.text = describe(pixels)
                picked.setImageBitmap(bitmap(pixels))
                picked.shown(true)
            }
        }
    }

    /** The pixels Swift decoded, back into a Bitmap to show them; nil for padded rows. */
    private fun bitmap(pixels: LabPixels): Bitmap? {
        if (pixels.bytesPerRow != pixels.width * 4) return null
        return Bitmap.createBitmap(pixels.width, pixels.height, Bitmap.Config.ARGB_8888).apply {
            copyPixelsFromBuffer(java.nio.ByteBuffer.wrap(pixels.pixels))
        }
    }

    private fun update() {
        val access = library.getAccess(activity.arena).discriminator
        this.access.text = when (access) {
            LibraryAccess.Discriminator.AUTHORIZED -> "Full access to the photo library."
            LibraryAccess.Discriminator.LIMITED -> "Access to the photos you selected."
            else -> "No library access: only photos Device Lab saved are visible."
        }
        allow.shown(access != LibraryAccess.Discriminator.AUTHORIZED)

        val photos = library.getPhotos(activity.arena)
        status.text = if (photos.isEmpty()) "No photos visible yet. Take one and save it." else "${photos.size} newest photos. Tap one to open it."
        grid.removeAllViews()
        for (photo in photos) grid.addView(thumbnailView(photo))
    }

    private fun thumbnailView(photo: LabPhotoAsset): ImageView = ImageView(activity).apply {
        layoutParams = GridLayout.LayoutParams().apply {
            width = cell
            height = cell
            setMargins(2, 2, 2, 2)
        }
        scaleType = ImageView.ScaleType.CENTER_CROP
        setBackgroundColor(activity.getColor(R.color.thumbnail_placeholder))
        contentDescription = photo.name
        setOnClickListener { open(photo) }

        val cached = thumbnails[photo.id] ?: photo.thumbnail.takeIf { it.isNotEmpty() }?.let { decodeBounded(it, cell) }
        if (cached != null) {
            thumbnails[photo.id] = cached
            setImageBitmap(cached)
        } else {
            photo.loadThumbnail(cell).onMain(activity) { jpeg, _ ->
                val bitmap = jpeg?.let { decodeBounded(it, cell) } ?: return@onMain
                thumbnails[photo.id] = bitmap
                setImageBitmap(bitmap)
            }
        }
    }

    private fun open(photo: LabPhotoAsset) {
        status.text = "Opening ${photo.name}…"
        photo.data().onMain(activity) { data, error ->
            if (data == null) {
                status.showError("Could not open ${photo.name}", error ?: IllegalStateException("no data"))
                return@onMain
            }
            status.text = "${photo.name} · ${photo.width}×${photo.height} · ${photo.mimeType} · ${data.size / 1024} KB"
            decodeBounded(data, 2048)?.rotated(photo.rotation)?.let { showFullScreen(it, photo) }
        }
    }

    private fun showFullScreen(bitmap: Bitmap, photo: LabPhotoAsset) {
        val dialog = Dialog(activity, android.R.style.Theme_Black_NoTitleBar_Fullscreen)
        val frame = FrameLayout(activity).apply { setBackgroundColor(Color.BLACK) }
        frame.addView(ImageView(activity).apply {
            setImageBitmap(bitmap)
            scaleType = ImageView.ScaleType.FIT_CENTER
            setOnClickListener { dialog.dismiss() }
        }, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        val info = TextView(activity).apply {
            setTextColor(Color.WHITE)
            setBackgroundColor(0x88000000.toInt())
            setPadding(24, 16, 24, 16)
            text = "Decoding in Swift…"
        }
        frame.addView(info, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.TOP))
        frame.addView(Button(activity).apply {
            text = "Share"
            isAllCaps = false
            setOnClickListener { runCatching { photo.share() }.onFailure { status.showError("Sharing failed", it) } }
        }, FrameLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.BOTTOM or Gravity.END))
        dialog.setContentView(frame)
        dialog.show()
        photo.decode(1024, activity.arena).onMain(activity) { pixels, error ->
            info.text = pixels?.let(::describe) ?: "Decoding failed: ${error?.swiftMessage}"
        }
    }
}
