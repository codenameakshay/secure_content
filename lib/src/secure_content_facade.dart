import 'package:flutter/material.dart';

import 'secure_content_auth.dart';
import 'secure_content_controller.dart';
import 'secure_content_event.dart';
import 'secure_content_service.dart';

class SecureContent {
  SecureContent._();

  static final SecureContentService _service = SecureContentService.instance;
  static final SecureContentController _globalController =
      SecureContentController();

  static Stream<SecureContentEvent> get events => _service.events;

  static SecureContentController createController() {
    return SecureContentController();
  }

  static Future<void> setGlobalProtection(
    bool enabled, {
    bool protectInAppSwitcher = true,
    Color appSwitcherColor = Colors.black,
  }) {
    return _globalController.setProtection(
      enabled,
      protectInAppSwitcher: protectInAppSwitcher,
      appSwitcherColor: appSwitcherColor,
    );
  }

  static Future<bool> isScreenCaptured() {
    return _service.isScreenCaptured();
  }

  /// Shows one authentication prompt and returns its outcome.
  ///
  /// With [biometricOnly], the prompt accepts only a biometric (Face ID,
  /// Touch ID, or an Android class 2 or 3 biometric) and never offers the
  /// device passcode, PIN, or pattern. By default the device credential is
  /// accepted too, as with [requestBiometricAuth].
  ///
  /// Calls share one prompt while it is up, unless their [biometricOnly]
  /// values differ. This prompt emits no biometric events on [events].
  static Future<SecureContentAuthResult> authenticate({
    required String reason,
    bool biometricOnly = false,
  }) {
    return _service.authenticate(reason, biometricOnly: biometricOnly);
  }

  /// Whether biometrics are enrolled, and which sensors the device has.
  static Future<SecureContentBiometricCapability> getBiometricCapability() {
    return _service.getBiometricCapability();
  }

  /// Shows a prompt that accepts a biometric or the device credential, and
  /// reports the outcome only as a biometric event on [events]. Use
  /// [authenticate] to get the outcome directly.
  static Future<void> requestBiometricAuth({
    String reason = 'Authenticate to continue',
  }) {
    return _service.requestBiometricAuth(reason);
  }

  static Future<void> checkIntegrity() {
    return _service.checkIntegrity();
  }

  static Future<void> setSensitiveClipboard(
    String content, {
    Duration clearAfter = const Duration(seconds: 30),
  }) {
    return _service.setSensitiveClipboard(content, clearAfter: clearAfter);
  }

  static Future<void> clearSensitiveClipboard() {
    return _service.clearSensitiveClipboard();
  }
}
