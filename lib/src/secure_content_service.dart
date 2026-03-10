import 'dart:async';

import 'package:flutter/material.dart';

import 'secure_content_event.dart';
import 'secure_content_platform.dart';

class SecureContentService {
  SecureContentService._() {
    _eventSubscription = _platform.events.listen(_eventsController.add);
  }

  static final SecureContentService instance = SecureContentService._();

  final SecureContentPlatform _platform = SecureContentPlatform.instance;
  final Map<Object, _SecureSource> _sources = <Object, _SecureSource>{};
  final StreamController<SecureContentEvent> _eventsController =
      StreamController<SecureContentEvent>.broadcast();

  StreamSubscription<SecureContentEvent>? _eventSubscription;

  bool _appliedEnabled = false;
  bool _appliedProtectInAppSwitcher = true;
  int _appliedAppSwitcherColor = Colors.black.toARGB32();

  Stream<SecureContentEvent> get events => _eventsController.stream;

  Future<void> updateSource({
    required Object key,
    required bool enabled,
    required bool protectInAppSwitcher,
    required Color appSwitcherColor,
  }) async {
    _sources[key] = _SecureSource(
      enabled: enabled,
      protectInAppSwitcher: protectInAppSwitcher,
      appSwitcherColor: appSwitcherColor,
      updatedAt: DateTime.now(),
    );

    await _sync();
  }

  Future<void> removeSource(Object key) async {
    _sources.remove(key);
    await _sync();
  }

  Future<bool> isScreenCaptured() => _platform.isScreenCaptured();

  Future<void> _sync() async {
    final activeSources = _sources.values
        .where((element) => element.enabled)
        .toList();

    final enabled = activeSources.isNotEmpty;

    final protectInAppSwitcher = activeSources.any(
      (element) => element.protectInAppSwitcher,
    );

    final appSwitcherColor = activeSources.isEmpty
        ? Colors.black.toARGB32()
        : (activeSources..sort((a, b) => a.updatedAt.compareTo(b.updatedAt)))
              .last
              .appSwitcherColor
              .toARGB32();

    if (enabled == _appliedEnabled &&
        protectInAppSwitcher == _appliedProtectInAppSwitcher &&
        appSwitcherColor == _appliedAppSwitcherColor) {
      return;
    }

    _appliedEnabled = enabled;
    _appliedProtectInAppSwitcher = protectInAppSwitcher;
    _appliedAppSwitcherColor = appSwitcherColor;

    await _platform.configureProtection(
      enabled: enabled,
      protectInAppSwitcher: protectInAppSwitcher,
      appSwitcherColor: appSwitcherColor,
    );
  }

  void dispose() {
    _eventSubscription?.cancel();
    _eventsController.close();
  }
}

class _SecureSource {
  const _SecureSource({
    required this.enabled,
    required this.protectInAppSwitcher,
    required this.appSwitcherColor,
    required this.updatedAt,
  });

  final bool enabled;
  final bool protectInAppSwitcher;
  final Color appSwitcherColor;
  final DateTime updatedAt;
}
