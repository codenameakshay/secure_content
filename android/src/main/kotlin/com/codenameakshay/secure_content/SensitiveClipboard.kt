package com.codenameakshay.secure_content

import android.app.Activity
import android.app.Application
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PersistableBundle
import android.os.SystemClock
import android.view.ViewTreeObserver
import androidx.annotation.MainThread
import java.util.Collections
import java.util.IdentityHashMap
import java.util.UUID

internal const val CLIPBOARD_TOKEN_EXTRA = "com.codenameakshay.secure_content.clipboard_token"

@MainThread
internal class SensitiveClipboard(
    context: Context,
    onEvent: (NativeEvent) -> Unit,
) {
    private var onEvent: ((NativeEvent) -> Unit)? = onEvent
    private val application = context.applicationContext as? Application
    private val clipboard = checkNotNull(context.getSystemService(ClipboardManager::class.java))
    private val clipboardHandler = Handler(Looper.getMainLooper())
    private var clipboardClearRunnable: Runnable? = null
    private var lastSensitiveClipboardToken: String? = null
    private var clipboardCleanupPending = false
    private var lifecycleCallbacksRegistered = false
    private val resumedActivities: MutableSet<Activity> = Collections.newSetFromMap(IdentityHashMap())
    private val clipboardWindowFocusListeners =
        IdentityHashMap<Activity, ViewTreeObserver.OnWindowFocusChangeListener>()
    private val focusedClipboardActivities: MutableSet<Activity> =
        Collections.newSetFromMap(IdentityHashMap())

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

    init {
        registerLifecycleCallbacks()
    }

    fun set(content: String, clearAfterMs: Long, activity: Activity?) {
        val token = UUID.randomUUID().toString()
        clipboard.setPrimaryClip(createSensitiveClipboardClip(content, token))
        lastSensitiveClipboardToken = token
        clipboardCleanupPending = false
        registerLifecycleCallbacks()
        resumedActivities.forEach(::watchWindowFocus)
        activity?.let(::watchWindowFocus)
        onEvent?.invoke(NativeEvent.CLIPBOARD_SET)

        cancelExpiry()
        if (clearAfterMs > 0) {
            val runnable = Runnable {
                clipboardClearRunnable = null
                clear()
            }
            clipboardClearRunnable = runnable
            val now = SystemClock.uptimeMillis()
            clipboardHandler.postAtTime(runnable, now + clearAfterMs.coerceAtMost(Long.MAX_VALUE - now))
        }
    }

    fun clear(emitEvent: Boolean = true) {
        val expectedToken = lastSensitiveClipboardToken
        if (expectedToken != null &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
            focusedClipboardActivities.isEmpty()
        ) {
            clipboardCleanupPending = true
            return
        }

        val currentClip = if (expectedToken == null) null else clipboard.primaryClip
        val actualToken = currentClip?.takeIf { it.itemCount > 0 }?.let(::sensitiveClipboardToken)
        if (expectedToken != null && actualToken == expectedToken) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                clipboard.clearPrimaryClip()
            } else {
                clipboard.setPrimaryClip(ClipData.newPlainText("secure_content", ""))
            }
        }
        lastSensitiveClipboardToken = null
        clipboardCleanupPending = false
        cancelExpiry()
        unwatchAllWindows()
        if (onEvent == null) releaseLifecycleObservers()
        if (emitEvent) onEvent?.invoke(NativeEvent.CLIPBOARD_CLEARED)
    }

    fun onActivityAttached(activity: Activity) {
        if (lastSensitiveClipboardToken != null) watchWindowFocus(activity)
    }

    fun onActivityDetached(activity: Activity) {
        if (lastSensitiveClipboardToken == null) unwatchWindowFocus(activity)
    }

    fun detachEngine() {
        onEvent = null
        cancelExpiry()
        clear(emitEvent = false)
        if (!clipboardCleanupPending) releaseLifecycleObservers()
    }

    private fun cancelExpiry() {
        clipboardClearRunnable?.let(clipboardHandler::removeCallbacks)
        clipboardClearRunnable = null
    }

    private fun registerLifecycleCallbacks() {
        if (lifecycleCallbacksRegistered || application == null) return
        application.registerActivityLifecycleCallbacks(appLifecycleCallbacks)
        lifecycleCallbacksRegistered = true
    }

    private fun releaseLifecycleObservers() {
        cancelExpiry()
        unwatchAllWindows()
        resumedActivities.clear()
        if (lifecycleCallbacksRegistered) {
            application?.unregisterActivityLifecycleCallbacks(appLifecycleCallbacks)
            lifecycleCallbacksRegistered = false
        }
    }

    private fun watchWindowFocus(activity: Activity) {
        val decor = activity.window.decorView
        if (clipboardWindowFocusListeners.containsKey(activity)) {
            onWindowFocus(activity, decor.hasWindowFocus())
            return
        }
        val listener = ViewTreeObserver.OnWindowFocusChangeListener { hasFocus ->
            onWindowFocus(activity, hasFocus)
        }
        clipboardWindowFocusListeners[activity] = listener
        decor.viewTreeObserver.addOnWindowFocusChangeListener(listener)
        onWindowFocus(activity, decor.hasWindowFocus())
    }

    private fun unwatchWindowFocus(activity: Activity) {
        val listener = clipboardWindowFocusListeners.remove(activity) ?: return
        val observer = activity.window.decorView.viewTreeObserver
        if (observer.isAlive) observer.removeOnWindowFocusChangeListener(listener)
        focusedClipboardActivities.remove(activity)
    }

    private fun unwatchAllWindows() {
        clipboardWindowFocusListeners.keys.toList().forEach(::unwatchWindowFocus)
        focusedClipboardActivities.clear()
    }

    private fun onWindowFocus(activity: Activity, hasFocus: Boolean) {
        if (!clipboardWindowFocusListeners.containsKey(activity)) return
        if (hasFocus) focusedClipboardActivities.add(activity) else focusedClipboardActivities.remove(activity)
        if (focusedClipboardActivities.isNotEmpty() && clipboardCleanupPending) clear()
    }
}

internal fun createSensitiveClipboardClip(content: String, token: String): ClipData {
    val clip = ClipData.newPlainText("secure_content:$token", content)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
        clip.description.extras = PersistableBundle().apply {
            putBoolean("android.content.extra.IS_SENSITIVE", true)
            putString(CLIPBOARD_TOKEN_EXTRA, token)
        }
    }
    return clip
}

internal fun sensitiveClipboardToken(clip: ClipData): String? {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
        clip.description.extras?.getString(CLIPBOARD_TOKEN_EXTRA)?.let { return it }
    }
    val label = clip.description.label?.toString() ?: return null
    return label.takeIf { it.startsWith("secure_content:") }?.removePrefix("secure_content:")
}
