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
}
