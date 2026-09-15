package com.codenameakshay.secure_content

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class EmulatorDetectionTest {
    @Test
    fun detectsGoogleApisArm64Emulator() {
        assertTrue(
            isEmulatorBuild(
                fingerprint = "google/sdk_gphone64_arm64/emu64a:16/BP2A.250605.031.A2/12345678:userdebug/dev-keys",
                model = "sdk_gphone64_arm64",
                manufacturer = "Google",
                brand = "google",
                device = "emu64a",
                product = "sdk_gphone64_arm64",
                hardware = "ranchu",
            ),
        )
    }

    @Test
    fun doesNotFlagPhysicalPixel() {
        assertFalse(
            isEmulatorBuild(
                fingerprint = "google/husky/husky:15/AP4A.250105.002/12345678:user/release-keys",
                model = "Pixel 8 Pro",
                manufacturer = "Google",
                brand = "google",
                device = "husky",
                product = "husky",
                hardware = "husky",
            ),
        )
    }
}
