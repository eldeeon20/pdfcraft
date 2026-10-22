package ai.storyteller.pdfcraft

import android.Manifest
import android.app.AlertDialog
import android.app.NativeActivity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.Settings
import android.widget.Toast
import java.io.File

/**
 * NativeActivity with a thin Kotlin shell: asks for storage access on first launch and offers
 * the system file picker (SAF). The UI itself is still the original egui one; a SAF pick is
 * copied into the app sandbox and handed to Rust through `PdfCraft/pending_open.txt`.
 */
class PdfCraftActivity : NativeActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) askForStorage()
    }

    private fun hasStorage(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            checkSelfPermission(Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
        }

    private fun askForStorage() {
        if (hasStorage()) return
        AlertDialog.Builder(this)
            .setTitle("Storage access")
            .setMessage(
                "PdfCraft needs access to your files to open PDFs.\n\n" +
                    "You can also pick a single document with the system picker; that only " +
                    "touches the file you choose."
            )
            .setPositiveButton("Grant access") { _, _ -> requestStorage() }
            .setNeutralButton("Pick a PDF") { _, _ -> pickPdf() }
            .setNegativeButton("Not now", null)
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
            val dir = File(filesDir, "PdfCraft").apply { mkdirs() }
            val copy = File(dir, "saf-open.pdf")
            try {
                contentResolver.openInputStream(uri)?.use { input ->
                    copy.outputStream().use { output -> input.copyTo(output) }
                } ?: throw IllegalStateException("empty stream")
                File(dir, "pending_open.txt").writeText(copy.absolutePath)
                recreate()
            } catch (e: Exception) {
                Toast.makeText(this, "Could not open the PDF: ${e.message}", Toast.LENGTH_LONG).show()
            }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, results: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, results)
        if (requestCode == REQ_STORAGE && results.isNotEmpty() && results[0] != PackageManager.PERMISSION_GRANTED) {
            askForStorage()
        }
    }

    private companion object {
        const val REQ_STORAGE = 1
        const val REQ_PICK = 2
    }
}
