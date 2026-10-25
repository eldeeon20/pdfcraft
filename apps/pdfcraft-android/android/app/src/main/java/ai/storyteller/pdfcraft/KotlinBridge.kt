package ai.storyteller.pdfcraft

import android.content.pm.ActivityInfo

/**
 * Puente para el lado Rust (JNI). La UI sigue siendo la original (egui); esto sólo le da a
 * Kotlin un lugar estable dentro del APK para cuando el motor necesite llamarlo.
 */
object KotlinBridge {
    @Volatile
    var activity: PdfCraftActivity? = null

    @JvmStatic
    fun ping(): String = "pdfcraft-kotlin"

    @JvmStatic
    fun sdkInt(): Int = android.os.Build.VERSION.SDK_INT

    /// Rust lo llama desde los botones Full/Window: visor bloquea vertical, editor horizontal.
    @JvmStatic
    fun setViewerMode(on: Boolean) {
        val activity = activity ?: return
        activity.requestedOrientation = if (on) {
            ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        } else {
            ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
        }
    }
}
