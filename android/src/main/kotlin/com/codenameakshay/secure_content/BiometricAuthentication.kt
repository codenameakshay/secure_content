package com.codenameakshay.secure_content

import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.biometrics.BiometricPrompt as FrameworkBiometricPrompt
import android.os.Build
import android.os.CancellationSignal
import androidx.annotation.RequiresApi
import androidx.annotation.MainThread
import androidx.appcompat.app.AlertDialog
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt as AndroidXBiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.codenameakshay.secure_content.pigeon.AuthResult
import com.codenameakshay.secure_content.pigeon.AuthStatus
import com.codenameakshay.secure_content.pigeon.BiometricCapability
import com.codenameakshay.secure_content.pigeon.BiometryType
import java.util.WeakHashMap
import java.lang.ref.WeakReference

@MainThread
internal class BiometricAuthentication(private val onEvent: (NativeEvent) -> Unit) {
    private var generation = 0L
    private var androidXPrompt: AndroidXBiometricPrompt? = null
    private var frameworkCancellation: CancellationSignal? = null
    private val owner = Any()
    private var ownedActivity: Activity? = null
    private var ownershipKey: Any? = null
    private var lifecycleObserver: LifecycleEventObserver? = null
    private var androidXStartAttempted = false
    private var cancellationPending = false
    private var pendingReply: ((AuthResult) -> Unit)? = null

    /**
     * Without [reply], reports the outcome as a coarse [NativeEvent]. With [reply], answers
     * exactly once through it with a detailed [AuthResult] and emits no biometric event.
     */
    fun request(
        activity: Activity?,
        reason: String,
        biometricOnly: Boolean = false,
        reply: ((AuthResult) -> Unit)? = null,
    ) {
        fun reject(event: NativeEvent, status: AuthStatus, message: String? = null) {
            if (reply != null) reply(AuthResult(status, message)) else onEvent(event)
        }
        if (ownershipKey != null && !cancellationPending) {
            reply?.invoke(AuthResult(AuthStatus.ERROR, "Another authentication is in progress"))
            return
        }
        if (activity == null || activity.isFinishing || activity.isDestroyed) {
            reject(NativeEvent.BIOMETRIC_UNAVAILABLE, AuthStatus.NOT_AVAILABLE, "No activity")
            return
        }

        val title = reason.ifBlank { "Authenticate" }
        val fragmentActivity = activity as? FragmentActivity
        if (fragmentActivity?.supportFragmentManager?.isStateSaved == true) {
            reject(NativeEvent.BIOMETRIC_UNAVAILABLE, AuthStatus.NOT_AVAILABLE, "Activity state is saved")
            return
        }
        if (fragmentActivity != null && Build.VERSION.SDK_INT < Build.VERSION_CODES.P &&
            !hasFingerprintDialogTheme(fragmentActivity)
        ) {
            reject(NativeEvent.BIOMETRIC_UNAVAILABLE, AuthStatus.NOT_AVAILABLE, "Activity theme is not AppCompat")
            return
        }
        val supportsCredentials = if (fragmentActivity != null) {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.R
        } else {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
        }
        val authenticators = allowedAuthenticators(biometricOnly, supportsCredentials)

        if (fragmentActivity == null && Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            reject(NativeEvent.BIOMETRIC_UNAVAILABLE, AuthStatus.NOT_AVAILABLE, "Requires a FragmentActivity below API 28")
            return
        }
        val availability = BiometricManager.from(activity).canAuthenticate(authenticators)
        val lockoutDuringMandatoryBiometrics = isLockoutAvailability(availability)
        if (availability != BiometricManager.BIOMETRIC_SUCCESS && !(reply != null && lockoutDuringMandatoryBiometrics)) {
            reject(NativeEvent.BIOMETRIC_UNAVAILABLE, authStatusForAvailability(availability))
            return
        }
        if (ownershipKey != null) {
            // A canceled AndroidX prompt still owns this host until its terminal callback.
            reject(NativeEvent.BIOMETRIC_FAILED, AuthStatus.ERROR, "The previous prompt is still closing")
            return
        }
        val key = fragmentActivity?.viewModelStore ?: activity
        if (!BiometricActivityOwners.acquire(key, owner, this)) {
            val holderIsCanceling = BiometricActivityOwners.find(key)?.cancellationPending == true
            reject(
                if (holderIsCanceling) NativeEvent.BIOMETRIC_FAILED else NativeEvent.BIOMETRIC_UNAVAILABLE,
                AuthStatus.ERROR,
                "Another engine is authenticating in this activity",
            )
            return
        }
        ownershipKey = key
        ownedActivity = activity

        try {
            if (fragmentActivity != null) {
                watchHost(fragmentActivity)
                requestAndroidX(fragmentActivity, title, authenticators)
            } else {
                requestFramework(activity, title, biometricOnly)
            }
        } catch (error: RuntimeException) {
            cancel(emitEvent = false)
            reject(NativeEvent.BIOMETRIC_UNAVAILABLE, AuthStatus.NOT_AVAILABLE, error.message)
            return
        }
        // Set only once the prompt started, so a failed start cannot reply twice.
        pendingReply = reply
    }

    fun capability(context: Context): BiometricCapability {
        val availability = BiometricManager.from(context)
            .canAuthenticate(allowedAuthenticators(biometricOnly = true, supportsCredentials = false))
        val available = availability == BiometricManager.BIOMETRIC_SUCCESS ||
            isLockoutAvailability(availability)
        val types = biometryTypes(context.packageManager)
        return BiometricCapability(
            available,
            if (available && types.isEmpty()) listOf(BiometryType.UNKNOWN) else types,
        )
    }

    /** Android 15 QPR and later report the lockout code from `canAuthenticate` for mandatory biometrics. */
    private fun isLockoutAvailability(availability: Int): Boolean =
        Build.VERSION.SDK_INT >= 35 && availability == AndroidXBiometricPrompt.ERROR_LOCKOUT

    fun onActivityAttached(activity: Activity) {
        val fragmentActivity = activity as? FragmentActivity ?: return
        BiometricActivityOwners.find(fragmentActivity.viewModelStore)?.watchHost(fragmentActivity)
    }

    fun cancel(emitEvent: Boolean = true) {
        val prompt = androidXPrompt
        val cancellation = frameworkCancellation
        if (ownershipKey == null) return
        if (cancellationPending) return
        if (prompt != null && androidXStartAttempted) {
            cancellationPending = true
            prompt.cancelAuthentication()
            respond(NativeEvent.BIOMETRIC_UNAVAILABLE, AuthStatus.CANCELED, emitEvent)
            return
        }
        generation += 1
        androidXPrompt = null
        frameworkCancellation = null
        try {
            prompt?.cancelAuthentication()
            cancellation?.cancel()
        } finally {
            val reply = pendingReply
            releaseOwnership()
            pendingReply = reply
        }
        respond(NativeEvent.BIOMETRIC_UNAVAILABLE, AuthStatus.CANCELED, emitEvent)
    }

    /** Answers the pending [request]: its reply when it has one, otherwise an event. */
    private fun respond(event: NativeEvent, status: AuthStatus, emitEvent: Boolean = true, message: String? = null) {
        val reply = pendingReply
        pendingReply = null
        if (reply != null) reply(AuthResult(status, message)) else if (emitEvent) onEvent(event)
    }

    private fun requestAndroidX(
        activity: FragmentActivity,
        title: String,
        authenticators: Int,
    ) {
        val promptInfo = createAndroidXPromptInfo(title, authenticators)
        val requestGeneration = ++generation
        val prompt = AndroidXBiometricPrompt(
            activity,
            ContextCompat.getMainExecutor(activity),
            object : AndroidXBiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: AndroidXBiometricPrompt.AuthenticationResult) {
                    finish(requestGeneration, NativeEvent.BIOMETRIC_SUCCEEDED, AuthStatus.SUCCESS)
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    finish(requestGeneration, NativeEvent.BIOMETRIC_FAILED, authStatusForError(errorCode), errString.toString())
                }
            },
        )
        androidXPrompt = prompt
        androidXStartAttempted = true
        prompt.authenticate(promptInfo)
    }

    @RequiresApi(Build.VERSION_CODES.P)
    private fun requestFramework(activity: Activity, title: String, biometricOnly: Boolean) {
        val requestGeneration = ++generation
        val executor = activity.mainExecutor
        val builder = FrameworkBiometricPrompt.Builder(activity).setTitle(title)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            builder.setAllowedAuthenticators(
                allowedAuthenticators(biometricOnly, supportsCredentials = true),
            )
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && !biometricOnly) {
            builder.setDeviceCredentialAllowed(true)
        }
        if (biometricOnly || Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            // Required whenever the device credential is not allowed.
            builder.setNegativeButton("Cancel", executor) { _, _ ->
                finish(requestGeneration, NativeEvent.BIOMETRIC_FAILED, AuthStatus.CANCELED)
            }
        }
        val cancellation = CancellationSignal()
        frameworkCancellation = cancellation
        builder.build().authenticate(
            cancellation,
            executor,
            object : FrameworkBiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: FrameworkBiometricPrompt.AuthenticationResult?) {
                    finish(requestGeneration, NativeEvent.BIOMETRIC_SUCCEEDED, AuthStatus.SUCCESS)
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence?) {
                    finish(requestGeneration, NativeEvent.BIOMETRIC_FAILED, authStatusForError(errorCode), errString?.toString())
                }
            },
        )
    }

    private fun finish(requestGeneration: Long, event: NativeEvent, status: AuthStatus, message: String? = null) {
        if (requestGeneration != generation) return
        generation += 1
        val wasCanceled = cancellationPending
        androidXPrompt = null
        frameworkCancellation = null
        val reply = pendingReply
        releaseOwnership()
        pendingReply = reply
        if (!wasCanceled) respond(event, status, message = message)
    }

    private fun releaseOwnership() {
        val activity = ownedActivity as? FragmentActivity
        lifecycleObserver?.let { activity?.lifecycle?.removeObserver(it) }
        lifecycleObserver = null
        ownershipKey?.let { BiometricActivityOwners.release(it, owner) }
        ownershipKey = null
        ownedActivity = null
        androidXStartAttempted = false
        cancellationPending = false
        pendingReply = null
    }

    private fun watchHost(activity: FragmentActivity) {
        val previousActivity = ownedActivity as? FragmentActivity
        lifecycleObserver?.let { previousActivity?.lifecycle?.removeObserver(it) }
        ownedActivity = activity
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_DESTROY) {
                if (activity.isChangingConfigurations) {
                    cancel()
                    androidXPrompt = null
                    lifecycleObserver?.let(activity.lifecycle::removeObserver)
                    lifecycleObserver = null
                    ownedActivity = null
                } else {
                    val wasCanceled = cancellationPending
                    generation += 1
                    androidXPrompt = null
                    frameworkCancellation = null
                    val reply = pendingReply
                    releaseOwnership()
                    pendingReply = reply
                    if (!wasCanceled) respond(NativeEvent.BIOMETRIC_UNAVAILABLE, AuthStatus.CANCELED)
                }
            }
        }
        lifecycleObserver = observer
        activity.lifecycle.addObserver(observer)
    }

    private fun hasFingerprintDialogTheme(activity: FragmentActivity): Boolean {
        val attributes = AlertDialog.Builder(activity).context.obtainStyledAttributes(
            intArrayOf(androidx.appcompat.R.attr.windowActionBar),
        )
        return try {
            attributes.hasValue(0)
        } finally {
            attributes.recycle()
        }
    }
}

@MainThread
private object BiometricActivityOwners {
    private class Owner(val token: Any, authentication: BiometricAuthentication) {
        val authentication = WeakReference(authentication)
    }

    private val owners = WeakHashMap<Any, Owner>()

    fun acquire(key: Any, owner: Any, authentication: BiometricAuthentication): Boolean {
        if (owners.containsKey(key)) return false
        owners[key] = Owner(owner, authentication)
        return true
    }

    fun find(key: Any): BiometricAuthentication? = owners[key]?.authentication?.get()

    fun release(key: Any, owner: Any) {
        if (owners[key]?.token === owner) owners.remove(key)
    }
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

/**
 * Biometric-only matches local_auth: BIOMETRIC_WEAK (which includes STRONG) with no
 * DEVICE_CREDENTIAL, so the prompt never offers the PIN, pattern, or password.
 */
internal fun allowedAuthenticators(biometricOnly: Boolean, supportsCredentials: Boolean): Int =
    BiometricManager.Authenticators.BIOMETRIC_WEAK or
        if (supportsCredentials && !biometricOnly) BiometricManager.Authenticators.DEVICE_CREDENTIAL else 0

/** Maps a BiometricPrompt error code. AndroidX and the framework share the values. */
internal fun authStatusForError(errorCode: Int): AuthStatus = when (errorCode) {
    AndroidXBiometricPrompt.ERROR_USER_CANCELED,
    AndroidXBiometricPrompt.ERROR_NEGATIVE_BUTTON,
    AndroidXBiometricPrompt.ERROR_CANCELED,
    -> AuthStatus.CANCELED
    AndroidXBiometricPrompt.ERROR_TIMEOUT -> AuthStatus.TIMEOUT
    AndroidXBiometricPrompt.ERROR_LOCKOUT -> AuthStatus.TEMPORARY_LOCKOUT
    AndroidXBiometricPrompt.ERROR_LOCKOUT_PERMANENT -> AuthStatus.PERMANENT_LOCKOUT
    AndroidXBiometricPrompt.ERROR_NO_BIOMETRICS -> AuthStatus.NOT_ENROLLED
    AndroidXBiometricPrompt.ERROR_HW_UNAVAILABLE,
    AndroidXBiometricPrompt.ERROR_HW_NOT_PRESENT,
    AndroidXBiometricPrompt.ERROR_NO_DEVICE_CREDENTIAL,
    AndroidXBiometricPrompt.ERROR_SECURITY_UPDATE_REQUIRED,
    -> AuthStatus.NOT_AVAILABLE
    else -> AuthStatus.ERROR
}

/** Maps a failed [BiometricManager.canAuthenticate] result. */
internal fun authStatusForAvailability(result: Int): AuthStatus = when (result) {
    BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED -> AuthStatus.NOT_ENROLLED
    else -> AuthStatus.NOT_AVAILABLE
}

/** Best effort: Android does not say which sensor holds an enrolled biometric. */
internal fun biometryTypes(packageManager: PackageManager): List<BiometryType> = buildList {
    if (packageManager.hasSystemFeature(PackageManager.FEATURE_FINGERPRINT)) add(BiometryType.FINGERPRINT)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        if (packageManager.hasSystemFeature(PackageManager.FEATURE_FACE)) add(BiometryType.FACE)
        if (packageManager.hasSystemFeature(PackageManager.FEATURE_IRIS)) add(BiometryType.IRIS)
    }
}
