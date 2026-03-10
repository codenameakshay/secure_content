import 'dart:io';

import 'package:flutter/services.dart';

import 'secure_content_event.dart';

class SecureContentPlatform {
  SecureContentPlatform._();

  static final SecureContentPlatform instance = SecureContentPlatform._();

  static const MethodChannel _methodChannel = MethodChannel(
    'secure_content/methods',
  );
  static const EventChannel _eventChannel = EventChannel(
    'secure_content/events',
  );

  Stream<SecureContentEvent>? _events;

  bool get isSupportedPlatform => Platform.isAndroid || Platform.isIOS;

  Stream<SecureContentEvent> get events {
    if (!isSupportedPlatform) {
      return const Stream<SecureContentEvent>.empty();
    }

    _events ??= _eventChannel
        .receiveBroadcastStream()
        .where((dynamic event) => event is Map)
        .map(
          (dynamic event) =>
              SecureContentEvent.fromMap(event as Map<Object?, Object?>),
        )
        .asBroadcastStream();

    return _events!;
  }

  Future<void> configureProtection({
    required bool enabled,
    required bool protectInAppSwitcher,
    required int appSwitcherColor,
  }) async {
    if (!isSupportedPlatform) {
      return;
    }

    await _methodChannel
        .invokeMethod<void>('configureProtection', <String, Object?>{
          'enabled': enabled,
          'protectInAppSwitcher': protectInAppSwitcher,
          'appSwitcherColor': appSwitcherColor,
        });
  }

  Future<bool> isScreenCaptured() async {
    if (!isSupportedPlatform) {
      return false;
    }

    final captured = await _methodChannel.invokeMethod<bool>(
      'isScreenCaptured',
    );
    return captured ?? false;
  }
}
