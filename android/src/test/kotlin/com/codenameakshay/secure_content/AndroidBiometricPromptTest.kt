package com.codenameakshay.secure_content

import androidx.biometric.BiometricManager
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class AndroidBiometricPromptTest {
    @Test
    fun api28BiometricPromptIncludesRequiredCancelButton() {
        val plugin = SecureContentPlugin()

        val promptInfo = plugin.createAndroidXPromptInfo(
            "Authenticate",
            BiometricManager.Authenticators.BIOMETRIC_WEAK,
        )

        assertEquals("Authenticate", promptInfo.title)
        assertEquals("Cancel", promptInfo.negativeButtonText)
    }
}
