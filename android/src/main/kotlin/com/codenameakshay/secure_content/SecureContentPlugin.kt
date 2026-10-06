package com.codenameakshay.secure_content

import android.app.Activity
import android.app.Application
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.PersistableBundle
import android.graphics.Color
import android.hardware.biometrics.BiometricPrompt as FrameworkBiometricPrompt
import android.os.CancellationSignal
import android.os.Build
import android.os.Bundle
import android.os.Debug
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.ViewTreeObserver
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
import java.util.Collections
import java.util.IdentityHashMap
import java.util.UUID

internal const val CLIPBOARD_TOKEN_EXTRA = "com.codenameakshay.secure_content.clipboard_token"

/** SecureContentPlugin */
class SecureContentPlugin : FlutterPlugin, SecureContentHostApi, ActivityAware {

    private var activity: Activity? = null
    private var flutterApi: SecureContentFlutterApi? = null
    private var screenshotCallback: Activity.ScreenCaptureCallback? = null
    private val clipboardHandler = Handler(Looper.getMainLooper())
    private var clipboardClearRunnable: Runnable? = null

    private var secureEnabled: Boolean = false
    private var appSwitcherProtectionEnabled: Boolean = false
    private var appSwitcherColor: Int = Color.BLACK
    private val windowProtectionState = WindowProtectionState()
    private lateinit var appContext: Context
    private var lastSensitiveClipboardToken: String? = null
    private var clipboardCleanupPending: Boolean = false
    private var clipboardWindowFocused: Boolean = false
    private val resumedActivities: MutableSet<Activity> = Collections.newSetFromMap(IdentityHashMap())
    private val clipboardWindowFocusListeners = IdentityHashMap<Activity, ViewTreeObserver.OnWindowFocusChangeListener>()
    private val focusedClipboardActivities: MutableSet<Activity> = Collections.newSetFromMap(IdentityHashMap())
    private var lifecycleCallbacksRegistered: Boolean = false
    private var engineAttached: Boolean = false
    private var biometricGeneration: Long = 0
    private var activeAndroidXPrompt: AndroidXBiometricPrompt? = null
    private var activeFrameworkCancellation: CancellationSignal? = null
    private var platformReadyEmitted: Boolean = false

    private val appLifecycleCallbacks = object : Application.ActivityLifecycleCallbacks {
        override fun onActivityCreated(activity: Activity, state: Bundle?) = Unit
        override fun onActivityStarted(activity: Activity) = Unit
        override fun onActivityResumed(activity: Activity) {
            resumedActivities.add(activity)
            if (lastSensitiveClipboardToken != null) watchWindowFocus(activity)
        }
        override fun onActivityPaused(activity: Activity) {
            resumedActivities.remove(activity)
            unwatchWindowFocus(activity)
        }
        override fun onActivityStopped(activity: Activity) = Unit
        override fun onActivitySaveInstanceState(activity: Activity, state: Bundle) = Unit
        override fun onActivityDestroyed(activity: Activity) {
            resumedActivities.remove(activity)
            unwatchWindowFocus(activity)
        }
    }

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        appContext = flutterPluginBinding.applicationContext
        engineAttached = true
        registerClipboardLifecycleCallbacks()
        flutterApi = SecureContentFlutterApi(flutterPluginBinding.binaryMessenger)
        SecureContentHostApi.setUp(flutterPluginBinding.binaryMessenger, this)
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        SecureContentHostApi.setUp(binding.binaryMessenger, null)
        cancelBiometricForActivityDetach()
        clearSensitiveClipboard(emitEvent = false)
        unregisterScreenshotCallbackIfAvailable()
        engineAttached = false
        releaseClipboardObserversAfterEngineDetach()
        activity?.let { windowProtectionState.restore(it.window) }
        activity = null
        flutterApi = null
    }

    private fun releaseClipboardObserversAfterEngineDetach() {
        if (clipboardCleanupPending) {
            registerClipboardLifecycleCallbacks()
        } else {
            clipboardClearRunnable?.let { clipboardHandler.removeCallbacks(it) }
            clipboardClearRunnable = null
            unwatchAllClipboardWindows()
            resumedActivities.clear()
            unregisterClipboardLifecycleCallbacks()
        }
    }

    override fun configureProtection(config: ProtectionConfig) {
        secureEnabled = config.enabled
        appSwitcherProtectionEnabled = config.protectInAppSwitcher
        appSwitcherColor = config.appSwitcherColor.toInt()
        applyProtection()
        emitPlatformReadyOnce()
    }

    override fun isScreenCaptured(): Boolean {
        return false
    }

    override fun requestBiometricAuth(reason: String) {
        val currentActivity = activity ?: run {
            emitEvent("biometricUnavailable")
            return
        }

        val title = if (reason.isBlank()) "Authenticate" else reason
        // AndroidX Biometric supports API 23+, so try it first whenever the host
        // Activity is a FragmentActivity, before falling back to the API 28+
        // framework prompt below. This lets API 23-27 hosts authenticate instead
        // of being rejected purely for being below the framework's minimum.
        val fragmentActivity = currentActivity as? FragmentActivity
        if (fragmentActivity != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val authenticators = androidXBiometricAuthenticators()
            val biometricManager = BiometricManager.from(fragmentActivity)
            if (biometricManager.canAuthenticate(authenticators) == BiometricManager.BIOMETRIC_SUCCESS) {
                requestBiometricWithAndroidX(fragmentActivity, title, authenticators)
            } else {
                emitEvent("biometricUnavailable")
            }
            return
        }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            emitEvent("biometricUnavailable")
            return
        }

        val authenticators = frameworkBiometricAuthenticators()
        val biometricManager = BiometricManager.from(currentActivity)
        if (biometricManager.canAuthenticate(authenticators) != BiometricManager.BIOMETRIC_SUCCESS) {
            emitEvent("biometricUnavailable")
            return
        }

        requestBiometricWithFramework(currentActivity, title)
    }

    private fun androidXBiometricAuthenticators(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            BiometricManager.Authenticators.BIOMETRIC_WEAK or
                BiometricManager.Authenticators.DEVICE_CREDENTIAL
        } else {
            BiometricManager.Authenticators.BIOMETRIC_WEAK
        }
    }

    private fun frameworkBiometricAuthenticators(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            BiometricManager.Authenticators.BIOMETRIC_WEAK or
                BiometricManager.Authenticators.DEVICE_CREDENTIAL
        } else {
            BiometricManager.Authenticators.BIOMETRIC_WEAK
        }
    }

    private fun requestBiometricWithAndroidX(
        fragmentActivity: FragmentActivity,
        title: String,
        authenticators: Int,
    ) {
        val promptInfo = createAndroidXPromptInfo(title, authenticators)
        val generation = ++biometricGeneration

        val biometricPrompt = AndroidXBiometricPrompt(
            fragmentActivity,
            ContextCompat.getMainExecutor(fragmentActivity),
            object : AndroidXBiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: AndroidXBiometricPrompt.AuthenticationResult) {
                    super.onAuthenticationSucceeded(result)
                    finishBiometric(generation, "biometricAuthSucceeded")
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    super.onAuthenticationError(errorCode, errString)
                    finishBiometric(generation, "biometricAuthFailed")
                }

            },
        )
        activeAndroidXPrompt = biometricPrompt
        biometricPrompt.authenticate(promptInfo)
    }

    internal fun createAndroidXPromptInfo(
        title: String,
        authenticators: Int,
    ): AndroidXBiometricPrompt.PromptInfo {
        val builder = AndroidXBiometricPrompt.PromptInfo.Builder()
            .setTitle(title)
            .setAllowedAuthenticators(authenticators)
        if ((authenticators and BiometricManager.Authenticators.DEVICE_CREDENTIAL) == 0) {
            builder.setNegativeButtonText("Cancel")
        }
        return builder.build()
    }

    @RequiresApi(Build.VERSION_CODES.P)
    private fun requestBiometricWithFramework(
        currentActivity: Activity,
        title: String,
    ) {
        val generation = ++biometricGeneration
        val callback = object : FrameworkBiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(result: FrameworkBiometricPrompt.AuthenticationResult?) {
                super.onAuthenticationSucceeded(result)
                finishBiometric(generation, "biometricAuthSucceeded")
            }

            override fun onAuthenticationError(errorCode: Int, errString: CharSequence?) {
                super.onAuthenticationError(errorCode, errString)
                finishBiometric(generation, "biometricAuthFailed")
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
                finishBiometric(generation, "biometricAuthFailed")
            }
        }

        val prompt = promptBuilder.build()
        val cancellationSignal = CancellationSignal()
        activeFrameworkCancellation = cancellationSignal
        prompt.authenticate(
            cancellationSignal,
            currentActivity.mainExecutor,
            callback,
        )
    }

    private fun finishBiometric(generation: Long, event: String) {
        if (generation != biometricGeneration) return
        activeAndroidXPrompt = null
        activeFrameworkCancellation = null
        emitEvent(event)
    }

    private fun cancelBiometricForActivityDetach() {
        val hadPrompt = activeAndroidXPrompt != null || activeFrameworkCancellation != null
        if (!hadPrompt) return
        biometricGeneration += 1
        activeAndroidXPrompt?.cancelAuthentication()
        activeAndroidXPrompt = null
        activeFrameworkCancellation?.cancel()
        activeFrameworkCancellation = null
        emitEvent("biometricUnavailable")
    }

    override fun checkIntegrity() {
        val riskDetected = isRooted() || isEmulator() || Debug.isDebuggerConnected()
        emitEvent(if (riskDetected) "integrityRiskDetected" else "integritySafe")
    }

    override fun setSensitiveClipboard(content: String, clearAfterMs: Long) {
        val clipboardManager = appContext.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val token = UUID.randomUUID().toString()
        val clipData = createSensitiveClipboardClip(content, token)
        clipboardManager.setPrimaryClip(clipData)
        lastSensitiveClipboardToken = token
        clipboardCleanupPending = false
        registerClipboardLifecycleCallbacks()
        resumedActivities.forEach(::watchWindowFocus)
        activity?.let(::watchWindowFocus)
        emitEvent("clipboardSet")

        clipboardClearRunnable?.let { clipboardHandler.removeCallbacks(it) }
        if (clearAfterMs > 0) {
            val runnable = Runnable {
                clipboardClearRunnable = null
                clearSensitiveClipboard()
            }
            clipboardClearRunnable = runnable
            val now = SystemClock.uptimeMillis()
            val safeDelay = clearAfterMs.coerceAtMost(Long.MAX_VALUE - now)
            clipboardHandler.postAtTime(runnable, now + safeDelay)
        }
    }

    override fun clearSensitiveClipboard() {
        clearSensitiveClipboard(emitEvent = true)
    }

    private fun clearSensitiveClipboard(emitEvent: Boolean) {
        val clipboardManager = appContext.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val expectedToken = lastSensitiveClipboardToken
        if (expectedToken != null &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
            !clipboardWindowFocused
        ) {
            clipboardCleanupPending = true
            return
        }

        val currentClip = if (expectedToken == null) null else clipboardManager.primaryClip
        val actualToken = currentClip?.takeIf { it.itemCount > 0 }?.let(::sensitiveClipboardToken)
        if (expectedToken != null && actualToken == expectedToken) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                clipboardManager.clearPrimaryClip()
            } else {
                clipboardManager.setPrimaryClip(ClipData.newPlainText("secure_content", ""))
            }
        }
        lastSensitiveClipboardToken = null
        clipboardCleanupPending = false
        clipboardClearRunnable?.let { clipboardHandler.removeCallbacks(it) }
        clipboardClearRunnable = null
        if (!engineAttached) unregisterClipboardLifecycleCallbacks()
        unwatchAllClipboardWindows()
        if (emitEvent) emitEvent("clipboardCleared")
    }

    private fun registerClipboardLifecycleCallbacks() {
        val application = appContext as? Application ?: return
        if (lifecycleCallbacksRegistered) return
        application.registerActivityLifecycleCallbacks(appLifecycleCallbacks)
        lifecycleCallbacksRegistered = true
    }

    private fun unregisterClipboardLifecycleCallbacks() {
        val application = appContext as? Application ?: return
        if (!lifecycleCallbacksRegistered) return
        application.unregisterActivityLifecycleCallbacks(appLifecycleCallbacks)
        lifecycleCallbacksRegistered = false
    }

    private fun watchWindowFocus(activity: Activity) {
        if (clipboardWindowFocusListeners.containsKey(activity)) {
            val decor = activity.window.decorView
            if (decor.hasWindowFocus()) onClipboardWindowFocus(activity, true)
            return
        }
        val listener = ViewTreeObserver.OnWindowFocusChangeListener { hasFocus ->
            onClipboardWindowFocus(activity, hasFocus)
        }
        clipboardWindowFocusListeners[activity] = listener
        activity.window.decorView.viewTreeObserver.addOnWindowFocusChangeListener(listener)
        onClipboardWindowFocus(activity, activity.window.decorView.hasWindowFocus())
    }

    private fun unwatchWindowFocus(activity: Activity) {
        val listener = clipboardWindowFocusListeners.remove(activity) ?: return
        val observer = activity.window.decorView.viewTreeObserver
        if (observer.isAlive) {
            observer.removeOnWindowFocusChangeListener(listener)
        }
        focusedClipboardActivities.remove(activity)
        clipboardWindowFocused = focusedClipboardActivities.isNotEmpty()
    }

    private fun unwatchAllClipboardWindows() {
        clipboardWindowFocusListeners.keys.toList().forEach(::unwatchWindowFocus)
        focusedClipboardActivities.clear()
        clipboardWindowFocused = false
    }

    private fun onClipboardWindowFocus(activity: Activity, hasFocus: Boolean) {
        if (!clipboardWindowFocusListeners.containsKey(activity)) return
        if (hasFocus) focusedClipboardActivities.add(activity) else focusedClipboardActivities.remove(activity)
        clipboardWindowFocused = focusedClipboardActivities.isNotEmpty()
        if (clipboardWindowFocused && clipboardCleanupPending) {
            clearSensitiveClipboard()
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        registerScreenshotCallbackIfAvailable()
        applyProtection()
        if (lastSensitiveClipboardToken != null) {
            watchWindowFocus(binding.activity)
        }
    }

    override fun onDetachedFromActivityForConfigChanges() {
        cancelBiometricForActivityDetach()
        unregisterScreenshotCallbackIfAvailable()
        activity?.let { detachedActivity ->
            if (lastSensitiveClipboardToken == null) {
                unwatchWindowFocus(detachedActivity)
            }
        }
        activity?.let { windowProtectionState.restore(it.window) }
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        registerScreenshotCallbackIfAvailable()
        applyProtection()
        if (lastSensitiveClipboardToken != null) {
            watchWindowFocus(binding.activity)
        }
    }

    override fun onDetachedFromActivity() {
        cancelBiometricForActivityDetach()
        unregisterScreenshotCallbackIfAvailable()
        activity?.let { detachedActivity ->
            if (lastSensitiveClipboardToken == null) {
                unwatchWindowFocus(detachedActivity)
            }
        }
        activity?.let { windowProtectionState.restore(it.window) }
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

    private fun isEmulator(): Boolean = isEmulatorBuild(
        fingerprint = Build.FINGERPRINT,
        model = Build.MODEL,
        manufacturer = Build.MANUFACTURER,
        brand = Build.BRAND,
        device = Build.DEVICE,
        product = Build.PRODUCT,
        hardware = Build.HARDWARE,
    )

    private fun applyProtection() {
        val currentActivity = activity ?: return
        currentActivity.runOnUiThread {
            windowProtectionState.apply(
                currentActivity.window,
                secureEnabled = secureEnabled,
                appSwitcherProtected = appSwitcherProtectionEnabled,
                appSwitcherColor = appSwitcherColor,
            )
        }
    }

    private fun emitPlatformReadyOnce() {
        if (platformReadyEmitted) {
            return
        }
        platformReadyEmitted = true
        emitEvent("platformReady")
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

internal fun isEmulatorBuild(
    fingerprint: String,
    model: String,
    manufacturer: String,
    brand: String,
    device: String,
    product: String,
    hardware: String,
): Boolean {
    val normalizedFingerprint = fingerprint.lowercase()
    val normalizedModel = model.lowercase()
    val normalizedManufacturer = manufacturer.lowercase()
    val normalizedBrand = brand.lowercase()
    val normalizedDevice = device.lowercase()
    val normalizedProduct = product.lowercase()
    val normalizedHardware = hardware.lowercase()

    return normalizedFingerprint.startsWith("generic") ||
        normalizedFingerprint.contains("emulator") ||
        normalizedFingerprint.contains("vbox") ||
        normalizedFingerprint.contains("test-keys") ||
        normalizedModel.contains("google_sdk") ||
        normalizedModel.contains("emulator") ||
        normalizedModel.contains("android sdk built for") ||
        normalizedManufacturer.contains("genymotion") ||
        normalizedBrand.startsWith("generic") && normalizedDevice.startsWith("generic") ||
        normalizedProduct.contains("google_sdk") ||
        normalizedProduct.contains("sdk_gphone") ||
        normalizedProduct.contains("emulator") ||
        normalizedHardware.contains("goldfish") ||
        normalizedHardware.contains("ranchu")
}

internal fun createSensitiveClipboardClip(content: String, token: String): ClipData {
    val clip = ClipData.newPlainText("secure_content:$token", content)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
        val extras = PersistableBundle()
        extras.putBoolean("android.content.extra.IS_SENSITIVE", true)
        extras.putString(CLIPBOARD_TOKEN_EXTRA, token)
        clip.description.extras = extras
    }
    return clip
}

internal fun sensitiveClipboardToken(clip: ClipData): String? {
    val extrasToken = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
        clip.description.extras?.getString(CLIPBOARD_TOKEN_EXTRA)
    } else {
        null
    }
    if (extrasToken != null) return extrasToken
    val label = clip.description.label?.toString() ?: return null
    return label.takeIf { it.startsWith("secure_content:") }
        ?.removePrefix("secure_content:")
}
