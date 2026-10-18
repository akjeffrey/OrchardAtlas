package com.orchardatlas.orchard_atlas

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import kotlin.math.max
import kotlin.math.min
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
    private val imageCode = 7303
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
            "importIcon" -> {
                if (pending != null) { result.error("busy", "A file picker is already open", null); return }
                pending = result
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "image/*"
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                try {
                    @Suppress("DEPRECATION")
                    activity.startActivityForResult(intent, imageCode)
                } catch (_: Exception) { pending = null; result.error("picker_failed", "Could not open the image picker", null) }
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
        if (requestCode != createCode && requestCode != selectCode && requestCode != imageCode) return false
        val result = pending ?: return true
        pending = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { result.success(null); return true }
        if (requestCode == imageCode) {
            worker.execute {
                try {
                    val output = ByteArrayOutputStream()
                    activity.contentResolver.openInputStream(uri).use { stream ->
                        requireNotNull(stream)
                        val buffer = ByteArray(8192)
                        while (true) {
                            val n = stream.read(buffer)
                            if (n < 0) break
                            require(output.size() + n <= 8 * 1024 * 1024) { "Choose an image under 8 MB" }
                            output.write(buffer, 0, n)
                        }
                    }
                    val bytes = output.toByteArray()
                    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                    BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
                    require(bounds.outWidth > 0 && bounds.outHeight > 0 &&
                        bounds.outWidth <= 16384 && bounds.outHeight <= 16384 &&
                        bounds.outWidth.toLong() * bounds.outHeight <= 64000000L) { "Unsupported image dimensions" }
                    var sample = 1
                    while (max(bounds.outWidth, bounds.outHeight) / sample > 192) sample *= 2
                    val options = BitmapFactory.Options().apply { inSampleSize = sample; inPreferredConfig = Bitmap.Config.ARGB_8888 }
                    val bitmap = requireNotNull(BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)) { "Unsupported image" }
                    fun thumbnail(size: Int): ByteArray {
                        val scale = min(1.0, size.toDouble() / max(bitmap.width, bitmap.height))
                        val scaled = Bitmap.createScaledBitmap(bitmap, max(1, (bitmap.width * scale).toInt()), max(1, (bitmap.height * scale).toInt()), true)
                        val encoded = ByteArrayOutputStream()
                        scaled.compress(Bitmap.CompressFormat.PNG, 100, encoded)
                        if (scaled !== bitmap) scaled.recycle()
                        return encoded.toByteArray()
                    }
                    var png = thumbnail(96)
                    if (png.size > 32768) png = thumbnail(64)
                    bitmap.recycle()
                    require(png.size <= 32768) { "Icon is too large" }
                    activity.runOnUiThread { result.success(png) }
                } catch (e: Exception) {
                    activity.runOnUiThread { result.error("icon_failed", "Choose a valid image under 8 MB (up to 64 megapixels).", null) }
                }
            }
            return true
        }
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
