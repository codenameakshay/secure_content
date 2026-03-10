package com.codenameakshay.secure_content

import android.app.Activity
import android.graphics.Color
import android.os.Build
import android.view.WindowManager
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** SecureContentPlugin */
class SecureContentPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    ActivityAware {

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel

    private var activity: Activity? = null
    private var eventSink: EventChannel.EventSink? = null

    private var secureEnabled: Boolean = false
    private var appSwitcherProtectionEnabled: Boolean = true
    private var appSwitcherColor: Int = Color.BLACK

    override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel = MethodChannel(binding.binaryMessenger, "secure_content/methods")
        methodChannel.setMethodCallHandler(this)

        eventChannel = EventChannel(binding.binaryMessenger, "secure_content/events")
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: MethodChannel.Result) {
        when (call.method) {
            "configureProtection" -> {
                secureEnabled = call.argument<Boolean>("enabled") ?: false
                appSwitcherProtectionEnabled = call.argument<Boolean>("protectInAppSwitcher") ?: true
                appSwitcherColor = call.argument<Int>("appSwitcherColor") ?: Color.BLACK
                applyProtection()
                result.success(null)
            }

            "isScreenCaptured" -> {
                result.success(false)
            }

            else -> result.notImplemented()
        }
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

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        eventSink?.success(
            mapOf(
                "type" to "platformReady",
                "platform" to "android",
                "timestamp" to System.currentTimeMillis().toString()
            )
        )
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
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
}
