package com.codenameakshay.secure_content

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.PersistableBundle
import android.graphics.Color
import android.hardware.biometrics.BiometricPrompt as FrameworkBiometricPrompt
import android.os.CancellationSignal
import android.os.Build
import android.os.Debug
import android.os.Handler
import android.os.Looper
import android.view.WindowManager
import androidx.annotation.NonNull
import androidx.annotation.RequiresApi
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt as AndroidXBiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import com.codenameakshay.secure_content.pigeon.ProtectionConfig
import com.codenameakshay.secure_content.pigeon.SecureContentFlutterApi
import com.codenameakshay.secure_content.pigeon.SecureContentHostApi
import com.codenameakshay.secure_content.pigeon.SecureEvent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import java.time.Instant
import java.io.File

/** SecureContentPlugin */
class SecureContentPlugin : FlutterPlugin, SecureContentHostApi, ActivityAware {

    private lateinit var binding: FlutterPlugin.FlutterPluginBinding

    private var activity: Activity? = null
    private var flutterApi: SecureContentFlutterApi? = null
    private var screenshotCallback: Activity.ScreenCaptureCallback? = null
    private val clipboardHandler = Handler(Looper.getMainLooper())
    private var clipboardClearRunnable: Runnable? = null

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
        clipboardClearRunnable?.let { clipboardHandler.removeCallbacks(it) }
        clipboardClearRunnable = null
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

    override fun requestBiometricAuth(reason: String) {
        val currentActivity = activity ?: run {
            emitEvent("biometricUnavailable")
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            emitEvent("biometricUnavailable")
            return
        }

        val title = if (reason.isBlank()) "Authenticate" else reason
        val biometricManager = BiometricManager.from(currentActivity)
        val authenticators = BiometricManager.Authenticators.BIOMETRIC_WEAK or
            BiometricManager.Authenticators.DEVICE_CREDENTIAL

        if (biometricManager.canAuthenticate(authenticators) != BiometricManager.BIOMETRIC_SUCCESS) {
            emitEvent("biometricUnavailable")
            return
        }

        val fragmentActivity = currentActivity as? FragmentActivity
        if (fragmentActivity != null) {
            requestBiometricWithAndroidX(fragmentActivity, title)
            return
        }

        requestBiometricWithFramework(currentActivity, title)
    }

    private fun requestBiometricWithAndroidX(
        fragmentActivity: FragmentActivity,
        title: String,
    ) {
        val promptInfo = AndroidXBiometricPrompt.PromptInfo.Builder()
            .setTitle(title)
            .setAllowedAuthenticators(
                BiometricManager.Authenticators.BIOMETRIC_WEAK or
                    BiometricManager.Authenticators.DEVICE_CREDENTIAL,
            )
            .build()

        val biometricPrompt = AndroidXBiometricPrompt(
            fragmentActivity,
            ContextCompat.getMainExecutor(fragmentActivity),
            object : AndroidXBiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: AndroidXBiometricPrompt.AuthenticationResult) {
                    super.onAuthenticationSucceeded(result)
                    emitEvent("biometricAuthSucceeded")
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    super.onAuthenticationError(errorCode, errString)
                    emitEvent("biometricAuthFailed")
                }

                override fun onAuthenticationFailed() {
                    super.onAuthenticationFailed()
                    emitEvent("biometricAuthFailed")
                }
            },
        )
        biometricPrompt.authenticate(promptInfo)
    }

    @RequiresApi(Build.VERSION_CODES.P)
    private fun requestBiometricWithFramework(
        currentActivity: Activity,
        title: String,
    ) {
        val callback = object : FrameworkBiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(result: FrameworkBiometricPrompt.AuthenticationResult?) {
                super.onAuthenticationSucceeded(result)
                emitEvent("biometricAuthSucceeded")
            }

            override fun onAuthenticationFailed() {
                super.onAuthenticationFailed()
                emitEvent("biometricAuthFailed")
            }

            override fun onAuthenticationError(errorCode: Int, errString: CharSequence?) {
                super.onAuthenticationError(errorCode, errString)
                emitEvent("biometricAuthFailed")
            }
        }

        val promptBuilder = FrameworkBiometricPrompt.Builder(currentActivity)
            .setTitle(title)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            promptBuilder.setDeviceCredentialAllowed(true)
        } else {
            promptBuilder.setNegativeButton(
                "Cancel",
                currentActivity.mainExecutor,
            ) { _, _ ->
                emitEvent("biometricAuthFailed")
            }
        }

        val prompt = promptBuilder.build()
        prompt.authenticate(
            CancellationSignal(),
            currentActivity.mainExecutor,
            callback,
        )
    }

    override fun checkIntegrity() {
        val riskDetected = isRooted() || isEmulator() || Debug.isDebuggerConnected()
        emitEvent(if (riskDetected) "integrityRiskDetected" else "integritySafe")
    }

    override fun setSensitiveClipboard(content: String, clearAfterMs: Long) {
        val currentActivity = activity ?: return
        val clipboardManager = currentActivity.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val clipData = ClipData.newPlainText("secure_content", content)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            val extras = PersistableBundle()
            extras.putBoolean("android.content.extra.IS_SENSITIVE", true)
            clipData.description.extras = extras
        }
        clipboardManager.setPrimaryClip(clipData)
        emitEvent("clipboardSet")

        clipboardClearRunnable?.let { clipboardHandler.removeCallbacks(it) }
        if (clearAfterMs > 0) {
            val runnable = Runnable {
                clearSensitiveClipboard()
            }
            clipboardClearRunnable = runnable
            clipboardHandler.postDelayed(runnable, clearAfterMs)
        }
    }

    override fun clearSensitiveClipboard() {
        val currentActivity = activity ?: return
        val clipboardManager = currentActivity.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboardManager.setPrimaryClip(ClipData.newPlainText("secure_content", ""))
        clipboardClearRunnable?.let { clipboardHandler.removeCallbacks(it) }
        clipboardClearRunnable = null
        emitEvent("clipboardCleared")
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        registerScreenshotCallbackIfAvailable()
        applyProtection()
    }

    override fun onDetachedFromActivityForConfigChanges() {
        unregisterScreenshotCallbackIfAvailable()
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        registerScreenshotCallbackIfAvailable()
        applyProtection()
    }

    override fun onDetachedFromActivity() {
        unregisterScreenshotCallbackIfAvailable()
        activity = null
    }

    private fun registerScreenshotCallbackIfAvailable() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            return
        }
        registerScreenshotCallbackApi34()
    }

    private fun unregisterScreenshotCallbackIfAvailable() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            return
        }
        unregisterScreenshotCallbackApi34()
    }

    @RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
    private fun registerScreenshotCallbackApi34() {
        val currentActivity = activity ?: return
        if (screenshotCallback != null) {
            return
        }

        val executor = currentActivity.mainExecutor
        val callback = Activity.ScreenCaptureCallback {
            if (secureEnabled) {
                emitEvent("screenshotCaptured")
            }
        }

        currentActivity.registerScreenCaptureCallback(executor, callback)
        screenshotCallback = callback
    }

    @RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
    private fun unregisterScreenshotCallbackApi34() {
        val currentActivity = activity ?: return
        val callback = screenshotCallback ?: return

        currentActivity.unregisterScreenCaptureCallback(callback)
        screenshotCallback = null
    }

    private fun isRooted(): Boolean {
        val buildTags = Build.TAGS
        if (buildTags != null && buildTags.contains("test-keys")) {
            return true
        }

        val rootPaths = listOf(
            "/system/app/Superuser.apk",
            "/sbin/su",
            "/system/bin/su",
            "/system/xbin/su",
            "/data/local/xbin/su",
            "/data/local/bin/su",
            "/system/sd/xbin/su",
            "/system/bin/failsafe/su",
            "/data/local/su",
        )

        return rootPaths.any { File(it).exists() }
    }

    private fun isEmulator(): Boolean {
        return Build.FINGERPRINT.startsWith("generic") ||
            Build.FINGERPRINT.lowercase().contains("vbox") ||
            Build.FINGERPRINT.lowercase().contains("test-keys") ||
            Build.MODEL.contains("google_sdk") ||
            Build.MODEL.contains("Emulator") ||
            Build.MODEL.contains("Android SDK built for x86") ||
            Build.MANUFACTURER.contains("Genymotion") ||
            Build.BRAND.startsWith("generic") && Build.DEVICE.startsWith("generic") ||
            "google_sdk" == Build.PRODUCT
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
