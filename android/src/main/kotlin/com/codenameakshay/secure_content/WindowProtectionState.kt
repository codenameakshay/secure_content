package com.codenameakshay.secure_content

import android.content.Context
import android.graphics.Color
import android.view.View
import android.view.ViewGroup
import android.view.ViewTreeObserver
import android.view.Window
import android.view.WindowManager
import androidx.annotation.MainThread
import java.util.WeakHashMap

@MainThread
internal class WindowProtectionState {
    private val owner = Any()

    fun apply(
        window: Window,
        secureEnabled: Boolean,
        appSwitcherProtected: Boolean,
        appSwitcherColor: Int,
        windowInactive: Boolean = false,
    ) {
        WindowProtectionRegistry.update(
            window = window,
            owner = owner,
            secureEnabled = secureEnabled,
            appSwitcherProtected = appSwitcherProtected,
            appSwitcherColor = appSwitcherColor,
            windowInactive = windowInactive,
        )
    }

    fun restore(window: Window) {
        WindowProtectionRegistry.remove(window, owner)
    }
}

private object WindowProtectionRegistry {
    // Found by tag rather than stored, so the weak window keys are never retained.
    private val coverTag = Any()

    private data class Request(
        val appSwitcherProtected: Boolean,
        val appSwitcherColor: Int,
        val coversWindow: Boolean,
    )

    private data class WindowState(
        val originalSecureFlag: Boolean,
        var originalNavigationBarColor: Int? = null,
        var originalImportantForAccessibility: Int? = null,
        val requests: MutableMap<Any, Request> = linkedMapOf(),
    )

    private val states = WeakHashMap<Window, WindowState>()

    @Synchronized
    fun update(
        window: Window,
        owner: Any,
        secureEnabled: Boolean,
        appSwitcherProtected: Boolean,
        appSwitcherColor: Int,
        windowInactive: Boolean,
    ) {
        if (!secureEnabled) {
            remove(window, owner)
            return
        }

        val state = states.getOrPut(window) {
            WindowState(
                originalSecureFlag =
                    (window.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE) != 0,
            )
        }
        val hadSwitcherOwner = state.requests.values.any { it.appSwitcherProtected }
        state.requests.remove(owner)
        state.requests[owner] = Request(
            appSwitcherProtected = appSwitcherProtected,
            appSwitcherColor = appSwitcherColor,
            coversWindow = appSwitcherProtected && windowInactive,
        )
        val hasSwitcherOwner = state.requests.values.any { it.appSwitcherProtected }
        if (!hadSwitcherOwner && hasSwitcherOwner) {
            state.originalNavigationBarColor = window.navigationBarColor
        } else if (hadSwitcherOwner && !hasSwitcherOwner) {
            restoreNavigationBarColor(window, state)
        }
        applyAggregate(window, state)
    }

    @Synchronized
    fun remove(window: Window, owner: Any) {
        val state = states[window] ?: return
        val hadSwitcherOwner = state.requests.values.any { it.appSwitcherProtected }
        state.requests.remove(owner)
        val hasSwitcherOwner = state.requests.values.any { it.appSwitcherProtected }
        if (hadSwitcherOwner && !hasSwitcherOwner) {
            restoreNavigationBarColor(window, state)
        }
        if (state.requests.isEmpty()) {
            states.remove(window)
            restoreBaseline(window, state)
        } else {
            applyAggregate(window, state)
        }
    }

    private fun applyAggregate(window: Window, state: WindowState) {
        val flag = WindowManager.LayoutParams.FLAG_SECURE
        // Focus changes reapply often; an unchanged addFlags still relayouts the window.
        if ((window.attributes.flags and flag) == 0) window.addFlags(flag)
        val latestAppSwitcher = state.requests.values.lastOrNull { it.appSwitcherProtected }
        if (latestAppSwitcher != null) {
            window.navigationBarColor = latestAppSwitcher.appSwitcherColor
        }
        applyCover(window, state)
    }

    private fun applyCover(window: Window, state: WindowState) {
        val decor = window.peekDecorView() as? ViewGroup ?: return
        var cover = (0 until decor.childCount).map(decor::getChildAt).firstOrNull { it.tag === coverTag }
        val color = state.requests.values.lastOrNull { it.coversWindow }?.appSwitcherColor
        if (color == null) {
            state.originalImportantForAccessibility?.let { decor.importantForAccessibility = it }
            state.originalImportantForAccessibility = null
            cover?.let(decor::removeView)
            return
        }
        val needsAdding = cover == null
        if (cover == null) {
            cover = PrivacyCover(decor.context).apply {
                tag = coverTag
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            }
        }
        cover.setBackgroundColor(color or Color.BLACK)
        if (state.originalImportantForAccessibility == null) {
            state.originalImportantForAccessibility = decor.importantForAccessibility
            decor.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        }
        if (needsAdding) {
            decor.addView(cover, ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
        } else if (decor.getChildAt(decor.childCount - 1) !== cover) {
            cover.bringToFront()
        }
    }

    private class PrivacyCover(context: Context) : View(context), ViewTreeObserver.OnPreDrawListener {
        override fun onAttachedToWindow() {
            super.onAttachedToWindow()
            viewTreeObserver.addOnPreDrawListener(this)
        }

        override fun onDetachedFromWindow() {
            viewTreeObserver.removeOnPreDrawListener(this)
            super.onDetachedFromWindow()
        }

        override fun onPreDraw(): Boolean {
            val decor = parent as? ViewGroup ?: return true
            var highestSiblingZ = 0f
            for (index in 0 until decor.childCount) {
                val sibling = decor.getChildAt(index)
                if (sibling !== this) highestSiblingZ = maxOf(highestSiblingZ, sibling.z)
            }
            if (z != highestSiblingZ) z = highestSiblingZ
            if (decor.getChildAt(decor.childCount - 1) !== this) bringToFront()
            return true
        }
    }

    private fun restoreBaseline(window: Window, state: WindowState) {
        val flag = WindowManager.LayoutParams.FLAG_SECURE
        if (state.originalSecureFlag) {
            window.addFlags(flag)
        } else {
            window.clearFlags(flag)
        }
        restoreNavigationBarColor(window, state)
        applyCover(window, state)
    }

    private fun restoreNavigationBarColor(window: Window, state: WindowState) {
        state.originalNavigationBarColor?.let { window.navigationBarColor = it }
        state.originalNavigationBarColor = null
    }
}
