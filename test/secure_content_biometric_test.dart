import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_content/src/secure_content_event.dart';
import 'package:secure_content/src/secure_content_platform.dart';
import 'package:secure_content/src/secure_content_service.dart';
import 'package:secure_content/src/pigeon/secure_content_api.g.dart' as pigeon;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // These tests exercise SecureContentService.requestBiometricAuth in
  // isolation via emitLocalEvent, so they stay deterministic without needing
  // the real Pigeon channel (see AUTH-01).
  const channelPrefix =
      'dev.flutter.pigeon.secure_content.SecureContentHostApi';
  final codec = pigeon.SecureContentHostApi.pigeonChannelCodec;

  setUp(() {
    SecureContentPlatform.debugIsSupportedPlatformOverride = true;

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMessageHandler(
      '$channelPrefix.requestBiometricAuth',
      (ByteData? message) async => codec.encodeMessage(<Object?>[null]),
    );
  });

  tearDown(() {
    SecureContentPlatform.debugIsSupportedPlatformOverride = null;
  });

  tearDownAll(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMessageHandler(
      '$channelPrefix.requestBiometricAuth',
      null,
    );
  });

  test(
    'concurrent requests share a single in-flight result (AUTH-01)',
    () async {
      final service = SecureContentService.instance;

      final first = service.requestBiometricAuth('reason a');
      final second = service.requestBiometricAuth('reason b');

      // A single emitted outcome must resolve both concurrent callers.
      service.emitLocalEvent(SecureContentEventType.biometricAuthSucceeded);

      final results = await Future.wait([first, second]);
      expect(results[0], SecureContentEventType.biometricAuthSucceeded);
      expect(results[1], SecureContentEventType.biometricAuthSucceeded);
    },
  );

  test(
    'a request after a prior one resolved starts a fresh correlation',
    () async {
      final service = SecureContentService.instance;

      final first = service.requestBiometricAuth('reason');
      service.emitLocalEvent(SecureContentEventType.biometricAuthFailed);
      expect(await first, SecureContentEventType.biometricAuthFailed);

      final second = service.requestBiometricAuth('reason');
      service.emitLocalEvent(SecureContentEventType.biometricUnavailable);
      expect(await second, SecureContentEventType.biometricUnavailable);
    },
  );

  test(
    'unsupported platforms resolve biometric requests immediately',
    () async {
      SecureContentPlatform.debugIsSupportedPlatformOverride = false;

      final outcome = await SecureContentService.instance
          .requestBiometricAuth('reason')
          .timeout(const Duration(seconds: 1));

      expect(outcome, SecureContentEventType.biometricUnavailable);
    },
  );
}
