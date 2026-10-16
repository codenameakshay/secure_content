package com.codenameakshay.secure_content

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.ColorDrawable
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
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
    fun coverDrawsAfterAnElevatedHostDecorChild() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val decor = activity.window.decorView as ViewGroup
        val drawingOrder = mutableListOf<String>()
        val host = View(activity).apply {
            elevation = 12f
            background = object : ColorDrawable(0xffff0000.toInt()) {
                override fun draw(canvas: Canvas) {
                    drawingOrder.add("host")
                    super.draw(canvas)
                }
            }
        }
        decor.addView(host, ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
        val state = WindowProtectionState()
        state.apply(activity.window, true, true, 0xff000000.toInt(), windowInactive = true)
        val cover = decor.getChildAt(decor.childCount - 1)
        cover.background = object : ColorDrawable(0xff000000.toInt()) {
            override fun draw(canvas: Canvas) {
                drawingOrder.add("cover")
                super.draw(canvas)
            }
        }
        val size = View.MeasureSpec.makeMeasureSpec(100, View.MeasureSpec.EXACTLY)
        decor.measure(size, size)
        decor.layout(0, 0, 100, 100)
        decor.viewTreeObserver.dispatchOnPreDraw()

        decor.draw(Canvas(Bitmap.createBitmap(100, 100, Bitmap.Config.ARGB_8888)))

        assertEquals(listOf("host", "cover"), drawingOrder)
        state.restore(activity.window)
    }

    @Test
    fun coverStaysAboveHostChildrenAddedBetweenProtectionUpdates() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val decor = activity.window.decorView as ViewGroup
        val state = WindowProtectionState()
        state.apply(activity.window, true, true, 0xff000000.toInt(), windowInactive = true)
        val cover = decor.getChildAt(decor.childCount - 1)

        decor.addView(View(activity))
        decor.viewTreeObserver.dispatchOnPreDraw()

        assertSame(cover, decor.getChildAt(decor.childCount - 1))
        state.restore(activity.window)
    }

    @Test
    fun reapplyingRepairsTheSecureFlagAndPreservesASecureHostBaseline() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val flag = WindowManager.LayoutParams.FLAG_SECURE
        activity.window.addFlags(flag)
        val state = WindowProtectionState()
        state.apply(activity.window, true, true, 0xff000000.toInt())

        activity.window.clearFlags(flag)
        state.apply(activity.window, true, true, 0xff000000.toInt())

        assertTrue((activity.window.attributes.flags and flag) != 0)
        state.restore(activity.window)
        assertTrue((activity.window.attributes.flags and flag) != 0)
    }

    @Test
    fun restoringProtectionWhileCoverIsAddedDoesNotLeaveAccessibilityHidden() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val decor = activity.window.decorView as ViewGroup
        decor.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
        val hostChildren = decor.children()
        val state = WindowProtectionState()
        decor.setOnHierarchyChangeListener(object : ViewGroup.OnHierarchyChangeListener {
            override fun onChildViewAdded(parent: View, child: View) {
                state.restore(activity.window)
            }

            override fun onChildViewRemoved(parent: View, child: View) = Unit
        })

        state.apply(activity.window, true, true, 0xff000000.toInt(), windowInactive = true)

        assertEquals(hostChildren, decor.children())
        assertEquals(View.IMPORTANT_FOR_ACCESSIBILITY_YES, decor.importantForAccessibility)
        assertFalse((activity.window.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE) != 0)
    }

    @Test
    fun ownerUpdatedWhileCoverIsAddedSuppliesTheLatestOpaqueColor() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val decor = activity.window.decorView as ViewGroup
        val first = WindowProtectionState()
        val second = WindowProtectionState()
        decor.setOnHierarchyChangeListener(object : ViewGroup.OnHierarchyChangeListener {
            override fun onChildViewAdded(parent: View, child: View) {
                second.apply(activity.window, true, true, 0x00123456, windowInactive = true)
            }

            override fun onChildViewRemoved(parent: View, child: View) = Unit
        })

        first.apply(activity.window, true, true, 0xff000000.toInt(), windowInactive = true)

        val cover = decor.getChildAt(decor.childCount - 1)
        assertEquals(0xff123456.toInt(), (cover.background as ColorDrawable).color)
        first.restore(activity.window)
        second.restore(activity.window)
    }

    @Test
    fun ownerEnabledWhileCoverIsRemovedKeepsItsCoverAndCanRestoreTheHost() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val decor = activity.window.decorView as ViewGroup
        decor.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
        val baselineNavigationColor = 0xff123456.toInt()
        activity.window.navigationBarColor = baselineNavigationColor
        val hostChildren = decor.children()
        val first = WindowProtectionState()
        val second = WindowProtectionState()
        first.apply(activity.window, true, true, 0xff000000.toInt(), windowInactive = true)
        decor.setOnHierarchyChangeListener(object : ViewGroup.OnHierarchyChangeListener {
            override fun onChildViewAdded(parent: View, child: View) = Unit

            override fun onChildViewRemoved(parent: View, child: View) {
                second.apply(activity.window, true, true, 0xff654321.toInt(), windowInactive = true)
            }
        })

        first.restore(activity.window)

        assertEquals(1, decor.children().count { it !in hostChildren })
        assertEquals(View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS, decor.importantForAccessibility)
        assertTrue((activity.window.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE) != 0)
        decor.setOnHierarchyChangeListener(null)
        second.restore(activity.window)
        assertEquals(hostChildren, decor.children())
        assertEquals(View.IMPORTANT_FOR_ACCESSIBILITY_YES, decor.importantForAccessibility)
        assertEquals(baselineNavigationColor, activity.window.navigationBarColor)
        assertFalse((activity.window.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE) != 0)
    }

    @Test
    fun removedCoverDoesNotObserveItsFormerWindowsDraws() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val decor = activity.window.decorView as ViewGroup
        val state = WindowProtectionState()
        state.apply(activity.window, true, true, 0xff000000.toInt(), windowInactive = true)
        val cover = decor.getChildAt(decor.childCount - 1)
        state.restore(activity.window)
        val detachedParent = FrameLayout(activity)
        detachedParent.addView(cover)
        val laterChild = View(activity)
        detachedParent.addView(laterChild)

        decor.viewTreeObserver.dispatchOnPreDraw()

        assertSame(laterChild, detachedParent.getChildAt(detachedParent.childCount - 1))
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
