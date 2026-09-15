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
  String? _appliedAppSwitcherImageName;

  Completer<SecureContentEventType>? _biometricRequest;
  StreamSubscription<SecureContentEvent>? _biometricResultSubscription;

  Stream<SecureContentEvent> get events => _eventsController.stream;

  /// Requests biometric authentication and returns the outcome as one of
  /// [SecureContentEventType.biometricAuthSucceeded],
  /// [SecureContentEventType.biometricAuthFailed], or
  /// [SecureContentEventType.biometricUnavailable].
  ///
  /// Only one biometric prompt runs at a time: concurrent callers share the
  /// same in-flight request and native prompt, and all resolve together from
  /// the single correlated result. Callers must await this result instead of
  /// reacting to the raw [events] stream, since that stream is shared by every
  /// [SecureContentService] consumer and a biometric outcome on it may belong
  /// to a request some other, unrelated caller made.
  Future<SecureContentEventType> requestBiometricAuth(String reason) {
    final inFlight = _biometricRequest;
    if (inFlight != null) {
      return inFlight.future;
    }

    final completer = Completer<SecureContentEventType>();
    _biometricRequest = completer;
    _biometricResultSubscription = _eventsController.stream.listen((event) {
      switch (event.type) {
        case SecureContentEventType.biometricAuthSucceeded:
        case SecureContentEventType.biometricAuthFailed:
        case SecureContentEventType.biometricUnavailable:
          _completeBiometricRequest(event.type);
          break;
        default:
          break;
      }
    });

    unawaited(
      _platform.requestBiometricAuth(reason).catchError((
        Object _,
        StackTrace _,
      ) {
        _completeBiometricRequest(SecureContentEventType.biometricAuthFailed);
      }),
    );

    return completer.future;
  }

  void _completeBiometricRequest(SecureContentEventType outcome) {
    final completer = _biometricRequest;
    if (completer == null || completer.isCompleted) {
      return;
    }
    _biometricRequest = null;
    unawaited(_biometricResultSubscription?.cancel());
    _biometricResultSubscription = null;
    completer.complete(outcome);
  }

  Future<void> checkIntegrity() {
    return _platform.checkIntegrity();
  }

  Future<void> setSensitiveClipboard(
    String content, {
    Duration clearAfter = const Duration(seconds: 30),
  }) {
    return _platform.setSensitiveClipboard(content, clearAfter: clearAfter);
  }

  Future<void> clearSensitiveClipboard() {
    return _platform.clearSensitiveClipboard();
  }

  void emitLocalEvent(SecureContentEventType type) {
    _eventsController.add(
      SecureContentEvent(
        type: type,
        platform: 'flutter',
        timestamp: DateTime.now(),
        payload: <String, Object?>{
          'type': type.name,
          'platform': 'flutter',
          'timestamp': DateTime.now().toIso8601String(),
        },
      ),
    );
  }

  Future<void> updateSource({
    required Object key,
    required bool enabled,
    required bool protectInAppSwitcher,
    required Color appSwitcherColor,
    String? appSwitcherImageName,
  }) async {
    _sources[key] = _SecureSource(
      enabled: enabled,
      protectInAppSwitcher: protectInAppSwitcher,
      appSwitcherColor: appSwitcherColor,
      appSwitcherImageName: appSwitcherImageName,
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

    // Color/image selection must only consider sources that actually
    // requested app-switcher protection (CFG-01); a source that opted out of
    // it should never dictate the overlay's appearance just because it was
    // updated more recently than a source that did opt in.
    final appSwitcherSources = activeSources
        .where((element) => element.protectInAppSwitcher)
        .toList();
    final _SecureSource? latest = appSwitcherSources.isEmpty
        ? null
        : (appSwitcherSources
                ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt)))
              .last;
    final appSwitcherColor =
        latest?.appSwitcherColor.toARGB32() ?? Colors.black.toARGB32();
    final appSwitcherImageName = latest?.appSwitcherImageName;

    if (enabled == _appliedEnabled &&
        protectInAppSwitcher == _appliedProtectInAppSwitcher &&
        appSwitcherColor == _appliedAppSwitcherColor &&
        appSwitcherImageName == _appliedAppSwitcherImageName) {
      return;
    }

    _appliedEnabled = enabled;
    _appliedProtectInAppSwitcher = protectInAppSwitcher;
    _appliedAppSwitcherColor = appSwitcherColor;
    _appliedAppSwitcherImageName = appSwitcherImageName;

    await _platform.configureProtection(
      enabled: enabled,
      protectInAppSwitcher: protectInAppSwitcher,
      appSwitcherColor: appSwitcherColor,
      appSwitcherImageName: appSwitcherImageName,
    );
  }

  void dispose() {
    _eventSubscription?.cancel();
    unawaited(_biometricResultSubscription?.cancel());
    _eventsController.close();
  }
}

class _SecureSource {
  const _SecureSource({
    required this.enabled,
    required this.protectInAppSwitcher,
    required this.appSwitcherColor,
    required this.appSwitcherImageName,
    required this.updatedAt,
  });

  final bool enabled;
  final bool protectInAppSwitcher;
  final Color appSwitcherColor;
  final String? appSwitcherImageName;
  final DateTime updatedAt;
}
