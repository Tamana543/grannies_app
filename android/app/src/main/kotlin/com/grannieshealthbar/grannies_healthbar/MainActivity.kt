package com.grannieshealthbar.grannies_healthbar

import android.app.Activity
import android.app.AlarmManager
import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.ImageDecoder
import android.graphics.Paint
import android.graphics.Rect
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlin.math.max
import kotlin.math.roundToInt

class MainActivity : FlutterActivity() {
    private var photoResult: MethodChannel.Result? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "grannies_healthbar/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "scheduleMedicines" -> {
                        try {
                            val events = call.argument<List<Map<String, Any>>>("events") ?: emptyList()
                            MedicineReminders.update(this, events)
                            result.success(null)
                        } catch (_: Exception) {
                            result.error("REMINDERS", "Could not schedule medicine reminders", null)
                        }
                    }
                    "requestReminderPermissions" -> {
                        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(
                                Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 305)
                        } else {
                            requestExactAlarms()
                        }
                        result.success(null)
                    }
                    "storagePath" -> result.success(filesDir.absolutePath)
                    "deviceInfo" -> result.success("${Build.MANUFACTURER} ${Build.MODEL} ${Build.DEVICE}")
                    "shareCode" -> {
                        val code = call.argument<String>("code") ?: ""
                        val intent = Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_TEXT, "Let’s stay connected on Grannies Healthbar. My family code is $code.")
                            setPackage("com.whatsapp")
                        }
                        try {
                            try { startActivity(intent) }
                            catch (_: ActivityNotFoundException) {
                                intent.setPackage(null)
                                startActivity(Intent.createChooser(intent, "Share your family code"))
                            }
                            result.success(null)
                        } catch (_: Exception) { result.error("SHARE", "No sharing app available", null) }
                    }
                    "pickFamilyPhoto" -> {
                        if (photoResult != null) {
                            result.error("BUSY", "A photo picker is already open", null)
                        } else {
                            photoResult = result
                            try {
                                startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                    type = "image/*"
                                    addCategory(Intent.CATEGORY_OPENABLE)
                                }, 304)
                            } catch (_: Exception) {
                                photoResult = null
                                result.error("PICKER", "Cannot open photos", null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
    private fun requestExactAlarms() {
        if (Build.VERSION.SDK_INT >= 31 && !getSystemService(AlarmManager::class.java).canScheduleExactAlarms()) {
            try {
                startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                    Uri.parse("package:$packageName")))
            } catch (_: ActivityNotFoundException) { /* Inexact reminders remain scheduled. */ }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 305 && grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) requestExactAlarms()
    }

    override fun onResume() {
        super.onResume()
        MedicineReminders.restore(this)
    }
    @Deprecated("Used for Flutter activity compatibility")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 304) return
        val pending = photoResult ?: return
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            photoResult = null
            pending.success(null)
            return
        }
        Thread {
            try {
                // ImageDecoder honors EXIF orientation and samples large sources before allocation.
                val source = ImageDecoder.createSource(contentResolver, uri)
                val bitmap = ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
                    decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                    val ratio = max(info.size.width / 1600.0, info.size.height / 1600.0).coerceAtLeast(1.0)
                    decoder.setTargetSize(max(1, (info.size.width / ratio).roundToInt()), max(1, (info.size.height / ratio).roundToInt()))
                }
                val output = Bitmap.createBitmap(1280, 720, Bitmap.Config.ARGB_8888)
                val width = bitmap.width
                val height = bitmap.height
                val cropWidth = minOf(width, (height * 16.0 / 9).roundToInt())
                val cropHeight = minOf(height, (width * 9.0 / 16).roundToInt())
                val left = (width - cropWidth) / 2
                val top = (height - cropHeight) / 2
                Canvas(output).drawBitmap(bitmap, Rect(left, top, left + cropWidth, top + cropHeight), Rect(0, 0, 1280, 720), Paint(Paint.FILTER_BITMAP_FLAG))
                val file = File(filesDir, "family_${System.currentTimeMillis()}.jpg")
                file.outputStream().use { output.compress(Bitmap.CompressFormat.JPEG, 86, it) }
                bitmap.recycle()
                output.recycle()
                runOnUiThread { photoResult = null; pending.success(file.absolutePath) }
            } catch (_: Throwable) {
                runOnUiThread { photoResult = null; pending.error("PHOTO", "Unable to crop and save photo", null) }
            }
        }.start()
    }
}
