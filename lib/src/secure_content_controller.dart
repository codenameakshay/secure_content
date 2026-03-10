import 'package:flutter/material.dart';

import 'secure_content_service.dart';

class SecureContentController {
  SecureContentController();

  final Object _sourceKey = Object();
  final SecureContentService _service = SecureContentService.instance;

  bool _enabled = false;
  bool _protectInAppSwitcher = true;
  Color _appSwitcherColor = Colors.black;

  bool get enabled => _enabled;

  Future<void> setProtection(
    bool enabled, {
    bool protectInAppSwitcher = true,
    Color appSwitcherColor = Colors.black,
  }) async {
    _enabled = enabled;
    _protectInAppSwitcher = protectInAppSwitcher;
    _appSwitcherColor = appSwitcherColor;

    await _service.updateSource(
      key: _sourceKey,
      enabled: _enabled,
      protectInAppSwitcher: _protectInAppSwitcher,
      appSwitcherColor: _appSwitcherColor,
    );
  }

  Future<void> enable({
    bool protectInAppSwitcher = true,
    Color appSwitcherColor = Colors.black,
  }) {
    return setProtection(
      true,
      protectInAppSwitcher: protectInAppSwitcher,
      appSwitcherColor: appSwitcherColor,
    );
  }

  Future<void> disable() {
    return setProtection(false);
  }

  Future<void> dispose() {
    return _service.removeSource(_sourceKey);
  }
}
