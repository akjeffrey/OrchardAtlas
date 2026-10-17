package com.orchardatlas.orchard_atlas

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/** Android's document picker grants access only to the user's selected backup. */
class BackupChannel(private val activity: Activity) : MethodChannel.MethodCallHandler {
    private val worker = Executors.newSingleThreadExecutor()
    private var pending: MethodChannel.Result? = null
    private val createCode = 7301
    private val selectCode = 7302
    private val maximumBytes = 20 * 1024 * 1024

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "version" -> {
                @Suppress("DEPRECATION")
                val info = activity.packageManager.getPackageInfo(activity.packageName, 0)
                @Suppress("DEPRECATION")
                val code = if (android.os.Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
                result.success("${info.versionName} ($code)")
            }
            "create", "select" -> {
                if (pending != null) { result.error("busy", "A file picker is already open", null); return }
                pending = result
                val creating = call.method == "create"
                val intent = Intent(if (creating) Intent.ACTION_CREATE_DOCUMENT else Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "application/json"
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                    if (creating) {
                        addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                        putExtra(Intent.EXTRA_TITLE, "OrchardAtlas-backup.json")
                    }
                }
                try {
                    @Suppress("DEPRECATION")
                    activity.startActivityForResult(intent, if (creating) createCode else selectCode)
                } catch (_: Exception) { pending = null; result.error("picker_failed", "Could not open the file picker", null) }
            }
            "read", "write", "delete" -> worker.execute {
                try {
                    val uri = Uri.parse(call.argument<String>("uri") ?: error("Missing document"))
                    require(uri.scheme == "content") { "Select a document using the file picker" }
                    when (call.method) {
                        "read" -> {
                            val bytes = ByteArrayOutputStream()
                            activity.contentResolver.openInputStream(uri).use { stream ->
                                requireNotNull(stream) { "Backup is unavailable" }
                                val buffer = ByteArray(8192)
                                while (true) {
                                    val n = stream.read(buffer)
                                    if (n < 0) break
                                    require(bytes.size() + n <= maximumBytes) { "Backup exceeds 20 MB" }
                                    bytes.write(buffer, 0, n)
                                }
                            }
                            activity.runOnUiThread { result.success(bytes.toString("UTF-8")) }
                        }
                        "write" -> {
                            val contents = requireNotNull(call.argument<String>("contents")).toByteArray(Charsets.UTF_8)
                            require(contents.size <= maximumBytes) { "Backup exceeds 20 MB" }
                            activity.contentResolver.openOutputStream(uri, "wt").use { stream ->
                                requireNotNull(stream) { "Backup is unavailable" }
                                stream.write(contents)
                                stream.flush()
                            }
                            activity.runOnUiThread { result.success(null) }
                        }
                        "delete" -> {
                            check(DocumentsContract.deleteDocument(activity.contentResolver, uri)) { "Provider could not delete the backup" }
                            activity.runOnUiThread { result.success(null) }
                        }
                    }
                } catch (_: Exception) {
                    activity.runOnUiThread { result.error("backup_failed", "Could not access the backup. Check Drive connectivity and file access, then retry or choose a new file.", null) }
                }
            }
            else -> result.notImplemented()
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != createCode && requestCode != selectCode) return false
        val result = pending ?: return true
        pending = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { result.success(null); return true }
        try {
            if (requestCode == createCode) {
                val flags = (data?.flags ?: 0) and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                activity.contentResolver.takePersistableUriPermission(uri, flags)
            }
            result.success(uri.toString())
        } catch (_: Exception) { result.error("permission_failed", "Choose a provider that supports persistent backup access", null) }
        return true
    }
}
