package com.codenameakshay.secure_content

import android.app.Activity
import android.app.Application
import android.content.pm.PackageManager
import android.graphics.drawable.ColorDrawable
import android.hardware.biometrics.BiometricPrompt
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import com.codenameakshay.secure_content.pigeon.ProtectionConfig
import com.codenameakshay.secure_content.pigeon.SecureContentFlutterApi
import com.codenameakshay.secure_content.pigeon.SecureEvent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.android.controller.ActivityController
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowBiometricPrompt
import org.robolectric.shadows.ShadowFingerprintManager
import org.robolectric.shadow.api.Shadow
import org.robolectric.util.ReflectionHelpers
import androidx.biometric.BiometricManager
import androidx.fragment.app.FragmentActivity
import java.lang.reflect.Proxy
import java.nio.ByteBuffer
import java.util.concurrent.Executor

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [30])
@LooperMode(LooperMode.Mode.PAUSED)
class SecureContentPluginLifecycleTest {
    private val application: Application = RuntimeEnvironment.getApplication()
    private val messenger = EventMessenger()
    private val binding = engineBinding(messenger)
    private val plugin = SecureContentPlugin().also { it.onAttachedToEngine(binding) }

    @Test
    fun platformReadyIsEmittedOnceForEachEngineAttachment() {
        val configuration = ProtectionConfig(false, false, 0xff000000)
        plugin.configureProtection(configuration)
        plugin.configureProtection(configuration)
        assertEquals(listOf("platformReady"), messenger.eventTypes)

        plugin.onDetachedFromEngine(binding)
        assertTrue(messenger.handlers.isEmpty())
        plugin.onAttachedToEngine(binding)
        plugin.configureProtection(configuration)

        assertEquals(listOf("platformReady", "platformReady"), messenger.eventTypes)
        plugin.onDetachedFromEngine(binding)
    }

    @Test
    fun configurationChangeRestoresTheOldWindowAndProtectsTheNewWindow() {
        val oldActivity = activity()
        val newActivity = activity()
        val initialColor = 0xff123456.toInt()
        oldActivity.window.navigationBarColor = initialColor
        plugin.onAttachedToActivity(activityBinding(oldActivity))
        plugin.configureProtection(ProtectionConfig(true, true, 0xff000000))
        assertTrue(isSecure(oldActivity))

        plugin.onDetachedFromActivityForConfigChanges()
        assertFalse(isSecure(oldActivity))
        assertEquals(initialColor, oldActivity.window.navigationBarColor)
        plugin.onReattachedToActivityForConfigChanges(activityBinding(newActivity))
        assertTrue(isSecure(newActivity))

        plugin.onDetachedFromEngine(binding)
        assertFalse(isSecure(newActivity))
    }

    @Test
    @Config(sdk = [23, 30, 36])
    fun focusLossCoversTheWholeWindowOpaquelyUntilFocusReturns() {
        val controller = focusedActivity()
        val decor = controller.get().window.decorView as ViewGroup
        val hostChildren = decor.children()
        val hostAccessibility = decor.importantForAccessibility
        plugin.onAttachedToActivity(activityBinding(controller.get()))
        plugin.configureProtection(ProtectionConfig(true, true, 0x80123456))

        controller.windowFocusChanged(false)

        val cover = decor.children().single { it !in hostChildren }
        assertSame(cover, decor.getChildAt(decor.childCount - 1))
        assertEquals(ViewGroup.LayoutParams.MATCH_PARENT, cover.layoutParams.width)
        assertEquals(ViewGroup.LayoutParams.MATCH_PARENT, cover.layoutParams.height)
        assertEquals(0xff123456.toInt(), (cover.background as ColorDrawable).color)
        assertEquals(View.IMPORTANT_FOR_ACCESSIBILITY_NO, cover.importantForAccessibility)
        assertEquals(View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS, decor.importantForAccessibility)
        assertEquals(listOf("platformReady", "appSwitcherProtected"), messenger.eventTypes)

        controller.windowFocusChanged(true)

        assertEquals(hostChildren, decor.children())
        assertEquals(hostAccessibility, decor.importantForAccessibility)
        assertTrue(isSecure(controller.get()))
        assertEquals(listOf("platformReady", "appSwitcherProtected", "appSwitcherUnprotected"), messenger.eventTypes)
        plugin.onDetachedFromEngine(binding)
    }

    @Test
    fun focusLossLeavesTheWindowUncoveredWithoutAppSwitcherProtection() {
        val controller = focusedActivity()
        val decor = controller.get().window.decorView as ViewGroup
        val hostChildren = decor.children()
        plugin.onAttachedToActivity(activityBinding(controller.get()))

        for (config in listOf(ProtectionConfig(true, false, 0xff000000), ProtectionConfig(false, true, 0xff000000))) {
            plugin.configureProtection(config)
            controller.windowFocusChanged(false)
            assertEquals(hostChildren, decor.children())
            controller.windowFocusChanged(true)
        }

        plugin.configureProtection(ProtectionConfig(true, true, 0xff000000))
        controller.windowFocusChanged(false)
        assertEquals(hostChildren.size + 1, decor.childCount)
        plugin.configureProtection(ProtectionConfig(false, true, 0xff000000))

        assertEquals(hostChildren, decor.children())
        assertEquals(listOf("platformReady", "appSwitcherProtected", "appSwitcherUnprotected"), messenger.eventTypes)
        plugin.onDetachedFromEngine(binding)
    }

    @Test
    fun multiWindowFocusLossLeavesTheVisibleAppUncovered() {
        val controller = focusedActivity()
        val decor = controller.get().window.decorView as ViewGroup
        val hostChildren = decor.children()
        plugin.onAttachedToActivity(activityBinding(controller.get()))
        plugin.configureProtection(ProtectionConfig(true, true, 0xff000000))

        shadowOf(controller.get()).setInMultiWindowMode(true)
        controller.windowFocusChanged(false)
        assertEquals(hostChildren, decor.children())

        shadowOf(controller.get()).setInMultiWindowMode(false)
        decor.layout(0, 0, decor.width + 1, decor.height)
        assertEquals(hostChildren.size + 1, decor.childCount)

        shadowOf(controller.get()).setInMultiWindowMode(true)
        decor.layout(0, 0, decor.width - 1, decor.height)
        assertEquals(hostChildren, decor.children())
        assertEquals(listOf("platformReady", "appSwitcherProtected", "appSwitcherUnprotected"), messenger.eventTypes)
        plugin.onDetachedFromEngine(binding)
    }

    @Test
    fun configurationChangeRemovesTheOldCoverAndWaitsForTheNewWindowToLoseFocus() {
        val oldController = focusedActivity()
        val oldDecor = oldController.get().window.decorView as ViewGroup
        val oldChildren = oldDecor.children()
        val oldAccessibility = oldDecor.importantForAccessibility
        plugin.onAttachedToActivity(activityBinding(oldController.get()))
        plugin.configureProtection(ProtectionConfig(true, true, 0xff000000))
        oldController.windowFocusChanged(false)

        plugin.onDetachedFromActivityForConfigChanges()
        assertEquals(oldChildren, oldDecor.children())
        assertEquals(oldAccessibility, oldDecor.importantForAccessibility)
        assertEquals(listOf("platformReady", "appSwitcherProtected", "appSwitcherUnprotected"), messenger.eventTypes)
        val newController = focusedActivity()
        val newDecor = newController.get().window.decorView as ViewGroup
        val newChildren = newDecor.children()
        plugin.onReattachedToActivityForConfigChanges(activityBinding(newController.get()))
        assertEquals(newChildren, newDecor.children())
        oldController.windowFocusChanged(true)
        oldController.windowFocusChanged(false)
        assertEquals(oldChildren, oldDecor.children())
        assertEquals(newChildren, newDecor.children())

        newController.windowFocusChanged(false)

        assertEquals(newChildren.size + 1, newDecor.childCount)
        assertEquals(
            listOf("platformReady", "appSwitcherProtected", "appSwitcherUnprotected", "appSwitcherProtected"),
            messenger.eventTypes,
        )
        plugin.onDetachedFromEngine(binding)
        assertEquals(newChildren, newDecor.children())
    }

    @Test
    fun engineDetachRemovesTheCoverAndStopsObservingTheWindow() {
        val controller = focusedActivity()
        val decor = controller.get().window.decorView as ViewGroup
        val hostChildren = decor.children()
        val hostAccessibility = decor.importantForAccessibility
        plugin.onAttachedToActivity(activityBinding(controller.get()))
        plugin.configureProtection(ProtectionConfig(true, true, 0xff000000))
        controller.windowFocusChanged(false)

        plugin.onDetachedFromEngine(binding)
        assertEquals(hostChildren, decor.children())
        assertEquals(hostAccessibility, decor.importantForAccessibility)
        controller.windowFocusChanged(true)
        controller.windowFocusChanged(false)

        assertEquals(hostChildren, decor.children())
        assertEquals(listOf("platformReady", "appSwitcherProtected"), messenger.eventTypes)
    }

    @Test
    fun sharedWindowCoverEventsBelongToEachEngineRequest() {
        val controller = focusedActivity()
        val decor = controller.get().window.decorView as ViewGroup
        val hostChildren = decor.children()
        val hostAccessibility = decor.importantForAccessibility
        val secondMessenger = EventMessenger()
        val secondBinding = engineBinding(secondMessenger)
        val secondPlugin = SecureContentPlugin().also { it.onAttachedToEngine(secondBinding) }
        try {
            plugin.onAttachedToActivity(activityBinding(controller.get()))
            secondPlugin.onAttachedToActivity(activityBinding(controller.get()))
            plugin.configureProtection(ProtectionConfig(true, true, 0xff000000))
            secondPlugin.configureProtection(ProtectionConfig(true, true, 0xff123456))
            controller.windowFocusChanged(false)
            val cover = decor.children().single { it !in hostChildren }
            assertEquals(listOf("platformReady", "appSwitcherProtected"), messenger.eventTypes)
            assertEquals(listOf("platformReady", "appSwitcherProtected"), secondMessenger.eventTypes)

            plugin.configureProtection(ProtectionConfig(false, true, 0xff000000))
            assertEquals(listOf("platformReady", "appSwitcherProtected", "appSwitcherUnprotected"), messenger.eventTypes)
            assertEquals(listOf("platformReady", "appSwitcherProtected"), secondMessenger.eventTypes)
            assertSame(cover, decor.children().single { it !in hostChildren })
            assertEquals(0xff123456.toInt(), (cover.background as ColorDrawable).color)
            assertTrue(isSecure(controller.get()))
            assertEquals(View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS, decor.importantForAccessibility)

            secondPlugin.onDetachedFromEngine(secondBinding)
            assertEquals(hostChildren, decor.children())
            assertFalse(isSecure(controller.get()))
            assertEquals(hostAccessibility, decor.importantForAccessibility)
            controller.windowFocusChanged(true).windowFocusChanged(false)
            assertEquals(hostChildren, decor.children())
            assertEquals(listOf("platformReady", "appSwitcherProtected"), secondMessenger.eventTypes)

            plugin.configureProtection(ProtectionConfig(true, true, 0xff000000))
            assertEquals(hostChildren.size + 1, decor.childCount)
            assertTrue(isSecure(controller.get()))
            assertEquals(View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS, decor.importantForAccessibility)
            plugin.onDetachedFromActivity()
            assertEquals(hostChildren, decor.children())
            assertFalse(isSecure(controller.get()))
            assertEquals(hostAccessibility, decor.importantForAccessibility)
            assertEquals(
                listOf("platformReady", "appSwitcherProtected", "appSwitcherUnprotected", "appSwitcherProtected", "appSwitcherUnprotected"),
                messenger.eventTypes,
            )
            assertEquals(listOf("platformReady", "appSwitcherProtected"), secondMessenger.eventTypes)
        } finally {
            plugin.onDetachedFromEngine(binding)
            secondPlugin.onDetachedFromEngine(secondBinding)
        }
    }

    @Test
    fun activityAttachedBeforeItsContentViewIsObservedWithoutInstallingTheDecorEarly() {
        var decorAfterAttach: View? = null
        AttachDuringCreateActivity.onCreateHook = {
            plugin.onAttachedToActivity(activityBinding(it))
            decorAfterAttach = it.window.peekDecorView()
        }
        val controller = try {
            Robolectric.buildActivity(AttachDuringCreateActivity::class.java).create()
        } finally {
            AttachDuringCreateActivity.onCreateHook = null
        }
        assertNull(decorAfterAttach)
        plugin.configureProtection(ProtectionConfig(true, true, 0xff000000))
        val decor = controller.get().window.decorView as ViewGroup
        val hostChildren = decor.children()

        controller.start().resume().visible()
        shadowOf(Looper.getMainLooper()).idle()

        assertFalse(decor.hasWindowFocus())
        assertEquals(hostChildren, decor.children())
        assertEquals(listOf("platformReady"), messenger.eventTypes)

        controller.windowFocusChanged(true)
        controller.windowFocusChanged(false)

        val cover = decor.children().single { it !in hostChildren }
        assertSame(cover, decor.getChildAt(decor.childCount - 1))
        assertEquals(0xff000000.toInt(), (cover.background as ColorDrawable).color)
        assertEquals(listOf("platformReady", "appSwitcherProtected"), messenger.eventTypes)
        plugin.onDetachedFromEngine(binding)
    }

    @Test
    @Config(sdk = [23, 28, 30, 36])
    fun aLaunchingWindowIsNotCoveredBeforeItsFirstFocusReport() {
        val controller = Robolectric.buildActivity(Activity::class.java).create().start().resume()
        val decor = controller.get().window.decorView as ViewGroup
        val hostChildren = decor.children()
        assertFalse(decor.isAttachedToWindow)
        plugin.onAttachedToActivity(activityBinding(controller.get()))
        plugin.configureProtection(ProtectionConfig(true, true, 0xff123456))

        controller.visible()
        assertTrue(decor.isAttachedToWindow)
        assertFalse(decor.hasWindowFocus())
        assertEquals(hostChildren, decor.children())
        assertEquals(listOf("platformReady"), messenger.eventTypes)

        controller.windowFocusChanged(true)
        plugin.requestBiometricAuth("Authenticate")
        assertEquals(hostChildren, decor.children())
        controller.windowFocusChanged(false)

        assertEquals(hostChildren.size + 1, decor.childCount)
        assertEquals(
            listOf("platformReady", "appSwitcherProtected"),
            messenger.eventTypes.filterNot { it == "biometricUnavailable" },
        )
        plugin.onDetachedFromEngine(binding)
    }

    @Test
    fun aPromptRequestedBeforeTheFirstFocusReportCoversTheLaunchingWindow() {
        val controller = Robolectric.buildActivity(Activity::class.java).create().start().resume()
        val decor = controller.get().window.decorView as ViewGroup
        plugin.onAttachedToActivity(activityBinding(controller.get()))
        plugin.configureProtection(ProtectionConfig(true, true, 0xff123456))
        controller.visible()
        val hostChildren = decor.children()

        plugin.requestBiometricAuth("Authenticate")

        assertNotNull(ShadowBiometricPrompt.getCurrentPrompt())
        assertEquals(hostChildren.size + 1, decor.childCount)
        assertEquals(listOf("platformReady", "appSwitcherProtected"), messenger.eventTypes)
        controller.windowFocusChanged(true)
        assertEquals(hostChildren, decor.children())
        assertEquals(listOf("platformReady", "appSwitcherProtected", "appSwitcherUnprotected"), messenger.eventTypes)
        plugin.onDetachedFromEngine(binding)
    }

    @Test
    fun aPromptRequestedWhileFocusedWaitsForThePromptToTakeFocus() {
        val controller = focusedActivity()
        val decor = controller.get().window.decorView as ViewGroup
        val hostChildren = decor.children()
        plugin.onAttachedToActivity(activityBinding(controller.get()))
        plugin.configureProtection(ProtectionConfig(true, true, 0xff123456))

        plugin.requestBiometricAuth("Authenticate")
        assertEquals(hostChildren, decor.children())
        controller.windowFocusChanged(false)

        assertEquals(hostChildren.size + 1, decor.childCount)
        assertEquals(listOf("platformReady", "appSwitcherProtected"), messenger.eventTypes)
        plugin.onDetachedFromEngine(binding)
    }

    @Test
    fun anAttachedWindowWithoutFocusIsCoveredWhenThePluginAttaches() {
        val controller = Robolectric.buildActivity(Activity::class.java).setup()
        val decor = controller.get().window.decorView as ViewGroup
        val hostChildren = decor.children()
        assertTrue(decor.isAttachedToWindow)
        assertFalse(decor.hasWindowFocus())

        plugin.onAttachedToActivity(activityBinding(controller.get()))
        plugin.configureProtection(ProtectionConfig(true, true, 0xff123456))

        assertEquals(hostChildren.size + 1, decor.childCount)
        assertEquals(listOf("appSwitcherProtected", "platformReady"), messenger.eventTypes)
        plugin.onDetachedFromEngine(binding)
    }

    @Test
    fun aNativeDecorChildAddedWhileUnfocusedStaysBelowTheCover() {
        val controller = focusedActivity()
        val decor = controller.get().window.decorView as ViewGroup
        val hostChildren = decor.children()
        plugin.onAttachedToActivity(activityBinding(controller.get()))
        plugin.configureProtection(ProtectionConfig(true, true, 0xff123456))
        controller.windowFocusChanged(false)
        val cover = decor.children().single { it !in hostChildren }
        val nativeContent = View(controller.get()).apply { setBackgroundColor(0xffff0000.toInt()) }

        decor.addView(nativeContent, ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
        decor.layout(0, 0, decor.width + 1, decor.height + 1)
        decor.viewTreeObserver.dispatchOnPreDraw()

        assertSame(cover, decor.getChildAt(decor.childCount - 1))
        assertSame(nativeContent, decor.getChildAt(decor.childCount - 2))
        assertEquals(listOf("platformReady", "appSwitcherProtected"), messenger.eventTypes)
        controller.windowFocusChanged(true)
        assertEquals(hostChildren + nativeContent, decor.children())
        assertEquals(listOf("platformReady", "appSwitcherProtected", "appSwitcherUnprotected"), messenger.eventTypes)
        plugin.onDetachedFromEngine(binding)
    }

    @Test
    fun detachingBeforeDeferredObservationDoesNotObserveTheOldWindow() {
        AttachDuringCreateActivity.onCreateHook = {
            plugin.onAttachedToActivity(activityBinding(it))
            assertNull(it.window.peekDecorView())
            plugin.onDetachedFromActivity()
        }
        val controller = try {
            Robolectric.buildActivity(AttachDuringCreateActivity::class.java).create().start().resume().visible()
        } finally {
            AttachDuringCreateActivity.onCreateHook = null
        }
        val decor = controller.get().window.decorView as ViewGroup
        val hostChildren = decor.children()
        plugin.configureProtection(ProtectionConfig(true, true, 0xff000000))

        shadowOf(Looper.getMainLooper()).idle()
        controller.windowFocusChanged(true).windowFocusChanged(false)

        assertEquals(hostChildren, decor.children())
        assertFalse(isSecure(controller.get()))
        assertEquals(listOf("platformReady"), messenger.eventTypes)
        plugin.onDetachedFromEngine(binding)
    }

    @Test
    fun reattachingADifferentActivityBeforeDeferredObservationIgnoresTheOldWindow() {
        AttachDuringCreateActivity.onCreateHook = {
            plugin.onAttachedToActivity(activityBinding(it))
            assertNull(it.window.peekDecorView())
            plugin.onDetachedFromActivityForConfigChanges()
        }
        val oldController = try {
            Robolectric.buildActivity(AttachDuringCreateActivity::class.java).create().start().resume().visible()
        } finally {
            AttachDuringCreateActivity.onCreateHook = null
        }
        val oldDecor = oldController.get().window.decorView as ViewGroup
        val oldChildren = oldDecor.children()
        val newController = focusedActivity()
        val newDecor = newController.get().window.decorView as ViewGroup
        val newChildren = newDecor.children()
        plugin.onReattachedToActivityForConfigChanges(activityBinding(newController.get()))
        plugin.configureProtection(ProtectionConfig(true, true, 0xff000000))

        shadowOf(Looper.getMainLooper()).idle()
        oldController.windowFocusChanged(true).windowFocusChanged(false)

        assertEquals(oldChildren, oldDecor.children())
        assertEquals(newChildren, newDecor.children())
        assertFalse(isSecure(oldController.get()))
        newController.windowFocusChanged(false)
        assertEquals(newChildren.size + 1, newDecor.childCount)
        assertEquals(listOf("platformReady", "appSwitcherProtected"), messenger.eventTypes)
        plugin.onDetachedFromEngine(binding)
    }

    @Test
    fun reattachingTheSameActivityBeforeDeferredObservationRegistersOneFocusListener() {
        AttachDuringCreateActivity.onCreateHook = {
            plugin.onAttachedToActivity(activityBinding(it))
            plugin.onDetachedFromActivityForConfigChanges()
            plugin.onReattachedToActivityForConfigChanges(activityBinding(it))
            assertNull(it.window.peekDecorView())
        }
        val controller = try {
            Robolectric.buildActivity(AttachDuringCreateActivity::class.java).create().start().resume().visible()
        } finally {
            AttachDuringCreateActivity.onCreateHook = null
        }
        shadowOf(Looper.getMainLooper()).idle()
        val decor = controller.get().window.decorView as ViewGroup
        val listener = ReflectionHelpers.getField<Any>(plugin, "focusListener")
        val listeners = ReflectionHelpers.getField<List<Any>>(decor.viewTreeObserver, "mOnWindowFocusListeners")
        assertEquals(1, listeners.count { it === listener })
        controller.windowFocusChanged(true)
        val hostChildren = decor.children()
        plugin.configureProtection(ProtectionConfig(true, true, 0xff000000))

        controller.windowFocusChanged(false)
        repeat(3) { decor.layout(0, 0, decor.width + 1, decor.height + 1) }

        assertEquals(hostChildren.size + 1, decor.childCount)
        assertEquals(listOf("platformReady", "appSwitcherProtected"), messenger.eventTypes)
        controller.windowFocusChanged(true)
        assertEquals(hostChildren, decor.children())
        assertEquals(listOf("platformReady", "appSwitcherProtected", "appSwitcherUnprotected"), messenger.eventTypes)
        plugin.onDetachedFromEngine(binding)
    }

    @Test
    fun duplicateBiometricRequestsShareOnePromptAndOneOutcome() {
        plugin.onAttachedToActivity(activityBinding(activity()))
        plugin.requestBiometricAuth("First request")
        val prompt = ShadowBiometricPrompt.getCurrentPrompt()
        assertNotNull(prompt)
        assertEquals(
            BiometricManager.Authenticators.BIOMETRIC_WEAK or
                BiometricManager.Authenticators.DEVICE_CREDENTIAL,
            prompt!!.allowedAuthenticators,
        )

        plugin.requestBiometricAuth("Second request")
        assertSame(prompt, ShadowBiometricPrompt.getCurrentPrompt())
        ShadowBiometricPrompt.failCurrentSessionOnce()
        shadowOf(Looper.getMainLooper()).idle()
        assertTrue(messenger.events.isEmpty())

        ShadowBiometricPrompt.authenticateCurrentSessionSuccessfully()
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(listOf("biometricAuthSucceeded"), messenger.eventTypes)
        plugin.onDetachedFromEngine(binding)
    }

    @Test
    fun activityDetachCancelsAuthenticationAndIgnoresQueuedSuccess() {
        plugin.onAttachedToActivity(activityBinding(activity()))
        plugin.requestBiometricAuth("Authenticate")
        assertNotNull(ShadowBiometricPrompt.getCurrentPrompt())
        ShadowBiometricPrompt.authenticateCurrentSessionSuccessfully()

        plugin.onDetachedFromActivityForConfigChanges()
        shadowOf(Looper.getMainLooper()).idle()

        assertEquals(listOf("biometricUnavailable"), messenger.eventTypes)
        plugin.onDetachedFromEngine(binding)
    }

    @Test
    fun engineDetachCancelsAuthenticationWithoutSendingToDetachedDart() {
        plugin.onAttachedToActivity(activityBinding(activity()))
        plugin.requestBiometricAuth("Authenticate")
        assertNotNull(ShadowBiometricPrompt.getCurrentPrompt())

        plugin.onDetachedFromEngine(binding)
        shadowOf(Looper.getMainLooper()).idle()

        assertNull(ShadowBiometricPrompt.getCurrentPrompt())
        assertTrue(messenger.events.isEmpty())
        assertTrue(messenger.handlers.isEmpty())
    }

    @Test
    fun finishingActivityCannotOpenAnAuthenticationPrompt() {
        val activity = activity()
        plugin.onAttachedToActivity(activityBinding(activity))
        activity.finish()

        plugin.requestBiometricAuth("Authenticate")

        assertNull(ShadowBiometricPrompt.getCurrentPrompt())
        assertEquals(listOf("biometricUnavailable"), messenger.eventTypes)
        plugin.onDetachedFromEngine(binding)
    }

    @Test
    fun repeatedTerminalCallbacksEmitOnlyOneBiometricOutcome() {
        plugin.onAttachedToActivity(activityBinding(activity()))
        plugin.requestBiometricAuth("Authenticate")
        val session = ReflectionHelpers.getStaticField<Any>(
            ShadowBiometricPrompt::class.java,
            "currentAuthenticateSession",
        )
        val callback = ReflectionHelpers.getField<BiometricPrompt.AuthenticationCallback>(session, "callback")

        callback.onAuthenticationError(BiometricPrompt.BIOMETRIC_ERROR_CANCELED, "Canceled")
        callback.onAuthenticationSucceeded(null)

        assertEquals(listOf("biometricAuthFailed"), messenger.eventTypes)
        plugin.onDetachedFromEngine(binding)
    }

    @Test
    @Config(sdk = [23])
    fun api23FragmentActivityAuthenticatesWithAndroidXFingerprint() {
        val fingerprint = configureFingerprint()
        val activityController = Robolectric.buildActivity(FragmentActivity::class.java)
        activityController.get().setTheme(androidx.appcompat.R.style.Theme_AppCompat_DayNight_NoActionBar)
        val activity = activityController.setup().get()
        plugin.onAttachedToActivity(activityBinding(activity))

        plugin.requestBiometricAuth("Authenticate")
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(emptyList<String>(), messenger.eventTypes)
        fingerprint.authenticationSucceeds()
        shadowOf(Looper.getMainLooper()).idle()

        assertEquals(listOf("biometricAuthSucceeded"), messenger.eventTypes)
        plugin.onDetachedFromEngine(binding)
    }

    @Test
    @Config(sdk = [23, 27])
    fun nonAppCompatFingerprintHostReturnsUnavailableWithoutCrashingTheMainQueue() {
        configureFingerprint()
        val activityController = Robolectric.buildActivity(FragmentActivity::class.java)
        activityController.get().setTheme(android.R.style.Theme_Material_Light_NoActionBar)
        plugin.onAttachedToActivity(activityBinding(activityController.setup().get()))

        plugin.requestBiometricAuth("Authenticate")
        shadowOf(Looper.getMainLooper()).idle()

        assertEquals(listOf("biometricUnavailable"), messenger.eventTypes)
        plugin.onDetachedFromEngine(binding)
    }

    @Test
    fun savedFragmentStateReturnsUnavailableInsteadOfLeavingARequestPending() {
        val controller = Robolectric.buildActivity(FragmentActivity::class.java).setup()
        plugin.onAttachedToActivity(activityBinding(controller.get()))
        controller.pause().saveInstanceState(android.os.Bundle())

        plugin.requestBiometricAuth("Authenticate")

        assertEquals(listOf("biometricUnavailable"), messenger.eventTypes)
        plugin.onDetachedFromEngine(binding)
    }

    @Test
    fun enginesSharingAFragmentActivityCannotReceiveEachOthersAuthentication() {
        val activity = Robolectric.buildActivity(FragmentActivity::class.java).setup().get()
        val secondMessenger = EventMessenger()
        val secondBinding = engineBinding(secondMessenger)
        val secondPlugin = SecureContentPlugin().also { it.onAttachedToEngine(secondBinding) }
        plugin.onAttachedToActivity(activityBinding(activity))
        secondPlugin.onAttachedToActivity(activityBinding(activity))

        try {
            plugin.requestBiometricAuth("First engine")
            shadowOf(Looper.getMainLooper()).idle()
            val firstPrompt = ShadowBiometricPrompt.getCurrentPrompt()
            assertNotNull(firstPrompt)
            secondPlugin.requestBiometricAuth("Second engine")
            shadowOf(Looper.getMainLooper()).idle()

            assertSame(firstPrompt, ShadowBiometricPrompt.getCurrentPrompt())
            assertTrue(messenger.events.isEmpty())
            assertEquals(listOf("biometricUnavailable"), secondMessenger.eventTypes)

            ShadowBiometricPrompt.authenticateCurrentSessionSuccessfully()
            shadowOf(Looper.getMainLooper()).idle()
            assertEquals(listOf("biometricAuthSucceeded"), messenger.eventTypes)
            assertEquals(listOf("biometricUnavailable"), secondMessenger.eventTypes)

            secondPlugin.requestBiometricAuth("Second engine retry")
            shadowOf(Looper.getMainLooper()).idle()
            assertNotNull(ShadowBiometricPrompt.getCurrentPrompt())
            ShadowBiometricPrompt.authenticateCurrentSessionSuccessfully()
            shadowOf(Looper.getMainLooper()).idle()

            assertEquals(listOf("biometricAuthSucceeded"), messenger.eventTypes)
            assertEquals(listOf("biometricUnavailable", "biometricAuthSucceeded"), secondMessenger.eventTypes)
        } finally {
            plugin.onDetachedFromEngine(binding)
            secondPlugin.onDetachedFromEngine(secondBinding)
        }
    }

    @Test
    fun cancellationReleasesSharedActivityAuthenticationOwnership() {
        val activity = activity()
        val secondMessenger = EventMessenger()
        val secondBinding = engineBinding(secondMessenger)
        val secondPlugin = SecureContentPlugin().also { it.onAttachedToEngine(secondBinding) }
        plugin.onAttachedToActivity(activityBinding(activity))
        secondPlugin.onAttachedToActivity(activityBinding(activity))

        try {
            plugin.requestBiometricAuth("First engine")
            val firstPrompt = ShadowBiometricPrompt.getCurrentPrompt()
            assertNotNull(firstPrompt)
            secondPlugin.requestBiometricAuth("Second engine")
            assertSame(firstPrompt, ShadowBiometricPrompt.getCurrentPrompt())
            assertEquals(listOf("biometricUnavailable"), secondMessenger.eventTypes)

            plugin.onDetachedFromActivity()
            shadowOf(Looper.getMainLooper()).idle()
            assertNull(ShadowBiometricPrompt.getCurrentPrompt())
            assertEquals(listOf("biometricUnavailable"), messenger.eventTypes)

            secondPlugin.requestBiometricAuth("Second engine retry")
            assertNotNull(ShadowBiometricPrompt.getCurrentPrompt())
            ShadowBiometricPrompt.authenticateCurrentSessionSuccessfully()
            shadowOf(Looper.getMainLooper()).idle()

            assertEquals(listOf("biometricUnavailable"), messenger.eventTypes)
            assertEquals(listOf("biometricUnavailable", "biometricAuthSucceeded"), secondMessenger.eventTypes)
        } finally {
            plugin.onDetachedFromEngine(binding)
            secondPlugin.onDetachedFromEngine(secondBinding)
        }
    }

    @Test
    fun failedPromptStartupReleasesSharedActivityAuthenticationOwnership() {
        val activity = Robolectric.buildActivity(UnavailableExecutorActivity::class.java).setup().get()
        val secondMessenger = EventMessenger()
        val secondBinding = engineBinding(secondMessenger)
        val secondPlugin = SecureContentPlugin().also { it.onAttachedToEngine(secondBinding) }
        plugin.onAttachedToActivity(activityBinding(activity))
        secondPlugin.onAttachedToActivity(activityBinding(activity))

        try {
            activity.executorUnavailable = true
            plugin.requestBiometricAuth("First engine")
            assertEquals(listOf("biometricUnavailable"), messenger.eventTypes)
            assertNull(ShadowBiometricPrompt.getCurrentPrompt())

            activity.executorUnavailable = false
            secondPlugin.requestBiometricAuth("Second engine")
            assertNotNull(ShadowBiometricPrompt.getCurrentPrompt())
            ShadowBiometricPrompt.authenticateCurrentSessionSuccessfully()
            shadowOf(Looper.getMainLooper()).idle()

            assertEquals(listOf("biometricUnavailable"), messenger.eventTypes)
            assertEquals(listOf("biometricAuthSucceeded"), secondMessenger.eventTypes)
        } finally {
            plugin.onDetachedFromEngine(binding)
            secondPlugin.onDetachedFromEngine(secondBinding)
        }
    }

    @Test
    fun canceledAndroidXOwnerKeepsItsLeaseUntilQueuedTerminalCallbacksDrain() {
        val activity = Robolectric.buildActivity(FragmentActivity::class.java).setup().get()
        val secondMessenger = EventMessenger()
        val secondBinding = engineBinding(secondMessenger)
        val secondPlugin = SecureContentPlugin().also { it.onAttachedToEngine(secondBinding) }
        plugin.onAttachedToActivity(activityBinding(activity))
        secondPlugin.onAttachedToActivity(activityBinding(activity))

        try {
            plugin.requestBiometricAuth("First engine")
            shadowOf(Looper.getMainLooper()).idle()
            val firstPrompt = ShadowBiometricPrompt.getCurrentPrompt()
            assertNotNull(firstPrompt)
            ShadowBiometricPrompt.authenticateCurrentSessionSuccessfully()

            plugin.onDetachedFromActivity()
            secondPlugin.requestBiometricAuth("Second engine before callback drains")
            assertEquals(listOf("biometricUnavailable"), messenger.eventTypes)
            assertEquals(listOf("biometricAuthFailed"), secondMessenger.eventTypes)
            assertNull(ownershipKey(secondPlugin))

            shadowOf(Looper.getMainLooper()).idle()
            assertEquals(listOf("biometricUnavailable"), messenger.eventTypes)
            assertEquals(listOf("biometricAuthFailed"), secondMessenger.eventTypes)

            secondPlugin.requestBiometricAuth("Second engine after callback drains")
            shadowOf(Looper.getMainLooper()).idle()
            val secondPrompt = ShadowBiometricPrompt.getCurrentPrompt()
            assertNotNull(secondPrompt)
            assertNotSame(firstPrompt, secondPrompt)
            ShadowBiometricPrompt.authenticateCurrentSessionSuccessfully()
            shadowOf(Looper.getMainLooper()).idle()

            assertEquals(listOf("biometricUnavailable"), messenger.eventTypes)
            assertEquals(listOf("biometricAuthFailed", "biometricAuthSucceeded"), secondMessenger.eventTypes)
        } finally {
            plugin.onDetachedFromEngine(binding)
            secondPlugin.onDetachedFromEngine(secondBinding)
        }
    }

    @Test
    fun canceledSelfLeaseReportsUnavailableWhenItsCurrentHostIsInvalid() {
        val nullHostEvents = mutableListOf<NativeEvent>()
        val nullHostActivity = Robolectric.buildActivity(FragmentActivity::class.java).setup().get()
        val nullHostAuthentication = BiometricAuthentication(nullHostEvents::add)
        nullHostAuthentication.request(nullHostActivity, "Authenticate")
        shadowOf(Looper.getMainLooper()).idle()
        nullHostAuthentication.cancel(emitEvent = false)
        val nullHostOwnership = ReflectionHelpers.getField<Any>(nullHostAuthentication, "ownershipKey")
        nullHostAuthentication.request(null, "Retry without a host")
        assertEquals(listOf(NativeEvent.BIOMETRIC_UNAVAILABLE), nullHostEvents)
        assertSame(nullHostOwnership, ReflectionHelpers.getField(nullHostAuthentication, "ownershipKey"))
        assertTrue(ReflectionHelpers.getField<Boolean>(nullHostAuthentication, "cancellationPending"))

        val finishingEvents = mutableListOf<NativeEvent>()
        val finishingActivity = Robolectric.buildActivity(FragmentActivity::class.java).setup().get()
        val finishingAuthentication = BiometricAuthentication(finishingEvents::add)
        finishingAuthentication.request(finishingActivity, "Authenticate")
        shadowOf(Looper.getMainLooper()).idle()
        finishingAuthentication.cancel(emitEvent = false)
        val finishingOwnership = ReflectionHelpers.getField<Any>(finishingAuthentication, "ownershipKey")
        finishingActivity.finish()
        finishingAuthentication.request(finishingActivity, "Retry while finishing")
        assertEquals(listOf(NativeEvent.BIOMETRIC_UNAVAILABLE), finishingEvents)
        assertSame(finishingOwnership, ReflectionHelpers.getField(finishingAuthentication, "ownershipKey"))
        assertTrue(ReflectionHelpers.getField<Boolean>(finishingAuthentication, "cancellationPending"))

        val destroyedEvents = mutableListOf<NativeEvent>()
        val destroyedActivity = Robolectric.buildActivity(FragmentActivity::class.java).setup().get()
        val destroyedAuthentication = BiometricAuthentication(destroyedEvents::add)
        destroyedAuthentication.request(destroyedActivity, "Authenticate")
        shadowOf(Looper.getMainLooper()).idle()
        destroyedAuthentication.cancel(emitEvent = false)
        val destroyedOwnership = ReflectionHelpers.getField<Any>(destroyedAuthentication, "ownershipKey")
        ReflectionHelpers.setField(destroyedActivity, "mDestroyed", true)
        destroyedAuthentication.request(destroyedActivity, "Retry after destruction")
        assertEquals(listOf(NativeEvent.BIOMETRIC_UNAVAILABLE), destroyedEvents)
        assertSame(destroyedOwnership, ReflectionHelpers.getField(destroyedAuthentication, "ownershipKey"))
        assertTrue(ReflectionHelpers.getField<Boolean>(destroyedAuthentication, "cancellationPending"))
    }

    @Test
    fun canceledSelfLeaseReportsUnavailableWhenFragmentStateIsSaved() {
        val controller = Robolectric.buildActivity(FragmentActivity::class.java).setup()
        val activity = controller.get()
        val events = mutableListOf<NativeEvent>()
        val authentication = BiometricAuthentication(events::add)
        authentication.request(activity, "Authenticate")
        shadowOf(Looper.getMainLooper()).idle()
        authentication.cancel(emitEvent = false)
        val ownership = ReflectionHelpers.getField<Any>(authentication, "ownershipKey")
        controller.pause().saveInstanceState(android.os.Bundle())

        authentication.request(activity, "Retry after state was saved")

        assertEquals(listOf(NativeEvent.BIOMETRIC_UNAVAILABLE), events)
        assertSame(ownership, ReflectionHelpers.getField(authentication, "ownershipKey"))
        assertTrue(ReflectionHelpers.getField<Boolean>(authentication, "cancellationPending"))
    }

    @Test
    @Config(sdk = [23])
    fun canceledSelfLeaseReportsUnavailableWhenBiometricsBecomeUnavailable() {
        val fingerprint = configureFingerprint()
        val activity = Robolectric.buildActivity(FragmentActivity::class.java)
            .also { it.get().setTheme(androidx.appcompat.R.style.Theme_AppCompat_DayNight_NoActionBar) }
            .setup()
            .get()
        val events = mutableListOf<NativeEvent>()
        val authentication = BiometricAuthentication(events::add)

        authentication.request(activity, "Authenticate")
        shadowOf(Looper.getMainLooper()).idle()
        authentication.cancel(emitEvent = false)
        val ownership = ReflectionHelpers.getField<Any>(authentication, "ownershipKey")
        fingerprint.setIsHardwareDetected(false)
        authentication.request(activity, "Retry without biometrics")

        assertEquals(listOf(NativeEvent.BIOMETRIC_UNAVAILABLE), events)
        assertSame(ownership, ReflectionHelpers.getField(authentication, "ownershipKey"))
        assertTrue(ReflectionHelpers.getField<Boolean>(authentication, "cancellationPending"))
    }

    @Test
    fun destroyingAnAndroidXHostReleasesItsCanceledAuthenticationLease() {
        val activityController = Robolectric.buildActivity(FragmentActivity::class.java).setup()
        plugin.onAttachedToActivity(activityBinding(activityController.get()))
        plugin.requestBiometricAuth("Authenticate")
        shadowOf(Looper.getMainLooper()).idle()
        plugin.onDetachedFromActivity()

        activityController.pause().stop().destroy()

        val authentication = ReflectionHelpers.getField<BiometricAuthentication>(plugin, "biometricAuthentication")
        assertNull(ReflectionHelpers.getField(authentication, "ownedActivity"))
        assertNull(ReflectionHelpers.getField(authentication, "lifecycleObserver"))
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(listOf("biometricUnavailable"), messenger.eventTypes)
        plugin.onDetachedFromEngine(binding)
    }

    @Test
    fun recreatedHostRetainsCanceledOwnershipUntilItsQueuedOutcomeDrains() {
        val firstController = Robolectric.buildActivity(FragmentActivity::class.java).setup()
        val store = firstController.get().viewModelStore
        plugin.onAttachedToActivity(activityBinding(firstController.get()))
        val secondMessenger = EventMessenger()
        val secondBinding = engineBinding(secondMessenger)
        val secondPlugin = SecureContentPlugin().also { it.onAttachedToEngine(secondBinding) }
        var recreatedController: ActivityController<FragmentActivity>? = null

        try {
            plugin.requestBiometricAuth("First engine")
            shadowOf(Looper.getMainLooper()).idle()
            val firstPrompt = ShadowBiometricPrompt.getCurrentPrompt()
            assertNotNull(firstPrompt)
            ShadowBiometricPrompt.authenticateCurrentSessionSuccessfully()
            plugin.onDetachedFromActivityForConfigChanges()

            recreatedController = recreate(firstController)
            val newActivity = recreatedController.get()
            assertSame(store, newActivity.viewModelStore)
            secondPlugin.onAttachedToActivity(activityBinding(newActivity))
            secondPlugin.requestBiometricAuth("Second engine before old outcome drains")

            assertEquals(listOf("biometricUnavailable"), messenger.eventTypes)
            assertEquals(listOf("biometricAuthFailed"), secondMessenger.eventTypes)
            assertNull(ownershipKey(secondPlugin))
            shadowOf(Looper.getMainLooper()).idle()
            assertEquals(listOf("biometricUnavailable"), messenger.eventTypes)
            assertEquals(listOf("biometricAuthFailed"), secondMessenger.eventTypes)

            secondPlugin.requestBiometricAuth("Second engine after old outcome drains")
            shadowOf(Looper.getMainLooper()).idle()
            val secondPrompt = ShadowBiometricPrompt.getCurrentPrompt()
            assertNotNull(secondPrompt)
            assertNotSame(firstPrompt, secondPrompt)
            ShadowBiometricPrompt.authenticateCurrentSessionSuccessfully()
            shadowOf(Looper.getMainLooper()).idle()

            assertEquals(listOf("biometricUnavailable"), messenger.eventTypes)
            assertEquals(listOf("biometricAuthFailed", "biometricAuthSucceeded"), secondMessenger.eventTypes)
        } finally {
            plugin.onDetachedFromEngine(binding)
            secondPlugin.onDetachedFromEngine(secondBinding)
            recreatedController?.pause()?.stop()?.destroy()
        }
    }

    @Test
    fun recreatedHostReportsTheSameEngineCancellationAsAFailedAttempt() {
        val firstController = Robolectric.buildActivity(FragmentActivity::class.java).setup()
        plugin.onAttachedToActivity(activityBinding(firstController.get()))
        var recreatedController: ActivityController<FragmentActivity>? = null

        try {
            plugin.requestBiometricAuth("Before recreation")
            shadowOf(Looper.getMainLooper()).idle()
            val firstPrompt = ShadowBiometricPrompt.getCurrentPrompt()
            assertNotNull(firstPrompt)
            ShadowBiometricPrompt.authenticateCurrentSessionSuccessfully()
            plugin.onDetachedFromActivityForConfigChanges()

            recreatedController = recreate(firstController)
            plugin.onReattachedToActivityForConfigChanges(activityBinding(recreatedController.get()))
            plugin.requestBiometricAuth("Before the old outcome drains")
            assertEquals(listOf("biometricUnavailable", "biometricAuthFailed"), messenger.eventTypes)

            shadowOf(Looper.getMainLooper()).idle()
            assertEquals(listOf("biometricUnavailable", "biometricAuthFailed"), messenger.eventTypes)
            plugin.requestBiometricAuth("After the old outcome drains")
            shadowOf(Looper.getMainLooper()).idle()
            val secondPrompt = ShadowBiometricPrompt.getCurrentPrompt()
            assertNotNull(secondPrompt)
            assertNotSame(firstPrompt, secondPrompt)
            ShadowBiometricPrompt.authenticateCurrentSessionSuccessfully()
            shadowOf(Looper.getMainLooper()).idle()

            assertEquals(
                listOf("biometricUnavailable", "biometricAuthFailed", "biometricAuthSucceeded"),
                messenger.eventTypes,
            )
        } finally {
            plugin.onDetachedFromEngine(binding)
            recreatedController?.pause()?.stop()?.destroy()
        }
    }

    @Suppress("DEPRECATION")
    private fun recreate(controller: ActivityController<FragmentActivity>): ActivityController<FragmentActivity> {
        val activity = controller.get()
        ReflectionHelpers.setField(activity, "mChangingConfigurations", true)
        val savedState = android.os.Bundle()
        controller.pause().stop().saveInstanceState(savedState)
        val retained = activity.onRetainNonConfigurationInstance()
        controller.destroy()

        val newController = Robolectric.buildActivity(FragmentActivity::class.java)
        shadowOf(newController.get()).setLastNonConfigurationInstance(retained)
        return newController.create(savedState).start().resume()
    }

    private fun ownershipKey(plugin: SecureContentPlugin): Any? = ReflectionHelpers.getField(
        ReflectionHelpers.getField<BiometricAuthentication>(plugin, "biometricAuthentication"),
        "ownershipKey",
    )

    private fun engineBinding(messenger: EventMessenger): FlutterPlugin.FlutterPluginBinding =
        FlutterPlugin.FlutterPluginBinding::class.java.constructors.single()
            .newInstance(application, null, messenger, null, null, null, null) as FlutterPlugin.FlutterPluginBinding

    private fun configureFingerprint(): ShadowFingerprintManager {
        shadowOf(application.packageManager).setSystemFeature(PackageManager.FEATURE_FINGERPRINT, true)
        return Shadow.extract<ShadowFingerprintManager>(application.getSystemService("fingerprint")).also {
            it.setIsHardwareDetected(true)
            it.setDefaultFingerprints(1)
        }
    }

    private fun activity(): Activity = Robolectric.buildActivity(Activity::class.java).setup().get()

    private fun focusedActivity() = Robolectric.buildActivity(Activity::class.java).setup().windowFocusChanged(true)

    private fun ViewGroup.children(): List<View> = (0 until childCount).map(::getChildAt)

    private fun isSecure(activity: Activity): Boolean =
        activity.window.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE != 0

    private fun activityBinding(activity: Activity): ActivityPluginBinding = Proxy.newProxyInstance(
        ActivityPluginBinding::class.java.classLoader,
        arrayOf(ActivityPluginBinding::class.java),
    ) { _, method, _ ->
        check(method.name == "getActivity")
        activity
    } as ActivityPluginBinding

    class AttachDuringCreateActivity : Activity() {
        override fun onCreate(savedInstanceState: android.os.Bundle?) {
            super.onCreate(savedInstanceState)
            onCreateHook?.invoke(this)
            setContentView(View(this))
        }

        companion object {
            var onCreateHook: ((Activity) -> Unit)? = null
        }
    }

    class UnavailableExecutorActivity : Activity() {
        var executorUnavailable = false

        override fun getMainExecutor(): Executor {
            check(!executorUnavailable) { "Main executor unavailable" }
            return super.getMainExecutor()
        }
    }

    private class EventMessenger : BinaryMessenger {
        val events = mutableListOf<SecureEvent>()
        val handlers = mutableMapOf<String, BinaryMessenger.BinaryMessageHandler>()
        val eventTypes: List<String> get() = events.map { it.type }

        override fun send(channel: String, message: ByteBuffer?) = send(channel, message, null)

        override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) {
            val codec = SecureContentFlutterApi.codec
            val arguments = codec.decodeMessage(message?.duplicate()?.apply { flip() }) as List<*>
            events.add(arguments.single() as SecureEvent)
            callback?.reply(codec.encodeMessage(listOf(null))?.apply { flip() })
        }

        override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) {
            if (handler == null) handlers.remove(channel) else handlers[channel] = handler
        }
    }
}
