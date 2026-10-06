package com.codenameakshay.secure_content

internal enum class NativeEvent(val wireName: String) {
    PLATFORM_READY("platformReady"),
    SCREENSHOT_CAPTURED("screenshotCaptured"),
    BIOMETRIC_SUCCEEDED("biometricAuthSucceeded"),
    BIOMETRIC_FAILED("biometricAuthFailed"),
    BIOMETRIC_UNAVAILABLE("biometricUnavailable"),
    INTEGRITY_RISK("integrityRiskDetected"),
    INTEGRITY_SAFE("integritySafe"),
    CLIPBOARD_SET("clipboardSet"),
    CLIPBOARD_CLEARED("clipboardCleared"),
}
