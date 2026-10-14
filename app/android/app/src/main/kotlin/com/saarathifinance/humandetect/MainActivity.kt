package com.saarathifinance.humandetect

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import java.io.File

/// System photo picker. The user grants one image; the app never holds storage
/// permission and cannot list the gallery itself.
class MainActivity : FlutterFragmentActivity() {
    private val channelName = "com.saarathifinance.humandetect/gallery"
    private var pending: MethodChannel.Result? = null

    private val pickImage =
        registerForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
            val result = pending
            pending = null
            if (result == null) return@registerForActivityResult
            if (uri == null) {
                result.success(null)
                return@registerForActivityResult
            }
            try {
                val file = File(cacheDir, "gallery-${System.currentTimeMillis()}")
                contentResolver.openInputStream(uri).use { input ->
                    if (input == null) throw IllegalStateException("Could not open the photo")
                    file.outputStream().use { output -> input.copyTo(output) }
                }
                result.success(file.absolutePath)
            } catch (e: Exception) {
                result.error("gallery", e.message, null)
            }
        }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickImage" -> {
                        if (pending != null) {
                            result.error("busy", "A picker is already open", null)
                            return@setMethodCallHandler
                        }
                        pending = result
                        try {
                            pickImage.launch(
                                PickVisualMediaRequest.Builder()
                                    .setMediaType(ActivityResultContracts.PickVisualMedia.ImageOnly)
                                    .build(),
                            )
                        } catch (e: Exception) {
                            pending = null
                            result.error("gallery", e.message, null)
                        }
                    }
                    "transcodeToJpeg" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("gallery", "Missing path", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(transcodeToJpeg(path))
                        } catch (e: Exception) {
                            result.error("gallery", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        try {
            pending?.error("cancelled", "Activity destroyed", null)
        } catch (_: Exception) {
            // The engine may already be gone.
        }
        pending = null
        super.onDestroy()
    }

    private fun transcodeToJpeg(path: String): String {
        val source = File(path)
        val bitmap =
            BitmapFactory.decodeFile(source.absolutePath)
                ?: throw IllegalArgumentException("Could not decode the photo")
        val upright = applyExifRotation(source, bitmap)
        val out = File(cacheDir, "gallery-${System.currentTimeMillis()}.jpg")
        out.outputStream().use { stream ->
            if (!upright.compress(Bitmap.CompressFormat.JPEG, 92, stream)) {
                throw IllegalStateException("Could not write JPEG")
            }
        }
        if (upright !== bitmap) upright.recycle()
        bitmap.recycle()
        return out.absolutePath
    }

    private fun applyExifRotation(file: File, bitmap: Bitmap): Bitmap {
        val orientation =
            ExifInterface(file.absolutePath).getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL,
            )
        val degrees =
            when (orientation) {
                ExifInterface.ORIENTATION_ROTATE_90 -> 90f
                ExifInterface.ORIENTATION_ROTATE_180 -> 180f
                ExifInterface.ORIENTATION_ROTATE_270 -> 270f
                else -> 0f
            }
        if (degrees == 0f) return bitmap
        val matrix = Matrix().apply { postRotate(degrees) }
        return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
    }
}
