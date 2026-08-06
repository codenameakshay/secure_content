import 'package:flutter/material.dart';

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
