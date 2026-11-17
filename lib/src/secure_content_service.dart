import 'dart:async';

import 'package:flutter/material.dart';

import 'secure_content_auth.dart';
import 'secure_content_event.dart';
import 'pigeon/secure_content_api.g.dart' as pigeon;
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
  int _sourceUpdateSequence = 0;

  // Serializes _sync() calls so overlapping updateSource/removeSource calls
  // apply in order against a consistent view of _sources, instead of racing
  // to read/write the applied-config cache concurrently (SYNC-01). This
  // continuation Future always resolves (errors are swallowed here so the
  // queue keeps moving); the Future returned to each _sync() caller is
  // separate and still carries that call's own failure.
  Future<void>? _syncQueue;

  Completer<SecureContentEventType>? _biometricRequest;
  StreamSubscription<SecureContentEvent>? _biometricResultSubscription;

  Future<SecureContentAuthResult>? _authRequest;
  ({bool biometricOnly, bool persist})? _authRequestKey;
  Completer<pigeon.AuthResult>? _authCancellation;
  AppLifecycleListener? _authLifecycleListener;
  bool _isDisposed = false;

  Stream<SecureContentEvent> get events => _eventsController.stream;

  Future<SecureContentEventType>? get pendingBiometricRequest =>
      _biometricRequest?.future;

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
  Future<SecureContentEventType> requestBiometricAuth(String reason) async {
    if (_isDisposed) return SecureContentEventType.biometricAuthFailed;
    if (!_platform.isSupportedPlatform) {
      return SecureContentEventType.biometricUnavailable;
    }

    final current = _biometricRequest;
    if (current != null) {
      return current.future;
    }

    final completer = Completer<SecureContentEventType>();
    _biometricRequest = completer;
    // An [authenticate] prompt is up: wait for it, then open our own. Its
    // result answers a different question, and reusing a prompt that began
    // earlier would skip the fresh result a resume needs.
    final auth = _authRequest;
    if (auth == null) {
      _startBiometricRequest(reason, completer);
    } else {
      unawaited(auth.then((_) => _startBiometricRequest(reason, completer)));
    }
    return completer.future;
  }

  void _startBiometricRequest(
    String reason,
    Completer<SecureContentEventType> completer,
  ) {
    if (!identical(_biometricRequest, completer)) return;
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
        if (identical(_biometricRequest, completer)) {
          _completeBiometricRequest(SecureContentEventType.biometricAuthFailed);
        }
      }),
    );
  }

  /// Shows one authentication prompt and returns its outcome.
  ///
  /// With [biometricOnly], the prompt accepts only a biometric and never
  /// offers the device passcode, PIN, or pattern.
  ///
  /// With [persistAcrossBackgrounding], a prompt that the system closes
  /// because the app lost the foreground opens again when the app is resumed,
  /// and this call returns that prompt's result.
  ///
  /// One prompt runs at a time. A call made while a prompt with the same
  /// options is up shares that prompt and its result. Any other call waits
  /// until the current prompt closes, then opens its own, so a prompt that
  /// accepts the passcode never answers a biometric-only call.
  Future<SecureContentAuthResult> authenticate(
    String reason, {
    bool biometricOnly = false,
    bool persistAcrossBackgrounding = false,
  }) async {
    if (!_platform.isSupportedPlatform) {
      return const SecureContentAuthResult(
        SecureContentAuthStatus.notAvailable,
      );
    }
    final key = (
      biometricOnly: biometricOnly,
      persist: persistAcrossBackgrounding,
    );
    while (true) {
      if (_isDisposed) {
        return const SecureContentAuthResult(SecureContentAuthStatus.canceled);
      }
      final auth = _authRequest;
      if (auth != null && _authRequestKey == key) {
        return auth;
      }
      // Neither future completes with an error.
      final busy = auth ?? _biometricRequest?.future;
      if (busy == null) break;
      await busy;
    }

    final request = _prompt(reason, key);
    _authRequest = request;
    _authRequestKey = key;
    unawaited(
      request.whenComplete(() {
        if (identical(_authRequest, request)) _authRequest = null;
      }),
    );
    return request;
  }

  Future<SecureContentAuthResult> _prompt(
    String reason,
    ({bool biometricOnly, bool persist}) key,
  ) async {
    final cancellation = Completer<pigeon.AuthResult>();
    _authCancellation = cancellation;
    var nextResume = Completer<void>();
    if (key.persist) {
      _authLifecycleListener = AppLifecycleListener(
        onResume: () {
          final resumed = nextResume;
          nextResume = Completer<void>();
          resumed.complete();
        },
      );
    }
    try {
      while (!_isDisposed) {
        final resumeAfterPrompt = nextResume.future;
        final reply = await Future.any<pigeon.AuthResult>([
          _platform.authenticate(reason, biometricOnly: key.biometricOnly),
          cancellation.future,
        ]);
        if (!key.persist || reply.interrupted != true) {
          return SecureContentAuthResult.fromPigeon(reply);
        }
        await Future.any<Object?>([resumeAfterPrompt, cancellation.future]);
        while (!_isDisposed &&
            WidgetsBinding.instance.lifecycleState !=
                AppLifecycleState.resumed) {
          await Future.any<Object?>([nextResume.future, cancellation.future]);
        }
      }
      return const SecureContentAuthResult(SecureContentAuthStatus.canceled);
    } catch (error) {
      return SecureContentAuthResult(
        SecureContentAuthStatus.error,
        message: '$error',
      );
    } finally {
      _authLifecycleListener?.dispose();
      _authLifecycleListener = null;
      _authCancellation = null;
      if (!cancellation.isCompleted) {
        cancellation.complete(
          pigeon.AuthResult(status: pigeon.AuthStatus.canceled),
        );
      }
    }
  }

  Future<SecureContentBiometricCapability> getBiometricCapability() async {
    if (!_platform.isSupportedPlatform) {
      return const SecureContentBiometricCapability(
        isAvailable: false,
        types: <SecureContentBiometryType>[],
      );
    }
    return SecureContentBiometricCapability.fromPigeon(
      await _platform.getBiometricCapability(),
    );
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
      updateSequence: ++_sourceUpdateSequence,
    );

    await _sync();
  }

  Future<void> removeSource(Object key) async {
    _sources.remove(key);
    await _sync();
  }

  Future<bool> isScreenCaptured() => _platform.isScreenCaptured();

  Future<void> _sync() {
    final result = (_syncQueue ?? Future<void>.value()).then(
      (_) => _syncOnce(),
    );
    final pending = result.catchError((Object _, StackTrace _) {});
    _syncQueue = pending;
    unawaited(
      pending.then((_) {
        if (identical(_syncQueue, pending)) {
          _syncQueue = null;
        }
      }),
    );
    return result;
  }

  Future<void> _syncOnce() async {
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
                ..sort((a, b) => a.updateSequence.compareTo(b.updateSequence)))
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

    // Only commit the applied-config cache once the platform call actually
    // succeeds (SYNC-01). If configureProtection throws, the cache stays at
    // its last known-good value so the next _sync() call sees a diff again
    // and retries, instead of silently believing a failed call succeeded.
    await _platform.configureProtection(
      enabled: enabled,
      protectInAppSwitcher: protectInAppSwitcher,
      appSwitcherColor: appSwitcherColor,
      appSwitcherImageName: appSwitcherImageName,
    );

    _appliedEnabled = enabled;
    _appliedProtectInAppSwitcher = protectInAppSwitcher;
    _appliedAppSwitcherColor = appSwitcherColor;
    _appliedAppSwitcherImageName = appSwitcherImageName;
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _authLifecycleListener?.dispose();
    _authLifecycleListener = null;
    _authCancellation?.complete(
      pigeon.AuthResult(status: pigeon.AuthStatus.canceled),
    );
    _completeBiometricRequest(SecureContentEventType.biometricAuthFailed);
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
    required this.updateSequence,
  });

  final bool enabled;
  final bool protectInAppSwitcher;
  final Color appSwitcherColor;
  final String? appSwitcherImageName;
  final int updateSequence;
}
