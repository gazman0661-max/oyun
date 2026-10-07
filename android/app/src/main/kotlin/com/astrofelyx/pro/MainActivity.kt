package com.astrofelyx.pro

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // Arkadas davetini Android paylasim menusuyle (WhatsApp, SMS...) gondermek icin.
    // Ek paket gerektirmez; Dart tarafi: lib/services/inbox_service.dart (shareInvite).
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "merge_dunyalari/share")
            .setMethodCallHandler { call, result ->
                if (call.method == "shareText") {
                    val text = call.argument<String>("text")
                    if (text.isNullOrEmpty()) {
                        result.error("bad_args", "text bos", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val send = Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_TEXT, text)
                        }
                        val chooser = Intent.createChooser(send, null)
                        chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(chooser)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("share_failed", e.message, null)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }
}
