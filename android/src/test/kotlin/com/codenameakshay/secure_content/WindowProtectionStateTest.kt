package com.codenameakshay.secure_content

import android.app.Activity
import android.graphics.drawable.ColorDrawable
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [23, 30])
class WindowProtectionStateTest {
    @Test
    fun disabledProtectionLeavesHostSecureFlagAndNavigationColorAlone() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val initialColor = 0xff123456.toInt()
        activity.window.navigationBarColor = initialColor
        activity.window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)

        WindowProtectionState().apply(
            activity.window,
            secureEnabled = false,
            appSwitcherProtected = true,
            appSwitcherColor = 0xff000000.toInt(),
        )

        assertTrue((activity.window.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE) != 0)
        assertEquals(initialColor, activity.window.navigationBarColor)
    }

    @Test
    fun disableRestoresHostChangesBeforeNextEnableCycle() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val initialColor = 0xff123456.toInt()
        val updatedHostColor = 0xff654321.toInt()
        val protectionColor = 0xff000000.toInt()
        activity.window.navigationBarColor = initialColor
        val state = WindowProtectionState()

        state.apply(activity.window, true, true, protectionColor)
        assertEquals(protectionColor, activity.window.navigationBarColor)
        state.apply(activity.window, false, true, protectionColor)
        assertEquals(initialColor, activity.window.navigationBarColor)

        activity.window.navigationBarColor = updatedHostColor
        state.apply(activity.window, true, true, protectionColor)
        state.apply(activity.window, false, true, protectionColor)

        assertEquals(updatedHostColor, activity.window.navigationBarColor)
        assertFalse((activity.window.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE) != 0)
    }

    @Test
    fun switcherColorOwnershipStartsAndStopsWhileSecureProtectionContinues() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val initialColor = 0xff123456.toInt()
        val updatedHostColor = 0xff654321.toInt()
        val protectionColor = 0xff000000.toInt()
        activity.window.navigationBarColor = initialColor
        val state = WindowProtectionState()

        state.apply(activity.window, true, false, protectionColor)
        assertEquals(initialColor, activity.window.navigationBarColor)

        state.apply(activity.window, true, true, protectionColor)
        assertEquals(protectionColor, activity.window.navigationBarColor)

        state.apply(activity.window, true, false, protectionColor)
        assertEquals(initialColor, activity.window.navigationBarColor)
        assertTrue((activity.window.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE) != 0)

        activity.window.navigationBarColor = updatedHostColor
        state.apply(activity.window, true, true, protectionColor)
        state.apply(activity.window, true, false, protectionColor)

        assertEquals(updatedHostColor, activity.window.navigationBarColor)
        assertTrue((activity.window.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE) != 0)
    }

    @Test
    fun disablingOneOwnerDoesNotRestoreAnotherOwnersSwitcherColor() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val initialColor = 0xff123456.toInt()
        val firstColor = 0xff000001.toInt()
        val secondColor = 0xff000002.toInt()
        activity.window.navigationBarColor = initialColor
        val firstEngine = WindowProtectionState()
        val secondEngine = WindowProtectionState()

        firstEngine.apply(activity.window, true, true, firstColor)
        secondEngine.apply(activity.window, true, true, secondColor)
        firstEngine.apply(activity.window, true, false, firstColor)

        assertEquals(secondColor, activity.window.navigationBarColor)
        assertTrue((activity.window.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE) != 0)
    }

    @Test
    fun detachRestoresOnlyTheWindowStateOwnedByThePlugin() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val originalColor = 0xff123456.toInt()
        activity.window.navigationBarColor = originalColor
        val state = WindowProtectionState()
        state.apply(activity.window, true, true, 0xff000000.toInt())

        state.restore(activity.window)

        assertEquals(originalColor, activity.window.navigationBarColor)
        assertFalse((activity.window.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE) != 0)
    }

    @Test
    fun oneEngineCannotRemoveAnotherEnginesWindowProtection() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val initialColor = 0xff123456.toInt()
        val firstColor = 0xff000001.toInt()
        val secondColor = 0xff000002.toInt()
        activity.window.navigationBarColor = initialColor
        val firstEngine = WindowProtectionState()
        val secondEngine = WindowProtectionState()

        firstEngine.apply(activity.window, true, true, firstColor)
        secondEngine.apply(activity.window, true, true, secondColor)
        firstEngine.apply(activity.window, false, false, firstColor)

        assertTrue((activity.window.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE) != 0)
        assertEquals(secondColor, activity.window.navigationBarColor)

        secondEngine.restore(activity.window)

        assertFalse((activity.window.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE) != 0)
        assertEquals(initialColor, activity.window.navigationBarColor)
    }

    @Test
    fun mostRecentlyUpdatedOwnerSuppliesColorUntilItDetaches() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val baselineColor = 0xff123456.toInt()
        val firstColor = 0xff000001.toInt()
        val secondColor = 0xff000002.toInt()
        val updatedColor = 0xff000003.toInt()
        activity.window.navigationBarColor = baselineColor
        val first = WindowProtectionState()
        val second = WindowProtectionState()

        first.apply(activity.window, true, true, firstColor)
        second.apply(activity.window, true, true, secondColor)
        first.apply(activity.window, true, true, updatedColor)
        assertEquals(updatedColor, activity.window.navigationBarColor)

        first.restore(activity.window)
        assertEquals(secondColor, activity.window.navigationBarColor)
        assertTrue((activity.window.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE) != 0)
        second.restore(activity.window)
        assertEquals(baselineColor, activity.window.navigationBarColor)
    }

    @Test
    @Config(sdk = [37])
    fun latestSdkPreservesSecureFlagAcrossEngineOwnersAndRestoresTheHostBaseline() {
        for (hostSecure in listOf(false, true)) {
            val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
            if (hostSecure) activity.window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
            val first = WindowProtectionState()
            val second = WindowProtectionState()

            first.apply(activity.window, true, false, 0)
            second.apply(activity.window, true, false, 0)
            first.restore(activity.window)
            assertTrue((activity.window.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE) != 0)

            second.restore(activity.window)
            assertEquals(
                hostSecure,
                (activity.window.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE) != 0,
            )
        }
    }

    @Test
    fun enginesSharingAWindowShareOneCoverAndRestoreTheHostAccessibilityMode() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val decor = activity.window.decorView as ViewGroup
        decor.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
        val hostChildren = decor.children()
        val first = WindowProtectionState()
        val second = WindowProtectionState()

        first.apply(activity.window, true, true, 0xff000001.toInt(), windowInactive = true)
        second.apply(activity.window, true, true, 0xff000002.toInt(), windowInactive = true)
        val cover = decor.children().single { it !in hostChildren }
        assertEquals(0xff000002.toInt(), (cover.background as ColorDrawable).color)

        second.apply(activity.window, true, true, 0xff000002.toInt(), windowInactive = false)
        assertSame(cover, decor.children().single { it !in hostChildren })
        assertEquals(0xff000001.toInt(), (cover.background as ColorDrawable).color)
        assertEquals(View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS, decor.importantForAccessibility)

        first.restore(activity.window)
        assertEquals(hostChildren, decor.children())
        assertEquals(View.IMPORTANT_FOR_ACCESSIBILITY_YES, decor.importantForAccessibility)
        assertTrue((activity.window.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE) != 0)
        second.restore(activity.window)
        assertFalse((activity.window.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE) != 0)
    }

    @Test
    fun reapplyingKeepsTheCoverAboveViewsTheHostAddsLater() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val decor = activity.window.decorView as ViewGroup
        val state = WindowProtectionState()
        state.apply(activity.window, true, true, 0xff000000.toInt(), windowInactive = true)
        val cover = decor.getChildAt(decor.childCount - 1)

        decor.addView(View(activity))
        state.apply(activity.window, true, true, 0xff000000.toInt(), windowInactive = true)

        assertSame(cover, decor.getChildAt(decor.childCount - 1))
        state.restore(activity.window)
    }

    @Test
    fun inactiveWindowWithoutSwitcherProtectionIsNotCovered() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val decor = activity.window.decorView as ViewGroup
        val hostChildren = decor.children()
        val hostAccessibility = decor.importantForAccessibility

        WindowProtectionState().apply(activity.window, true, false, 0xff000000.toInt(), windowInactive = true)

        assertEquals(hostChildren, decor.children())
        assertEquals(hostAccessibility, decor.importantForAccessibility)
    }

    private fun ViewGroup.children(): List<View> = (0 until childCount).map(::getChildAt)
}
