package com.codenameakshay.secure_content

import android.app.Activity
import android.app.Application
import android.content.pm.PackageManager
import android.hardware.biometrics.BiometricPrompt
import android.os.Looper
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
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
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
            assertNotNull(ShadowBiometricPrompt.getCurrentPrompt())
            ShadowBiometricPrompt.authenticateCurrentSessionSuccessfully()

            plugin.onDetachedFromActivity()
            secondPlugin.requestBiometricAuth("Second engine before callback drains")
            assertEquals(listOf("biometricUnavailable"), messenger.eventTypes)
            assertEquals(listOf("biometricUnavailable"), secondMessenger.eventTypes)

            shadowOf(Looper.getMainLooper()).idle()
            assertEquals(listOf("biometricUnavailable"), messenger.eventTypes)
            assertEquals(listOf("biometricUnavailable"), secondMessenger.eventTypes)

            secondPlugin.requestBiometricAuth("Second engine after callback drains")
            shadowOf(Looper.getMainLooper()).idle()
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
    @Suppress("DEPRECATION")
    fun recreatedHostRetainsCanceledOwnershipUntilItsQueuedOutcomeDrains() {
        val firstController = Robolectric.buildActivity(FragmentActivity::class.java).setup()
        val firstActivity = firstController.get()
        val store = firstActivity.viewModelStore
        plugin.onAttachedToActivity(activityBinding(firstActivity))
        val secondMessenger = EventMessenger()
        val secondBinding = engineBinding(secondMessenger)
        val secondPlugin = SecureContentPlugin().also { it.onAttachedToEngine(secondBinding) }
        var recreatedController: org.robolectric.android.controller.ActivityController<FragmentActivity>? = null

        try {
            plugin.requestBiometricAuth("First engine")
            shadowOf(Looper.getMainLooper()).idle()
            assertNotNull(ShadowBiometricPrompt.getCurrentPrompt())
            ShadowBiometricPrompt.authenticateCurrentSessionSuccessfully()
            plugin.onDetachedFromActivityForConfigChanges()

            ReflectionHelpers.setField(firstActivity, "mChangingConfigurations", true)
            val savedState = android.os.Bundle()
            firstController.pause().stop().saveInstanceState(savedState)
            val retained = firstActivity.onRetainNonConfigurationInstance()
            firstController.destroy()

            val newController = Robolectric.buildActivity(FragmentActivity::class.java)
            recreatedController = newController
            val newActivity = newController.get()
            shadowOf(newActivity).setLastNonConfigurationInstance(retained)
            newController.create(savedState).start().resume()
            assertSame(store, newActivity.viewModelStore)
            secondPlugin.onAttachedToActivity(activityBinding(newActivity))
            secondPlugin.requestBiometricAuth("Second engine before old outcome drains")

            assertEquals(listOf("biometricUnavailable"), messenger.eventTypes)
            assertEquals(listOf("biometricUnavailable"), secondMessenger.eventTypes)
            shadowOf(Looper.getMainLooper()).idle()
            assertEquals(listOf("biometricUnavailable"), messenger.eventTypes)
            assertEquals(listOf("biometricUnavailable"), secondMessenger.eventTypes)

            secondPlugin.requestBiometricAuth("Second engine after old outcome drains")
            shadowOf(Looper.getMainLooper()).idle()
            assertNotNull(ShadowBiometricPrompt.getCurrentPrompt())
            ShadowBiometricPrompt.authenticateCurrentSessionSuccessfully()
            shadowOf(Looper.getMainLooper()).idle()

            assertEquals(listOf("biometricUnavailable"), messenger.eventTypes)
            assertEquals(listOf("biometricUnavailable", "biometricAuthSucceeded"), secondMessenger.eventTypes)
        } finally {
            plugin.onDetachedFromEngine(binding)
            secondPlugin.onDetachedFromEngine(secondBinding)
            recreatedController?.pause()?.stop()?.destroy()
        }
    }

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

    private fun isSecure(activity: Activity): Boolean =
        activity.window.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE != 0

    private fun activityBinding(activity: Activity): ActivityPluginBinding = Proxy.newProxyInstance(
        ActivityPluginBinding::class.java.classLoader,
        arrayOf(ActivityPluginBinding::class.java),
    ) { _, method, _ ->
        check(method.name == "getActivity")
        activity
    } as ActivityPluginBinding

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
