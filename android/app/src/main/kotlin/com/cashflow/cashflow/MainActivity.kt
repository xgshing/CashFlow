package com.cashflow.cashflow

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cashflow/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "shareToWeChat" -> {
                        val path = call.argument<String>("path")
                        val name = call.argument<String>("name")
                        if (path.isNullOrBlank() || name.isNullOrBlank()) {
                            result.error("share", "缺少文件", null)
                            return@setMethodCallHandler
                        }
                        try {
                            shareToWeChat(path, name)
                            result.success(null)
                        } catch (_: PackageManager.NameNotFoundException) {
                            result.error("no_wechat", "请先安装微信", null)
                        } catch (_: ActivityNotFoundException) {
                            result.error("no_wechat", "请先安装微信", null)
                        } catch (error: Exception) {
                            result.error("share", error.message, null)
                        }
                    }

                    "fileIcon" -> {
                        val label = call.argument<String>("label") ?: "附件.pdf"
                        result.success(fileIcon(label))
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun shareToWeChat(path: String, name: String) {
        packageManager.getPackageInfo("com.tencent.mm", 0)
        val source = File(path)
        if (!source.isFile) throw IllegalArgumentException("文件不存在")
        val safeName = name.replace(Regex("""[\\/:*?"<>|]"""), "_").ifBlank { "记账.xlsx" }
        val folder = File(cacheDir, "wechat").apply { mkdirs() }
        val target = File(folder, safeName)
        source.copyTo(target, overwrite = true)
        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", target)
        val intent = Intent(Intent.ACTION_SEND).apply {
            setClassName("com.tencent.mm", "com.tencent.mm.ui.tools.ShareImgUI")
            type = "*/*"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            clipData = ClipData.newUri(contentResolver, safeName, uri)
        }
        grantUriPermission("com.tencent.mm", uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        startActivity(intent)
    }

    private fun fileIcon(label: String): ByteArray {
        val width = 420
        val height = 280
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawColor(Color.WHITE)
        val page = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.parseColor("#F8FAFC") }
        val border = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#4B5563")
            style = Paint.Style.STROKE
            strokeWidth = 4f
        }
        val sheet = RectF(145f, 18f, 275f, 158f)
        canvas.drawRoundRect(sheet, 10f, 10f, page)
        canvas.drawRoundRect(sheet, 10f, 10f, border)
        val band = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.parseColor("#E5484D") }
        canvas.drawRect(145f, 18f, 275f, 58f, band)
        val mark = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            textSize = 28f
            textAlign = Paint.Align.CENTER
            typeface = Typeface.DEFAULT_BOLD
        }
        canvas.drawText("PDF", 210f, 48f, mark)
        val caption = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#1F2937")
            textSize = 34f
            textAlign = Paint.Align.CENTER
        }
        var top = 198f
        for (line in wrapText(label, caption, width - 28f)) {
            canvas.drawText(line, width / 2f, top, caption)
            top += 42f
        }
        val output = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)
        bitmap.recycle()
        return output.toByteArray()
    }

    private fun wrapText(text: String, paint: Paint, maxWidth: Float): List<String> {
        if (text.isEmpty()) return listOf("附件.pdf")
        if (paint.measureText(text) <= maxWidth) return listOf(text)
        val lines = ArrayList<String>(2)
        var start = 0
        while (start < text.length && lines.size < 2) {
            var end = start + 1
            while (end <= text.length && paint.measureText(text.substring(start, end)) <= maxWidth) {
                end += 1
            }
            val cut = (end - 1).coerceAtLeast(start + 1).coerceAtMost(text.length)
            val line = text.substring(start, cut)
            lines.add(if (lines.size == 1 && cut < text.length) line.dropLast(1) + "…" else line)
            start = cut
        }
        return lines
    }
}
