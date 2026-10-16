import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_content/src/secure_content_event.dart';
import 'package:secure_content/src/secure_content_facade.dart';
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
    'service and global requests share one native prompt for every outcome',
    () async {
      final service = SecureContentService.instance;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var nativeInvocationCount = 0;
      messenger.setMockMessageHandler('$channelPrefix.requestBiometricAuth', (
        ByteData? _,
      ) async {
        nativeInvocationCount += 1;
        return codec.encodeMessage(<Object?>[null]);
      });

      var expectedInvocationCount = 0;
      for (final outcome in <SecureContentEventType>[
        SecureContentEventType.biometricAuthSucceeded,
        SecureContentEventType.biometricAuthFailed,
        SecureContentEventType.biometricUnavailable,
      ]) {
        expectedInvocationCount += 1;
        final first = service.requestBiometricAuth('reason a');
        final second = service.requestBiometricAuth('reason b');
        final global = SecureContent.requestBiometricAuth(reason: 'global');
        final pending = service.pendingBiometricRequest;

        expect(pending, isNotNull);
        expect(identical(pending, service.pendingBiometricRequest), isTrue);
        await Future<void>.delayed(Duration.zero);
        expect(nativeInvocationCount, expectedInvocationCount);
        service.emitLocalEvent(outcome);

        final results = await Future.wait([first, second]);
        await global;
        expect(results, <SecureContentEventType>[outcome, outcome]);
        expect(nativeInvocationCount, expectedInvocationCount);
        expect(service.pendingBiometricRequest, isNull);
      }
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
    'a late native error cannot complete the next biometric request',
    () async {
      final nativeReplies = <Completer<ByteData?>>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMessageHandler('$channelPrefix.requestBiometricAuth', (
        ByteData? _,
      ) {
        final reply = Completer<ByteData?>();
        nativeReplies.add(reply);
        return reply.future;
      });

      final service = SecureContentService.instance;
      final first = service.requestBiometricAuth('first');
      service.emitLocalEvent(SecureContentEventType.biometricAuthSucceeded);
      expect(await first, SecureContentEventType.biometricAuthSucceeded);

      final second = service.requestBiometricAuth('second');
      nativeReplies.first.complete(
        codec.encodeMessage(<Object?>['native-error', 'late error', null]),
      );
      await Future<void>.delayed(Duration.zero);
      nativeReplies.last.complete(codec.encodeMessage(<Object?>[null]));
      service.emitLocalEvent(SecureContentEventType.biometricAuthSucceeded);

      expect(await second, SecureContentEventType.biometricAuthSucceeded);
      expect(nativeReplies, hasLength(2));
      expect(nativeReplies.every((reply) => reply.isCompleted), isTrue);
    },
  );

  test(
    'a native invocation failure resolves shared callers and permits a retry',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var nativeInvocationCount = 0;
      messenger.setMockMessageHandler('$channelPrefix.requestBiometricAuth', (
        ByteData? _,
      ) {
        nativeInvocationCount += 1;
        return Future<ByteData?>.value(
          codec.encodeMessage(<Object?>[
            'native-error',
            'request failed',
            null,
          ]),
        );
      });

      final service = SecureContentService.instance;
      final first = service.requestBiometricAuth('first');
      final second = SecureContent.requestBiometricAuth(reason: 'second');
      final pending = service.pendingBiometricRequest;

      expect(pending, isNotNull);
      expect(identical(pending, service.pendingBiometricRequest), isTrue);

      expect(await first, SecureContentEventType.biometricAuthFailed);
      await expectLater(second, completes);
      expect(nativeInvocationCount, 1);
      expect(service.pendingBiometricRequest, isNull);

      messenger.setMockMessageHandler('$channelPrefix.requestBiometricAuth', (
        ByteData? _,
      ) async {
        nativeInvocationCount += 1;
        return codec.encodeMessage(<Object?>[null]);
      });

      final retry = service.requestBiometricAuth('retry');
      service.emitLocalEvent(SecureContentEventType.biometricAuthSucceeded);

      expect(await retry, SecureContentEventType.biometricAuthSucceeded);
      expect(nativeInvocationCount, 2);
      expect(service.pendingBiometricRequest, isNull);
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
