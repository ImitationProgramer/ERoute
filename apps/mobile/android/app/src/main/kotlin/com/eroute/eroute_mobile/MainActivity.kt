package com.eroute.eroute_mobile

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.content.pm.ApplicationInfo

class MainActivity : FlutterActivity() {
    private var sensitiveCount = 0
    private val sensitive: Boolean get() = sensitiveCount > 0
    private var privacyCover: android.view.View? = null
    override fun onPause() {
        if (sensitive && privacyCover == null) {
            privacyCover = android.view.View(this).apply { setBackgroundColor(android.graphics.Color.rgb(250, 251, 252)) }
            addContentView(privacyCover, android.view.ViewGroup.LayoutParams(-1, -1))
        }
        super.onPause()
    }
    private fun removePrivacyCover() {
        (privacyCover?.parent as? android.view.ViewGroup)?.removeView(privacyCover)
        privacyCover = null
    }

    private fun allowed(): Boolean {
        val virtual = Build.FINGERPRINT.startsWith("generic") || Build.FINGERPRINT.contains("emulator") ||
            Build.MODEL.contains("Emulator") || Build.MODEL.contains("sdk_gphone") ||
            Build.MODEL.contains("Android SDK") || Build.PRODUCT.contains("sdk") ||
            Build.HARDWARE.contains("goldfish") || Build.HARDWARE.contains("ranchu") ||
            Build.MANUFACTURER.contains("Genymotion")
        return BuildConfig.FLAVOR == "production" && BuildConfig.BUILD_TYPE == "release" &&
            !BuildConfig.DEBUG && BuildConfig.EMERGENCY_ENABLED && !BuildConfig.AUTOMATION &&
            applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE == 0 &&
            Build.FINGERPRINT.isNotBlank() && !virtual && !android.os.Debug.isDebuggerConnected()
    }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "eroute/privacy").setMethodCallHandler { call, result ->
            when (call.method) {
                "setSensitive" -> {
                    sensitiveCount = if (call.arguments == true) sensitiveCount + 1 else maxOf(0, sensitiveCount - 1)
                    if (sensitive) window.addFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
                    else { window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE); removePrivacyCover() }
                    result.success(null)
                }
                "allowDisplay" -> { removePrivacyCover(); result.success(null) }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "eroute/emergency_sms")
            .setMethodCallHandler { call, result ->
                if (call.method == "canCompose") {
                    result.success(Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:119"))
                        .resolveActivity(packageManager) != null)
                }
                else if (call.method != "compose") { result.notImplemented() }
                else {
                    val encoded = call.argument<String>("encodedBody")
                    if (encoded == null) { result.success(false) }
                    else try {
                        // OS composer owns the final Send action. No SMS permission.
                        val intent = Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:119"))
                        intent.putExtra("sms_body", Uri.decode(encoded))
                        startActivity(intent)
                        result.success(true)
                    } catch (_: Exception) { result.success(false) }
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "eroute/emergency_dialer")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isSystemDialerAllowed" -> result.success(allowed())
                    "openEmergencyDialScreen" -> {
                        if (!allowed()) { result.success(false) }
                        else {
                            try {
                                // Never ACTION_CALL: the user must press the OS call button.
                                startActivity(Intent(Intent.ACTION_DIAL, Uri.parse("tel:119")))
                                result.success(true)
                            } catch (_: Exception) { result.success(false) }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
