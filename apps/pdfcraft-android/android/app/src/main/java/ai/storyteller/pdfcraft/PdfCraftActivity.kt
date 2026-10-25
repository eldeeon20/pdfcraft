package ai.storyteller.pdfcraft

import android.Manifest
import android.app.AlertDialog
import android.app.NativeActivity
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.Settings
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import android.widget.Toast
import java.io.File

/**
 * NativeActivity with a thin Kotlin shell: asks for storage access on first launch and offers
 * the system file picker (SAF). The UI itself is still the original egui one; a SAF pick is
 * copied into the app sandbox and handed to Rust through `PdfCraft/pending_open.txt`.
 */
class PdfCraftActivity : NativeActivity() {

    private var prompting = false
    private var declined = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        KotlinBridge.activity = this
        applyOrientationMode()
        if (handleViewIntent(intent)) return
        askForStorage()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleViewIntent(intent)
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        applyOrientationMode()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) applyOrientationMode()
    }

    /// Portrait: the page owns the screen (immersive). Landscape: a normal window with
    /// the system bars visible, so the OS can resize or split the app.
    private fun applyOrientationMode() {
        val portrait = resources.configuration.orientation == Configuration.ORIENTATION_PORTRAIT
        if (portrait) enterImmersive() else leaveImmersive()
    }

    private fun enterImmersive() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false)
            window.insetsController?.let {
                it.hide(WindowInsets.Type.systemBars())
                it.systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = (
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                    or View.SYSTEM_UI_FLAG_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                    or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                )
        }
    }

    private fun leaveImmersive() {
        // The theme starts fullscreen; clear that flag before asking the bars to show.
        @Suppress("DEPRECATION")
        window.clearFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(true)
            window.insetsController?.let {
                it.show(WindowInsets.Type.systemBars())
                it.systemBarsBehavior = WindowInsetsController.BEHAVIOR_DEFAULT
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_VISIBLE
        }
    }

    override fun onResume() {
        super.onResume()
        applyOrientationMode()
        // Coming back from Settings (or from a pick) without the grant: ask again instead of
        // leaving the user with a picker that can't list Download.
        askForStorage()
    }

    override fun onDestroy() {
        if (KotlinBridge.activity === this) KotlinBridge.activity = null
        super.onDestroy()
    }

    private fun hasStorage(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            checkSelfPermission(Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
        }

    private fun askForStorage() {
        if (prompting || declined || hasStorage()) return
        prompting = true
        AlertDialog.Builder(this)
            .setTitle("Storage access")
            .setMessage(
                "PdfCraft needs access to your files to open PDFs.\n\n" +
                    "You can also pick a single document with the system picker; that only " +
                    "touches the file you choose."
            )
            .setPositiveButton("Grant access") { _, _ -> requestStorage() }
            .setNeutralButton("Pick a PDF") { _, _ -> pickPdf() }
            .setNegativeButton("Not now") { _, _ -> declined = true }
            .setOnDismissListener { prompting = false }
            .show()
    }

    private fun requestStorage() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val intent = Intent(
                Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                Uri.parse("package:$packageName"),
            )
            try {
                startActivity(intent)
            } catch (_: Exception) {
                startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
            }
        } else {
            requestPermissions(arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE), REQ_STORAGE)
        }
    }

    private fun pickPdf() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/pdf"
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        @Suppress("DEPRECATION")
        startActivityForResult(intent, REQ_PICK)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_PICK && resultCode == RESULT_OK) {
            val uri = data?.data ?: return
            openUri(uri)
        }
    }

    /// A tapped PDF (ACTION_VIEW) or the system picker both hand us a URI: copy it into the
    /// sandbox and restart so Rust opens it through `PdfCraft/pending_open.txt`.
    private fun handleViewIntent(intent: Intent?): Boolean {
        if (intent?.action != Intent.ACTION_VIEW) return false
        val uri = intent.data ?: return false
        openUri(uri)
        return true
    }

    private fun openUri(uri: Uri) {
        val dir = File(filesDir, "PdfCraft").apply { mkdirs() }
        val copy = File(dir, "saf-open.pdf")
        try {
            contentResolver.openInputStream(uri)?.use { input ->
                copy.outputStream().use { output -> input.copyTo(output) }
            } ?: throw IllegalStateException("empty stream")
            File(dir, "pending_open.txt").writeText(copy.absolutePath)
            // Drop the VIEW data before restarting, or onCreate would handle it again.
            setIntent(Intent(this, PdfCraftActivity::class.java))
            recreate()
        } catch (e: Exception) {
            Toast.makeText(this, "Could not open the PDF: ${e.message}", Toast.LENGTH_LONG).show()
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, results: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, results)
        if (requestCode == REQ_STORAGE && (results.isEmpty() || results[0] != PackageManager.PERMISSION_GRANTED)) {
            askForStorage()
        }
    }

    private companion object {
        const val REQ_STORAGE = 1
        const val REQ_PICK = 2
    }
}
