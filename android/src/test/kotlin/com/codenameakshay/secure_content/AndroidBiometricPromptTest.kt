package com.codenameakshay.secure_content

import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import com.codenameakshay.secure_content.pigeon.AuthStatus
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
        val promptInfo = createAndroidXPromptInfo(
            "Authenticate",
            BiometricManager.Authenticators.BIOMETRIC_WEAK,
        )

        assertEquals("Authenticate", promptInfo.title)
        assertEquals("Cancel", promptInfo.negativeButtonText)
    }

    @Test
    fun biometricOnlyNeverAllowsTheDeviceCredential() {
        val weak = BiometricManager.Authenticators.BIOMETRIC_WEAK
        val credential = BiometricManager.Authenticators.DEVICE_CREDENTIAL
        assertEquals(weak, allowedAuthenticators(biometricOnly = true, supportsCredentials = true))
        assertEquals(weak, allowedAuthenticators(biometricOnly = true, supportsCredentials = false))
        assertEquals(weak or credential, allowedAuthenticators(biometricOnly = false, supportsCredentials = true))
        assertEquals(weak, allowedAuthenticators(biometricOnly = false, supportsCredentials = false))

        val promptInfo = createAndroidXPromptInfo(
            "Unlock",
            allowedAuthenticators(biometricOnly = true, supportsCredentials = true),
        )
        assertEquals(weak, promptInfo.allowedAuthenticators)
        assertEquals("Cancel", promptInfo.negativeButtonText)
    }

    @Test
    fun promptErrorsMapToStatuses() {
        val expected = mapOf(
            BiometricPrompt.ERROR_USER_CANCELED to AuthStatus.CANCELED,
            BiometricPrompt.ERROR_NEGATIVE_BUTTON to AuthStatus.CANCELED,
            BiometricPrompt.ERROR_CANCELED to AuthStatus.CANCELED,
            BiometricPrompt.ERROR_TIMEOUT to AuthStatus.TIMEOUT,
            BiometricPrompt.ERROR_LOCKOUT to AuthStatus.TEMPORARY_LOCKOUT,
            BiometricPrompt.ERROR_LOCKOUT_PERMANENT to AuthStatus.PERMANENT_LOCKOUT,
            BiometricPrompt.ERROR_NO_BIOMETRICS to AuthStatus.NOT_ENROLLED,
            BiometricPrompt.ERROR_HW_UNAVAILABLE to AuthStatus.NOT_AVAILABLE,
            BiometricPrompt.ERROR_HW_NOT_PRESENT to AuthStatus.NOT_AVAILABLE,
            BiometricPrompt.ERROR_NO_DEVICE_CREDENTIAL to AuthStatus.NOT_AVAILABLE,
            BiometricPrompt.ERROR_SECURITY_UPDATE_REQUIRED to AuthStatus.NOT_AVAILABLE,
            BiometricPrompt.ERROR_UNABLE_TO_PROCESS to AuthStatus.ERROR,
            BiometricPrompt.ERROR_NO_SPACE to AuthStatus.ERROR,
            BiometricPrompt.ERROR_VENDOR to AuthStatus.ERROR,
        )
        assertEquals(expected, expected.mapValues { authStatusForError(it.key) })
    }

    @Test
    fun unavailableBiometricsMapToStatuses() {
        assertEquals(AuthStatus.NOT_ENROLLED, authStatusForAvailability(BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED))
        assertEquals(AuthStatus.NOT_AVAILABLE, authStatusForAvailability(BiometricManager.BIOMETRIC_ERROR_NO_HARDWARE))
        assertEquals(AuthStatus.NOT_AVAILABLE, authStatusForAvailability(BiometricManager.BIOMETRIC_ERROR_HW_UNAVAILABLE))
    }
}
