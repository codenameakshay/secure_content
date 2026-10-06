package com.codenameakshay.secure_content

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
    ) {
        WindowProtectionRegistry.update(
            window = window,
            owner = owner,
            secureEnabled = secureEnabled,
            appSwitcherProtected = appSwitcherProtected,
            appSwitcherColor = appSwitcherColor,
        )
    }

    fun restore(window: Window) {
        WindowProtectionRegistry.remove(window, owner)
    }
}

private object WindowProtectionRegistry {
    private data class Request(
        val appSwitcherProtected: Boolean,
        val appSwitcherColor: Int,
    )

    private data class WindowState(
        val originalSecureFlag: Boolean,
        var originalNavigationBarColor: Int? = null,
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
            restoreBaseline(window, state)
            states.remove(window)
        } else {
            applyAggregate(window, state)
        }
    }

    private fun applyAggregate(window: Window, state: WindowState) {
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        val latestAppSwitcher = state.requests.values.lastOrNull { it.appSwitcherProtected }
        if (latestAppSwitcher != null) {
            window.navigationBarColor = latestAppSwitcher.appSwitcherColor
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
    }

    private fun restoreNavigationBarColor(window: Window, state: WindowState) {
        state.originalNavigationBarColor?.let { window.navigationBarColor = it }
        state.originalNavigationBarColor = null
    }
}
