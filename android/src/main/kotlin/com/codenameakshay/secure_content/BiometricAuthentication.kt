package com.codenameakshay.secure_content

import android.app.Activity
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

    fun request(activity: Activity?, reason: String) {
        if (ownershipKey != null) {
            if (cancellationPending) onEvent(NativeEvent.BIOMETRIC_UNAVAILABLE)
            return
        }
        if (activity == null || activity.isFinishing || activity.isDestroyed) {
            onEvent(NativeEvent.BIOMETRIC_UNAVAILABLE)
            return
        }

        val title = reason.ifBlank { "Authenticate" }
        val fragmentActivity = activity as? FragmentActivity
        if (fragmentActivity?.supportFragmentManager?.isStateSaved == true) {
            onEvent(NativeEvent.BIOMETRIC_UNAVAILABLE)
            return
        }
        if (fragmentActivity != null && Build.VERSION.SDK_INT < Build.VERSION_CODES.P &&
            !hasFingerprintDialogTheme(fragmentActivity)
        ) {
            onEvent(NativeEvent.BIOMETRIC_UNAVAILABLE)
            return
        }
        val supportsCredentials = if (fragmentActivity != null) {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.R
        } else {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
        }
        val authenticators = BiometricManager.Authenticators.BIOMETRIC_WEAK or
            if (supportsCredentials) BiometricManager.Authenticators.DEVICE_CREDENTIAL else 0

        if (fragmentActivity == null && Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            onEvent(NativeEvent.BIOMETRIC_UNAVAILABLE)
            return
        }
        if (BiometricManager.from(activity).canAuthenticate(authenticators) !=
            BiometricManager.BIOMETRIC_SUCCESS
        ) {
            onEvent(NativeEvent.BIOMETRIC_UNAVAILABLE)
            return
        }
        val key = fragmentActivity?.viewModelStore ?: activity
        if (!BiometricActivityOwners.acquire(key, owner, this)) {
            onEvent(NativeEvent.BIOMETRIC_UNAVAILABLE)
            return
        }
        ownershipKey = key
        ownedActivity = activity

        try {
            if (fragmentActivity != null) {
                watchHost(fragmentActivity)
                requestAndroidX(fragmentActivity, title, authenticators)
            } else {
                requestFramework(activity, title)
            }
        } catch (_: RuntimeException) {
            cancel(emitEvent = false)
            onEvent(NativeEvent.BIOMETRIC_UNAVAILABLE)
        }
    }

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
            if (emitEvent) onEvent(NativeEvent.BIOMETRIC_UNAVAILABLE)
            return
        }
        generation += 1
        androidXPrompt = null
        frameworkCancellation = null
        try {
            prompt?.cancelAuthentication()
            cancellation?.cancel()
        } finally {
            releaseOwnership()
        }
        if (emitEvent) onEvent(NativeEvent.BIOMETRIC_UNAVAILABLE)
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
                    finish(requestGeneration, NativeEvent.BIOMETRIC_SUCCEEDED)
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    finish(requestGeneration, NativeEvent.BIOMETRIC_FAILED)
                }
            },
        )
        androidXPrompt = prompt
        androidXStartAttempted = true
        prompt.authenticate(promptInfo)
    }

    @RequiresApi(Build.VERSION_CODES.P)
    private fun requestFramework(activity: Activity, title: String) {
        val requestGeneration = ++generation
        val executor = activity.mainExecutor
        val builder = FrameworkBiometricPrompt.Builder(activity).setTitle(title)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            builder.setAllowedAuthenticators(
                android.hardware.biometrics.BiometricManager.Authenticators.BIOMETRIC_WEAK or
                    android.hardware.biometrics.BiometricManager.Authenticators.DEVICE_CREDENTIAL,
            )
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setDeviceCredentialAllowed(true)
        } else {
            builder.setNegativeButton("Cancel", executor) { _, _ ->
                finish(requestGeneration, NativeEvent.BIOMETRIC_FAILED)
            }
        }
        val cancellation = CancellationSignal()
        frameworkCancellation = cancellation
        builder.build().authenticate(
            cancellation,
            executor,
            object : FrameworkBiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: FrameworkBiometricPrompt.AuthenticationResult?) {
                    finish(requestGeneration, NativeEvent.BIOMETRIC_SUCCEEDED)
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence?) {
                    finish(requestGeneration, NativeEvent.BIOMETRIC_FAILED)
                }
            },
        )
    }

    private fun finish(requestGeneration: Long, event: NativeEvent) {
        if (requestGeneration != generation) return
        generation += 1
        val wasCanceled = cancellationPending
        androidXPrompt = null
        frameworkCancellation = null
        releaseOwnership()
        if (!wasCanceled) onEvent(event)
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
                    releaseOwnership()
                    if (!wasCanceled) onEvent(NativeEvent.BIOMETRIC_UNAVAILABLE)
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
