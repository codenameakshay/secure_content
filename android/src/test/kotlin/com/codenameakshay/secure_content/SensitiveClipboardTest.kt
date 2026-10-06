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
        val controller = controller()
        controller.set("same text", 60_000, activity)
        val clipboard = application.getSystemService(ClipboardManager::class.java)
        val sensitiveToken = sensitiveClipboardToken(clipboard.primaryClip!!)

        clipboard.setPrimaryClip(ClipData.newPlainText("another app", "same text"))
        focusListener(controller, activity).onWindowFocusChanged(true)
        controller.clear()

        assertNotEquals(sensitiveToken, sensitiveClipboardToken(clipboard.primaryClip!!))
        assertEquals("same text", clipboard.primaryClip!!.getItemAt(0).text)
        assertNull(ReflectionHelpers.getField(controller, "lastSensitiveClipboardToken"))
    }

    @Test
    @Config(sdk = [23])
    fun api23UsesClipLabelForClipboardOwnership() {
        val clip = createSensitiveClipboardClip("secret", "owned-clip-token")

        assertEquals("owned-clip-token", sensitiveClipboardToken(clip))
    }

    @Test
    fun expiryWaitsForForegroundClipboardAccessThenClearsItsOwnClip() {
        val controller = controller()
        controller.set("secret", 10, activity)
        val focusListener = focusListener(controller, activity)
        focusListener.onWindowFocusChanged(false)
        controller.clear()

        shadowOf(Looper.getMainLooper()).idleFor(20, TimeUnit.MILLISECONDS)

        val clipboard = application.getSystemService(ClipboardManager::class.java)
        assertEquals("secret", clipboard.primaryClip!!.getItemAt(0).text)
        assertTrue(ReflectionHelpers.getField(controller, "clipboardCleanupPending"))

        focusListener.onWindowFocusChanged(true)

        assertNull(clipboard.primaryClip)
        assertNull(ReflectionHelpers.getField(controller, "lastSensitiveClipboardToken"))
    }

    @Test
    fun engineDetachKeepsDeferredCleanupUntilAnotherActivityGetsFocus() {
        val controller = controller()
        controller.set("secret", 60_000, activity)
        focusListener(controller, activity).onWindowFocusChanged(false)
        controller.clear()

        controller.detachEngine()
        assertTrue(ReflectionHelpers.getField(controller, "lifecycleCallbacksRegistered"))

        val callbacks = ReflectionHelpers.getField<Application.ActivityLifecycleCallbacks>(controller, "appLifecycleCallbacks")
        val activityB = Robolectric.buildActivity(Activity::class.java).setup().get()
        callbacks.onActivityResumed(activityB)
        focusListener(controller, activityB).onWindowFocusChanged(true)

        val clipboard = application.getSystemService(ClipboardManager::class.java)
        assertNull(clipboard.primaryClip)
        assertNull(ReflectionHelpers.getField(controller, "lastSensitiveClipboardToken"))
        assertEquals(false, ReflectionHelpers.getField(controller, "lifecycleCallbacksRegistered"))
    }

    @Test
    fun engineDetachKeepsAnAlreadyResumedActivityFocusListener() {
        val controller = controller()
        controller.set("secret", 60_000, activity)
        val listener = focusListener(controller, activity)
        listener.onWindowFocusChanged(false)
        controller.clear()

        controller.detachEngine()
        assertTrue(focusListeners(controller).containsKey(activity))

        listener.onWindowFocusChanged(true)

        val clipboard = application.getSystemService(ClipboardManager::class.java)
        assertNull(clipboard.primaryClip)
        assertNull(ReflectionHelpers.getField(controller, "lastSensitiveClipboardToken"))
        assertEquals(false, ReflectionHelpers.getField(controller, "lifecycleCallbacksRegistered"))
        assertTrue(focusListeners(controller).isEmpty())
    }

    @Test
    fun activityDetachBeforeEngineDetachKeepsFocusCleanupForResumedHost() {
        val controller = controller()
        controller.set("secret", 60_000, activity)
        val listener = focusListener(controller, activity)
        listener.onWindowFocusChanged(false)
        controller.clear()

        controller.onActivityDetached(activity)
        controller.detachEngine()
        assertTrue(focusListeners(controller).containsKey(activity))
        assertTrue(ReflectionHelpers.getField(controller, "clipboardCleanupPending"))

        listener.onWindowFocusChanged(true)

        val clipboard = application.getSystemService(ClipboardManager::class.java)
        assertNull(clipboard.primaryClip)
        assertNull(ReflectionHelpers.getField(controller, "lastSensitiveClipboardToken"))
        assertEquals(false, ReflectionHelpers.getField(controller, "lifecycleCallbacksRegistered"))
        assertTrue(focusListeners(controller).isEmpty())
    }

    @Test
    fun deferredCleanupAfterEngineDetachPreservesAReplacementClip() {
        val controller = controller()
        controller.set("secret", 60_000, activity)
        focusListener(controller, activity).onWindowFocusChanged(false)
        controller.clear()
        controller.detachEngine()

        val replacement = ClipData.newPlainText("replacement", "keep me")
        application.getSystemService(ClipboardManager::class.java).setPrimaryClip(replacement)
        val callbacks = ReflectionHelpers.getField<Application.ActivityLifecycleCallbacks>(controller, "appLifecycleCallbacks")
        val activityB = Robolectric.buildActivity(Activity::class.java).setup().get()
        callbacks.onActivityResumed(activityB)
        focusListener(controller, activityB).onWindowFocusChanged(true)

        val currentClip = application.getSystemService(ClipboardManager::class.java).primaryClip
        assertEquals("keep me", currentClip!!.getItemAt(0).text)
        assertTrue(focusListeners(controller).isEmpty())
        assertEquals(false, ReflectionHelpers.getField(controller, "lifecycleCallbacksRegistered"))
    }

    @Test
    fun expiryClearsWhenAnEarlierResumedWindowRegainsFocus() {
        val controller = controller()
        val callbacks = ReflectionHelpers.getField<Application.ActivityLifecycleCallbacks>(
            controller,
            "appLifecycleCallbacks",
        )
        val activityB = Robolectric.buildActivity(Activity::class.java).setup().get()
        controller.set("secret", 10, activity)

        callbacks.onActivityResumed(activityB)
        val listeners = focusListeners(controller)
        val listenerB = listeners[activityB]!!
        listenerB.onWindowFocusChanged(true)
        callbacks.onActivityResumed(activity)

        val listenerA = listeners[activity]!!
        listenerB.onWindowFocusChanged(false)
        controller.clear()
        assertTrue(ReflectionHelpers.getField(controller, "clipboardCleanupPending"))

        shadowOf(Looper.getMainLooper()).idleFor(20, TimeUnit.MILLISECONDS)
        assertTrue(ReflectionHelpers.getField(controller, "clipboardCleanupPending"))

        listenerA.onWindowFocusChanged(true)

        val clipboard = application.getSystemService(ClipboardManager::class.java)
        assertNull(clipboard.primaryClip)
        assertNull(ReflectionHelpers.getField(controller, "lastSensitiveClipboardToken"))
    }

    @Test
    @Config(sdk = [23])
    fun api23ExpiryClearsInBackground() {
        val controller = controller()
        controller.set("secret", 10, activity)
        val focusListener = focusListener(controller, activity)
        focusListener.onWindowFocusChanged(false)

        shadowOf(Looper.getMainLooper()).idleFor(20, TimeUnit.MILLISECONDS)

        val clipboard = application.getSystemService(ClipboardManager::class.java)
        assertEquals("", clipboard.primaryClip!!.getItemAt(0).text)
        assertNull(ReflectionHelpers.getField(controller, "lastSensitiveClipboardToken"))
    }

    @Test
    @Config(sdk = [28])
    fun api28ExpiryClearsInBackgroundWithoutRemovingAnExternalSameTextClip() {
        val controller = controller()
        controller.set("secret", 10, activity)
        val focusListener = focusListener(controller, activity)
        focusListener.onWindowFocusChanged(false)
        val clipboard = application.getSystemService(ClipboardManager::class.java)
        clipboard.setPrimaryClip(ClipData.newPlainText("external", "secret"))

        shadowOf(Looper.getMainLooper()).idleFor(20, TimeUnit.MILLISECONDS)

        assertEquals("secret", clipboard.primaryClip!!.getItemAt(0).text)
        assertNull(ReflectionHelpers.getField(controller, "lastSensitiveClipboardToken"))
    }

    @Test
    fun focusedEmptyClipboardReleasesDeferredCleanupOwnership() {
        val controller = controller()
        controller.set("secret", 60_000, activity)
        val focusListener = focusListener(controller, activity)
        focusListener.onWindowFocusChanged(false)
        controller.clear()

        val clipboard = application.getSystemService(ClipboardManager::class.java)
        clipboard.clearPrimaryClip()
        focusListener.onWindowFocusChanged(true)

        assertNull(ReflectionHelpers.getField(controller, "lastSensitiveClipboardToken"))
        assertEquals(false, ReflectionHelpers.getField(controller, "clipboardCleanupPending"))
        assertTrue(focusListeners(controller).isEmpty())
    }

    @Test
    fun hugeTtlDoesNotOverflowIntoAnImmediateClear() {
        val controller = controller()
        controller.set("secret", Long.MAX_VALUE, activity)

        shadowOf(Looper.getMainLooper()).idleFor(1, TimeUnit.SECONDS)

        val clipboard = application.getSystemService(ClipboardManager::class.java)
        assertEquals("secret", clipboard.primaryClip!!.getItemAt(0).text)
        assertTrue(
            ReflectionHelpers.getField<Runnable?>(controller, "clipboardClearRunnable") != null,
        )
    }

    @Test
    fun replacingAnExpiringClipWithNoExpiryCancelsTheOldDeadline() {
        val controller = controller()
        controller.set("first", 10, activity)
        focusListener(controller, activity).onWindowFocusChanged(true)
        controller.set("replacement", 0, activity)

        shadowOf(Looper.getMainLooper()).idleFor(20, TimeUnit.MILLISECONDS)

        val clipboard = application.getSystemService(ClipboardManager::class.java)
        assertEquals("replacement", clipboard.primaryClip!!.getItemAt(0).text)
        assertNull(ReflectionHelpers.getField(controller, "clipboardClearRunnable"))
    }

    @Test
    fun detachedDeferredCleanupReleasesResumedActivityReferencesAndSuppressesEvents() {
        val events = mutableListOf<NativeEvent>()
        val controller = SensitiveClipboard(application, events::add)
        val callbacks = ReflectionHelpers.getField<Application.ActivityLifecycleCallbacks>(
            controller,
            "appLifecycleCallbacks",
        )
        callbacks.onActivityResumed(activity)
        controller.set("secret", 60_000, activity)
        controller.detachEngine()
        assertNull(ReflectionHelpers.getField(controller, "onEvent"))
        assertNull(ReflectionHelpers.getField(controller, "clipboardClearRunnable"))

        focusListener(controller, activity).onWindowFocusChanged(true)

        assertEquals(listOf(NativeEvent.CLIPBOARD_SET), events)
        assertTrue(ReflectionHelpers.getField<Set<Activity>>(controller, "resumedActivities").isEmpty())
        assertTrue(focusListeners(controller).isEmpty())
    }

    private fun controller(): SensitiveClipboard = SensitiveClipboard(application) { }

    private fun focusListeners(
        controller: SensitiveClipboard,
    ): MutableMap<Activity, ViewTreeObserver.OnWindowFocusChangeListener> =
        ReflectionHelpers.getField(controller, "clipboardWindowFocusListeners")

    private fun focusListener(
        controller: SensitiveClipboard,
        activity: Activity,
    ): ViewTreeObserver.OnWindowFocusChangeListener = focusListeners(controller)[activity]!!
}
