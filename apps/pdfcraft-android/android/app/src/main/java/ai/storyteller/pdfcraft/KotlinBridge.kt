package ai.storyteller.pdfcraft

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
}
