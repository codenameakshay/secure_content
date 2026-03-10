package com.codenameakshay.secure_content

import android.app.Activity
import android.graphics.Color
import android.os.Build
import android.view.WindowManager
import androidx.annotation.NonNull
import com.codenameakshay.secure_content.pigeon.ProtectionConfig
import com.codenameakshay.secure_content.pigeon.SecureContentFlutterApi
import com.codenameakshay.secure_content.pigeon.SecureContentHostApi
import com.codenameakshay.secure_content.pigeon.SecureEvent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import java.time.Instant

/** SecureContentPlugin */
class SecureContentPlugin : FlutterPlugin, SecureContentHostApi, ActivityAware {

    private lateinit var binding: FlutterPlugin.FlutterPluginBinding

    private var activity: Activity? = null
    private var flutterApi: SecureContentFlutterApi? = null

    private var secureEnabled: Boolean = false
    private var appSwitcherProtectionEnabled: Boolean = true
    private var appSwitcherColor: Int = Color.BLACK

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        binding = flutterPluginBinding
        flutterApi = SecureContentFlutterApi(binding.binaryMessenger)
        SecureContentHostApi.setUp(binding.binaryMessenger, this)
        emitEvent("platformReady")
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        SecureContentHostApi.setUp(binding.binaryMessenger, null)
        flutterApi = null
    }

    override fun configureProtection(config: ProtectionConfig) {
        secureEnabled = config.enabled
        appSwitcherProtectionEnabled = config.protectInAppSwitcher
        appSwitcherColor = config.appSwitcherColor.toInt()
        applyProtection()
    }

    override fun isScreenCaptured(): Boolean {
        return false
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        applyProtection()
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        applyProtection()
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    private fun applyProtection() {
        val currentActivity = activity ?: return
        currentActivity.runOnUiThread {
            if (secureEnabled) {
                currentActivity.window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
            } else {
                currentActivity.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP && appSwitcherProtectionEnabled) {
                currentActivity.window.navigationBarColor = appSwitcherColor
            }
        }
    }

    private fun emitEvent(type: String) {
        val event = SecureEvent(
            type = type,
            platform = "android",
            timestamp = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Instant.now().toString()
            } else {
                System.currentTimeMillis().toString()
            },
        )

        flutterApi?.onEvent(event) { _ -> }
    }
}
