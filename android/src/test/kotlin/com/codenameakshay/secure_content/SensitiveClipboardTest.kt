package com.codenameakshay.secure_content

import android.app.Activity
import android.app.Application
import android.content.ClipData
import android.content.ClipboardManager
import android.os.Looper
import android.view.ViewTreeObserver
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.Robolectric
import org.robolectric.util.ReflectionHelpers
import java.util.concurrent.TimeUnit

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [29])
class SensitiveClipboardTest {
    private val application: Application = RuntimeEnvironment.getApplication()
    private val activity: Activity = Robolectric.buildActivity(Activity::class.java).setup().get()

    @Test
    fun tokenDistinguishesAnExternalReplacementWithIdenticalText() {
        val plugin = plugin()
        plugin.setSensitiveClipboard("same text", 60_000)
        val clipboard = application.getSystemService(ClipboardManager::class.java)
        val sensitiveToken = sensitiveClipboardToken(clipboard.primaryClip!!)

        clipboard.setPrimaryClip(ClipData.newPlainText("another app", "same text"))
        plugin.clearSensitiveClipboard()

        assertNotEquals(sensitiveToken, sensitiveClipboardToken(clipboard.primaryClip!!))
        assertEquals("same text", clipboard.primaryClip!!.getItemAt(0).text)
    }

    @Test
    @Config(sdk = [23])
    fun api23UsesClipLabelForClipboardOwnership() {
        val clip = createSensitiveClipboardClip("secret", "owned-clip-token")

        assertEquals("owned-clip-token", sensitiveClipboardToken(clip))
    }

    @Test
    fun expiryWaitsForForegroundClipboardAccessThenClearsItsOwnClip() {
        val plugin = plugin()
        plugin.setSensitiveClipboard("secret", 10)
        val focusListener = focusListener(plugin, activity)
        focusListener.onWindowFocusChanged(false)
        plugin.clearSensitiveClipboard()

        shadowOf(Looper.getMainLooper()).idleFor(20, TimeUnit.MILLISECONDS)

        val clipboard = application.getSystemService(ClipboardManager::class.java)
        assertEquals("secret", clipboard.primaryClip!!.getItemAt(0).text)
        assertTrue(ReflectionHelpers.getField(plugin, "clipboardCleanupPending"))

        focusListener.onWindowFocusChanged(true)

        assertNull(clipboard.primaryClip)
        assertNull(ReflectionHelpers.getField(plugin, "lastSensitiveClipboardToken"))
    }

    @Test
    fun engineDetachKeepsDeferredCleanupUntilAnotherActivityGetsFocus() {
        val plugin = plugin()
        plugin.setSensitiveClipboard("secret", 60_000)
        focusListener(plugin, activity).onWindowFocusChanged(false)
        plugin.clearSensitiveClipboard()

        ReflectionHelpers.setField(plugin, "engineAttached", false)
        ReflectionHelpers.callInstanceMethod<Unit>(plugin, "releaseClipboardObserversAfterEngineDetach")
        assertTrue(ReflectionHelpers.getField(plugin, "lifecycleCallbacksRegistered"))
        assertNull(ReflectionHelpers.getField(plugin, "flutterApi"))

        val callbacks = ReflectionHelpers.getField<Application.ActivityLifecycleCallbacks>(plugin, "appLifecycleCallbacks")
        val activityB = Robolectric.buildActivity(Activity::class.java).setup().get()
        callbacks.onActivityResumed(activityB)
        focusListener(plugin, activityB).onWindowFocusChanged(true)

        val clipboard = application.getSystemService(ClipboardManager::class.java)
        assertNull(clipboard.primaryClip)
        assertNull(ReflectionHelpers.getField(plugin, "lastSensitiveClipboardToken"))
        assertEquals(false, ReflectionHelpers.getField(plugin, "lifecycleCallbacksRegistered"))
    }

    @Test
    fun engineDetachKeepsAnAlreadyResumedActivityFocusListener() {
        val plugin = plugin()
        plugin.setSensitiveClipboard("secret", 60_000)
        val listener = focusListener(plugin, activity)
        listener.onWindowFocusChanged(false)
        plugin.clearSensitiveClipboard()
        ReflectionHelpers.setField(plugin, "engineAttached", false)

        ReflectionHelpers.callInstanceMethod<Unit>(plugin, "releaseClipboardObserversAfterEngineDetach")
        assertTrue(focusListeners(plugin).containsKey(activity))

        listener.onWindowFocusChanged(true)

        val clipboard = application.getSystemService(ClipboardManager::class.java)
        assertNull(clipboard.primaryClip)
        assertNull(ReflectionHelpers.getField(plugin, "lastSensitiveClipboardToken"))
        assertEquals(false, ReflectionHelpers.getField(plugin, "lifecycleCallbacksRegistered"))
        assertTrue(focusListeners(plugin).isEmpty())
    }

    @Test
    fun activityDetachBeforeEngineDetachKeepsFocusCleanupForResumedHost() {
        val plugin = plugin()
        plugin.setSensitiveClipboard("secret", 60_000)
        val listener = focusListener(plugin, activity)
        listener.onWindowFocusChanged(false)
        plugin.clearSensitiveClipboard()

        plugin.onDetachedFromActivity()
        ReflectionHelpers.setField(plugin, "engineAttached", false)
        ReflectionHelpers.callInstanceMethod<Unit>(plugin, "releaseClipboardObserversAfterEngineDetach")
        assertTrue(focusListeners(plugin).containsKey(activity))
        assertTrue(ReflectionHelpers.getField(plugin, "clipboardCleanupPending"))

        listener.onWindowFocusChanged(true)

        val clipboard = application.getSystemService(ClipboardManager::class.java)
        assertNull(clipboard.primaryClip)
        assertNull(ReflectionHelpers.getField(plugin, "lastSensitiveClipboardToken"))
        assertEquals(false, ReflectionHelpers.getField(plugin, "lifecycleCallbacksRegistered"))
        assertTrue(focusListeners(plugin).isEmpty())
    }

    @Test
    fun deferredCleanupAfterEngineDetachPreservesAReplacementClip() {
        val plugin = plugin()
        plugin.setSensitiveClipboard("secret", 60_000)
        focusListener(plugin, activity).onWindowFocusChanged(false)
        plugin.clearSensitiveClipboard()
        ReflectionHelpers.setField(plugin, "engineAttached", false)
        ReflectionHelpers.callInstanceMethod<Unit>(plugin, "releaseClipboardObserversAfterEngineDetach")

        val replacement = ClipData.newPlainText("replacement", "keep me")
        application.getSystemService(ClipboardManager::class.java).setPrimaryClip(replacement)
        val callbacks = ReflectionHelpers.getField<Application.ActivityLifecycleCallbacks>(plugin, "appLifecycleCallbacks")
        val activityB = Robolectric.buildActivity(Activity::class.java).setup().get()
        callbacks.onActivityResumed(activityB)
        focusListener(plugin, activityB).onWindowFocusChanged(true)

        val currentClip = application.getSystemService(ClipboardManager::class.java).primaryClip
        assertEquals("keep me", currentClip!!.getItemAt(0).text)
        assertTrue(focusListeners(plugin).isEmpty())
        assertEquals(false, ReflectionHelpers.getField(plugin, "lifecycleCallbacksRegistered"))
    }

    @Test
    fun expiryClearsWhenAnEarlierResumedWindowRegainsFocus() {
        val plugin = plugin()
        plugin.setSensitiveClipboard("secret", 10)
        val callbacks = ReflectionHelpers.getField<Application.ActivityLifecycleCallbacks>(
            plugin,
            "appLifecycleCallbacks",
        )
        val activityB = Robolectric.buildActivity(Activity::class.java).setup().get()

        // B resumes while A is still the plugin's attached activity. Both windows
        // can remain resumed in multi-window mode, and focus can move independently.
        callbacks.onActivityResumed(activityB)
        val listeners = focusListeners(plugin)
        val listenerB = listeners[activityB]!!
        listenerB.onWindowFocusChanged(true)
        callbacks.onActivityResumed(activity)

        val listenerA = listeners[activity]!!
        listenerB.onWindowFocusChanged(false)
        plugin.clearSensitiveClipboard()
        assertTrue(ReflectionHelpers.getField(plugin, "clipboardCleanupPending"))

        shadowOf(Looper.getMainLooper()).idleFor(20, TimeUnit.MILLISECONDS)
        assertTrue(ReflectionHelpers.getField(plugin, "clipboardCleanupPending"))

        listenerA.onWindowFocusChanged(true)

        val clipboard = application.getSystemService(ClipboardManager::class.java)
        assertNull(clipboard.primaryClip)
        assertNull(ReflectionHelpers.getField(plugin, "lastSensitiveClipboardToken"))
    }

    @Test
    @Config(sdk = [23])
    fun api23ExpiryClearsInBackground() {
        val plugin = plugin()
        plugin.setSensitiveClipboard("secret", 10)
        val focusListener = focusListener(plugin, activity)
        focusListener.onWindowFocusChanged(false)

        shadowOf(Looper.getMainLooper()).idleFor(20, TimeUnit.MILLISECONDS)

        val clipboard = application.getSystemService(ClipboardManager::class.java)
        assertEquals("", clipboard.primaryClip!!.getItemAt(0).text)
        assertNull(ReflectionHelpers.getField(plugin, "lastSensitiveClipboardToken"))
    }

    @Test
    @Config(sdk = [28])
    fun api28ExpiryClearsInBackgroundWithoutRemovingAnExternalSameTextClip() {
        val plugin = plugin()
        plugin.setSensitiveClipboard("secret", 10)
        val focusListener = focusListener(plugin, activity)
        focusListener.onWindowFocusChanged(false)
        val clipboard = application.getSystemService(ClipboardManager::class.java)
        clipboard.setPrimaryClip(ClipData.newPlainText("external", "secret"))

        shadowOf(Looper.getMainLooper()).idleFor(20, TimeUnit.MILLISECONDS)

        assertEquals("secret", clipboard.primaryClip!!.getItemAt(0).text)
        assertNull(ReflectionHelpers.getField(plugin, "lastSensitiveClipboardToken"))
    }

    @Test
    fun focusedEmptyClipboardReleasesDeferredCleanupOwnership() {
        val plugin = plugin()
        plugin.setSensitiveClipboard("secret", 60_000)
        val focusListener = focusListener(plugin, activity)
        focusListener.onWindowFocusChanged(false)
        plugin.clearSensitiveClipboard()

        val clipboard = application.getSystemService(ClipboardManager::class.java)
        clipboard.clearPrimaryClip()
        focusListener.onWindowFocusChanged(true)

        assertNull(ReflectionHelpers.getField(plugin, "lastSensitiveClipboardToken"))
        assertEquals(false, ReflectionHelpers.getField(plugin, "clipboardCleanupPending"))
        assertTrue(focusListeners(plugin).isEmpty())
    }

    @Test
    fun hugeTtlDoesNotOverflowIntoAnImmediateClear() {
        val plugin = plugin()
        plugin.setSensitiveClipboard("secret", Long.MAX_VALUE)

        shadowOf(Looper.getMainLooper()).idleFor(1, TimeUnit.SECONDS)

        val clipboard = application.getSystemService(ClipboardManager::class.java)
        assertEquals("secret", clipboard.primaryClip!!.getItemAt(0).text)
        assertTrue(ReflectionHelpers.getField(plugin, "clipboardClearRunnable") != null)
    }

    private fun plugin(): SecureContentPlugin = SecureContentPlugin().also {
        ReflectionHelpers.setField(it, "appContext", application)
        ReflectionHelpers.setField(it, "activity", activity)
        ReflectionHelpers.setField(it, "clipboardWindowFocused", true)
    }

    private fun focusListeners(
        plugin: SecureContentPlugin,
    ): MutableMap<Activity, ViewTreeObserver.OnWindowFocusChangeListener> =
        ReflectionHelpers.getField(plugin, "clipboardWindowFocusListeners")

    private fun focusListener(
        plugin: SecureContentPlugin,
        activity: Activity,
    ): ViewTreeObserver.OnWindowFocusChangeListener = focusListeners(plugin)[activity]!!
}
