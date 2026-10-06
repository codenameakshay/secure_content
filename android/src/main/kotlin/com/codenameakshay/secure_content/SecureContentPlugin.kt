package com.codenameakshay.secure_content

import android.app.Activity
import android.graphics.Color
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.annotation.MainThread
import com.codenameakshay.secure_content.pigeon.ProtectionConfig
import com.codenameakshay.secure_content.pigeon.SecureContentFlutterApi
import com.codenameakshay.secure_content.pigeon.SecureContentHostApi
import com.codenameakshay.secure_content.pigeon.SecureEvent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import java.time.Instant

@MainThread
class SecureContentPlugin : FlutterPlugin, SecureContentHostApi, ActivityAware {
    private var activity: Activity? = null
    private var flutterApi: SecureContentFlutterApi? = null
    private var screenshotCallback: Activity.ScreenCaptureCallback? = null
    private var clipboard: SensitiveClipboard? = null
    private val biometricAuthentication = BiometricAuthentication(::emitEvent)
    private val windowProtectionState = WindowProtectionState()
    private var secureEnabled = false
    private var appSwitcherProtectionEnabled = false
    private var appSwitcherColor = Color.BLACK
    private var platformReadyEmitted = false

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        flutterApi = SecureContentFlutterApi(binding.binaryMessenger)
        clipboard = SensitiveClipboard(binding.applicationContext, ::emitEvent)
        SecureContentHostApi.setUp(binding.binaryMessenger, this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        SecureContentHostApi.setUp(binding.binaryMessenger, null)
        flutterApi = null
        biometricAuthentication.cancel(emitEvent = false)
        clipboard?.detachEngine()
        clipboard = null
        detachActivity()
        secureEnabled = false
        appSwitcherProtectionEnabled = false
        platformReadyEmitted = false
    }

    override fun configureProtection(config: ProtectionConfig) {
        secureEnabled = config.enabled
        appSwitcherProtectionEnabled = config.protectInAppSwitcher
        appSwitcherColor = config.appSwitcherColor.toInt()
        applyProtection()
        if (secureEnabled) registerScreenshotCallback() else unregisterScreenshotCallback()
        if (!platformReadyEmitted) {
            platformReadyEmitted = true
            emitEvent(NativeEvent.PLATFORM_READY)
        }
    }

    override fun isScreenCaptured(): Boolean = false

    override fun requestBiometricAuth(reason: String) {
        biometricAuthentication.request(activity, reason)
    }

    override fun checkIntegrity() {
        emitEvent(if (hasIntegrityRisk()) NativeEvent.INTEGRITY_RISK else NativeEvent.INTEGRITY_SAFE)
    }

    override fun setSensitiveClipboard(content: String, clearAfterMs: Long) {
        checkNotNull(clipboard) { "SecureContent is not attached to an engine" }
            .set(content, clearAfterMs, activity)
    }

    override fun clearSensitiveClipboard() {
        checkNotNull(clipboard) { "SecureContent is not attached to an engine" }.clear()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        biometricAuthentication.onActivityAttached(binding.activity)
        applyProtection()
        registerScreenshotCallback()
        clipboard?.onActivityAttached(binding.activity)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() = detachActivity()

    override fun onDetachedFromActivity() = detachActivity()

    private fun detachActivity() {
        biometricAuthentication.cancel()
        unregisterScreenshotCallback()
        activity?.let {
            clipboard?.onActivityDetached(it)
            windowProtectionState.restore(it.window)
        }
        activity = null
    }

    private fun applyProtection() {
        val window = activity?.window ?: return
        windowProtectionState.apply(
            window,
            secureEnabled = secureEnabled,
            appSwitcherProtected = appSwitcherProtectionEnabled,
            appSwitcherColor = appSwitcherColor,
        )
    }

    private fun registerScreenshotCallback() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE && secureEnabled) {
            registerScreenshotCallbackApi34()
        }
    }

    private fun unregisterScreenshotCallback() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            unregisterScreenshotCallbackApi34()
        }
    }

    @RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
    private fun registerScreenshotCallbackApi34() {
        val currentActivity = activity ?: return
        if (screenshotCallback != null) return
        val callback = Activity.ScreenCaptureCallback {
            if (secureEnabled && activity === currentActivity) emitEvent(NativeEvent.SCREENSHOT_CAPTURED)
        }
        currentActivity.registerScreenCaptureCallback(currentActivity.mainExecutor, callback)
        screenshotCallback = callback
    }

    @RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
    private fun unregisterScreenshotCallbackApi34() {
        val callback = screenshotCallback ?: return
        activity?.unregisterScreenCaptureCallback(callback)
        screenshotCallback = null
    }

    private fun emitEvent(type: NativeEvent) {
        val api = flutterApi ?: return
        api.onEvent(
            SecureEvent(
                type = type.wireName,
                platform = "android",
                timestamp = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    Instant.now().toString()
                } else {
                    System.currentTimeMillis().toString()
                },
            ),
        ) { _ -> }
    }
}
