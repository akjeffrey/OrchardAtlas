package com.orchardatlas.orchard_atlas

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.provider.MediaStore
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File

class PhotoChannel(private val activity: MainActivity) : MethodChannel.MethodCallHandler {
    private var pending: MethodChannel.Result? = null
    private var cameraFile: File? = null
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "capture") { result.notImplemented(); return }
        if (pending != null) { result.error("busy", "Photo picker already open", null); return }
        pending = result
        try {
            val intent = if (call.argument<Boolean>("camera") == true) {
                val file = File.createTempFile("orchard-photo-", ".jpg", activity.cacheDir)
                cameraFile = file
                val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.photos", file)
                Intent(MediaStore.ACTION_IMAGE_CAPTURE).apply {
                    putExtra(MediaStore.EXTRA_OUTPUT, uri)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                }
            } else Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                type = "image/*"; addCategory(Intent.CATEGORY_OPENABLE)
            }
            activity.startActivityForResult(intent, 9401)
        } catch (_: Exception) { pending = null; cameraFile?.delete(); cameraFile = null; result.error("unavailable", "Camera or photo picker unavailable", null) }
    }
    fun onActivityResult(code: Int, resultCode: Int, data: Intent?): Boolean {
        if (code != 9401) return false
        val reply = pending ?: return true
        pending = null
        val file = cameraFile; cameraFile = null
        if (resultCode != Activity.RESULT_OK) { file?.delete(); reply.success(null); return true }
        Thread {
            try {
                val uri = if (file != null) Uri.fromFile(file) else data?.data ?: error("No image")
                val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                activity.contentResolver.openInputStream(uri).use { BitmapFactory.decodeStream(it, null, options) }
                if (options.outWidth <= 0 || options.outHeight <= 0) error("Not an image")
                options.inSampleSize = 1
                while (maxOf(options.outWidth, options.outHeight) / options.inSampleSize > 1600) options.inSampleSize *= 2
                options.inJustDecodeBounds = false
                val bitmap = activity.contentResolver.openInputStream(uri).use { BitmapFactory.decodeStream(it, null, options) } ?: error("Invalid image")
                fun encode(maxSide: Int, budget: Int): ByteArray {
                    val ratio = minOf(1.0, maxSide.toDouble() / maxOf(bitmap.width, bitmap.height))
                    val scaled = Bitmap.createScaledBitmap(bitmap, maxOf(1,(bitmap.width*ratio).toInt()), maxOf(1,(bitmap.height*ratio).toInt()), true)
                    var quality = 85
                    var bytes: ByteArray
                    do { val stream=ByteArrayOutputStream(); scaled.compress(Bitmap.CompressFormat.JPEG,quality,stream); bytes=stream.toByteArray();quality-=10 } while(bytes.size>budget && quality>=25)
                    if (scaled !== bitmap) scaled.recycle()
                    if(bytes.size>budget) error("Image too large")
                    return bytes
                }
                val image=encode(1280,512*1024);val thumbnail=encode(160,32*1024)
                bitmap.recycle();file?.delete()
                activity.runOnUiThread { reply.success(mapOf("image" to image,"thumbnail" to thumbnail)) }
            } catch (_: Exception) { file?.delete();activity.runOnUiThread { reply.error("photo_failed","Could not read this image. Choose another photo.",null) } }
        }.start()
        return true
    }
}
