import 'dart:async';
import 'dart:io';

import 'pigeon/secure_content_api.g.dart' as pigeon;
import 'secure_content_event.dart';

class SecureContentPlatform {
  SecureContentPlatform._() {
    pigeon.SecureContentFlutterApi.setUp(_flutterApiBridge);
  }

  static final SecureContentPlatform instance = SecureContentPlatform._();

  final pigeon.SecureContentHostApi _hostApi = pigeon.SecureContentHostApi();
  final _FlutterApiBridge _flutterApiBridge = _FlutterApiBridge();

  bool get isSupportedPlatform => Platform.isAndroid || Platform.isIOS;

  Stream<SecureContentEvent> get events => _flutterApiBridge.events;

  Future<void> configureProtection({
    required bool enabled,
    required bool protectInAppSwitcher,
    required int appSwitcherColor,
  }) async {
    if (!isSupportedPlatform) {
      return;
    }

    await _hostApi.configureProtection(
      pigeon.ProtectionConfig(
        enabled: enabled,
        protectInAppSwitcher: protectInAppSwitcher,
        appSwitcherColor: appSwitcherColor,
      ),
    );
  }

  Future<bool> isScreenCaptured() async {
    if (!isSupportedPlatform) {
      return false;
    }

    return _hostApi.isScreenCaptured();
  }

  Future<void> requestBiometricAuth(String reason) async {
    if (!isSupportedPlatform) {
      return;
    }
    await _hostApi.requestBiometricAuth(reason);
  }

  Future<void> checkIntegrity() async {
    if (!isSupportedPlatform) {
      return;
    }
    await _hostApi.checkIntegrity();
  }

  Future<void> setSensitiveClipboard(
    String content, {
    required Duration clearAfter,
  }) async {
    if (!isSupportedPlatform) {
      return;
    }
    await _hostApi.setSensitiveClipboard(content, clearAfter.inMilliseconds);
  }

  Future<void> clearSensitiveClipboard() async {
    if (!isSupportedPlatform) {
      return;
    }
    await _hostApi.clearSensitiveClipboard();
  }
}

class _FlutterApiBridge extends pigeon.SecureContentFlutterApi {
  final StreamController<SecureContentEvent> _controller =
      StreamController<SecureContentEvent>.broadcast();

  Stream<SecureContentEvent> get events => _controller.stream;

  @override
  void onEvent(pigeon.SecureEvent event) {
    _controller.add(SecureContentEvent.fromPigeon(event));
  }
}
