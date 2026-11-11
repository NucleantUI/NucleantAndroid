package org.nucleantui.devicelab

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.graphics.Typeface
import android.text.InputType
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.SeekBar
import android.widget.TextView
import java.util.concurrent.CompletableFuture
import java.util.concurrent.CompletionException

/** The views every section is made of, built in code. */
class Ui(private val activity: Activity) {
    private val density = activity.resources.displayMetrics.density

    fun dp(value: Int): Int = (value * density).toInt()

    /** A titled card, filled by `content`. */
    fun card(title: String, content: LinearLayout.() -> Unit): LinearLayout =
        LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            background = activity.getDrawable(R.drawable.card)
            setPadding(dp(16), dp(16), dp(16), dp(16))
            layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
                .apply { bottomMargin = dp(12) }
            addView(TextView(activity).apply {
                text = title
                textSize = 20f
                setTypeface(typeface, Typeface.BOLD)
                setPadding(0, 0, 0, dp(4))
            })
            content()
        }

    fun LinearLayout.label(text: String = "", secondary: Boolean = false, monospace: Boolean = false): TextView =
        TextView(activity).apply {
            this.text = text
            if (secondary) setTextColor(activity.getColor(R.color.text_secondary))
            if (monospace) typeface = Typeface.MONOSPACE
            setPadding(0, dp(2), 0, dp(2))
        }.also(::addView)

    /** A hint about driving the capability on the emulator. */
    fun LinearLayout.hint(text: String): TextView =
        label(text, secondary = true).apply { textSize = 12f; setPadding(0, dp(6), 0, 0) }

    fun LinearLayout.button(text: String, onClick: () -> Unit): Button =
        Button(activity).apply {
            this.text = text
            isAllCaps = false
            setOnClickListener { onClick() }
        }.also(::addView)

    fun LinearLayout.row(content: LinearLayout.() -> Unit): LinearLayout =
        LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            content()
        }.also(::addView)

    /** A slider from 0 to `max`, with a caption in front. */
    fun LinearLayout.slider(caption: String, max: Int, value: Int, onChange: (Int) -> Unit): SeekBar {
        lateinit var bar: SeekBar
        row {
            label(caption).apply { setPadding(0, 0, dp(8), 0) }
            bar = SeekBar(activity).apply {
                this.max = max
                progress = value
                layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
                setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                    override fun onProgressChanged(seekBar: SeekBar, progress: Int, fromUser: Boolean) {
                        if (fromUser) onChange(progress)
                    }

                    override fun onStartTrackingTouch(seekBar: SeekBar) {}
                    override fun onStopTrackingTouch(seekBar: SeekBar) {}
                })
            }
            addView(bar)
        }
        return bar
    }

    fun LinearLayout.field(hint: String, text: String = ""): EditText =
        EditText(activity).apply {
            this.hint = hint
            setText(text)
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE
        }.also(::addView)

}

fun View.shown(visible: Boolean) {
    visibility = if (visible) View.VISIBLE else View.GONE
}

/** Run `block` on the UI thread once the future is done. */
fun <T> CompletableFuture<T>.onMain(activity: Activity, block: (T?, Throwable?) -> Unit) {
    whenComplete { value, error -> activity.runOnUiThread { block(value, error) } }
}

/** The Swift error's text, out of the CompletionException a future wraps it in. */
val Throwable.swiftMessage: String
    get() = ((this as? CompletionException)?.cause ?: this).message ?: toString()

/** `value`, or "—" for the NaN Swift sends when there is none. */
fun Double.orDash(format: String): String = if (isNaN()) "—" else String.format(format, this)

/** Decode `data`, downsampled so neither side is much over `maxSide`. */
fun decodeBounded(data: ByteArray, maxSide: Int): Bitmap? {
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeByteArray(data, 0, data.size, bounds)
    var sample = 1
    while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= maxSide) sample *= 2
    return BitmapFactory.decodeByteArray(data, 0, data.size, BitmapFactory.Options().apply { inSampleSize = sample })
}

fun Bitmap.rotated(degrees: Int): Bitmap {
    if (degrees % 360 == 0) return this
    val matrix = Matrix().apply { postRotate(degrees.toFloat()) }
    return Bitmap.createBitmap(this, 0, 0, width, height, matrix, true)
}
