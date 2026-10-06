package com.codenameakshay.secure_content

import android.os.Build
import android.os.Debug
import java.io.File

private val rootPaths = arrayOf(
    "/system/app/Superuser.apk",
    "/sbin/su",
    "/system/bin/su",
    "/system/xbin/su",
    "/data/local/xbin/su",
    "/data/local/bin/su",
    "/system/sd/xbin/su",
    "/system/bin/failsafe/su",
    "/data/local/su",
)

internal fun hasIntegrityRisk(): Boolean =
    Build.TAGS?.contains("test-keys") == true ||
        rootPaths.any { File(it).exists() } ||
        isEmulatorBuild(
            fingerprint = Build.FINGERPRINT,
            model = Build.MODEL,
            manufacturer = Build.MANUFACTURER,
            brand = Build.BRAND,
            device = Build.DEVICE,
            product = Build.PRODUCT,
            hardware = Build.HARDWARE,
        ) || Debug.isDebuggerConnected()

internal fun isEmulatorBuild(
    fingerprint: String,
    model: String,
    manufacturer: String,
    brand: String,
    device: String,
    product: String,
    hardware: String,
): Boolean {
    val normalizedFingerprint = fingerprint.lowercase()
    val normalizedModel = model.lowercase()
    val normalizedManufacturer = manufacturer.lowercase()
    val normalizedBrand = brand.lowercase()
    val normalizedDevice = device.lowercase()
    val normalizedProduct = product.lowercase()
    val normalizedHardware = hardware.lowercase()

    return normalizedFingerprint.startsWith("generic") ||
        normalizedFingerprint.contains("emulator") ||
        normalizedFingerprint.contains("vbox") ||
        normalizedFingerprint.contains("test-keys") ||
        normalizedModel.contains("google_sdk") ||
        normalizedModel.contains("emulator") ||
        normalizedModel.contains("android sdk built for") ||
        normalizedManufacturer.contains("genymotion") ||
        normalizedBrand.startsWith("generic") && normalizedDevice.startsWith("generic") ||
        normalizedProduct.contains("google_sdk") ||
        normalizedProduct.contains("sdk_gphone") ||
        normalizedProduct.contains("emulator") ||
        normalizedHardware.contains("goldfish") ||
        normalizedHardware.contains("ranchu")
}
