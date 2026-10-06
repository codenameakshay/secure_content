package com.codenameakshay.secure_content

import android.view.Window
import android.view.WindowManager
import java.util.WeakHashMap

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
        val secureEnabled: Boolean,
        val appSwitcherProtected: Boolean,
        val appSwitcherColor: Int,
        val order: Long,
    )

    private data class WindowState(
        val originalSecureFlag: Boolean,
        var originalNavigationBarColor: Int? = null,
        val requests: MutableMap<Any, Request> = mutableMapOf(),
    )

    private val states = WeakHashMap<Window, WindowState>()
    private var requestOrder = 0L

    @Synchronized
    fun update(
        window: Window,
        owner: Any,
        secureEnabled: Boolean,
        appSwitcherProtected: Boolean,
        appSwitcherColor: Int,
    ) {
        val active = secureEnabled
        if (!active) {
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
        state.requests[owner] = Request(
            secureEnabled = secureEnabled,
            appSwitcherProtected = appSwitcherProtected,
            appSwitcherColor = appSwitcherColor,
            order = ++requestOrder,
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
        val flag = WindowManager.LayoutParams.FLAG_SECURE
        if (state.requests.values.any { it.secureEnabled }) {
            window.addFlags(flag)
        } else if (state.originalSecureFlag) {
            window.addFlags(flag)
        } else {
            window.clearFlags(flag)
        }

        val latestAppSwitcher = state.requests.values
            .filter { it.secureEnabled && it.appSwitcherProtected }
            .maxByOrNull { it.order }
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
