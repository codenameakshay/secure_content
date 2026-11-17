import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_content/secure_content.dart';
import 'package:secure_content/src/pigeon/secure_content_api.g.dart' as pigeon;
import 'package:secure_content/src/secure_content_platform.dart';
import 'package:secure_content/src/secure_content_service.dart';

class _LifecycleBinding extends AutomatedTestWidgetsFlutterBinding {
  final Set<WidgetsBindingObserver> lifecycleListeners = {};

  @override
  void addObserver(WidgetsBindingObserver observer) {
    super.addObserver(observer);
    if (observer is AppLifecycleListener) lifecycleListeners.add(observer);
  }

  @override
  bool removeObserver(WidgetsBindingObserver observer) {
    lifecycleListeners.remove(observer);
    return super.removeObserver(observer);
  }
}

void main() {
  final binding = _LifecycleBinding();

  test(
    'disposing a parked request releases listeners and all gate waiters',
    () async {
      SecureContentPlatform.debugIsSupportedPlatformOverride = true;
      final service = SecureContentService.instance;
      const prefix = 'dev.flutter.pigeon.secure_content.SecureContentHostApi';
      final codec = pigeon.SecureContentHostApi.pigeonChannelCodec;
      final messenger = binding.defaultBinaryMessenger;
      final replies = <Completer<ByteData?>>[];
      var legacyCalls = 0;
      messenger.setMockMessageHandler('$prefix.authenticate', (_) {
        final reply = Completer<ByteData?>();
        replies.add(reply);
        return reply.future;
      });
      messenger.setMockMessageHandler('$prefix.requestBiometricAuth', (
        _,
      ) async {
        legacyCalls += 1;
        return codec.encodeMessage(<Object?>[null]);
      });
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final initialListeners = binding.lifecycleListeners.length;
      final first = service.authenticate('r', persistAcrossBackgrounding: true);
      final joined = service.authenticate(
        'r',
        persistAcrossBackgrounding: true,
      );
      final waiting = service.authenticate('r', biometricOnly: true);
      final legacy = service.requestBiometricAuth('r');
      await Future<void>.delayed(Duration.zero);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      replies.single.complete(
        codec.encodeMessage(<Object?>[
          pigeon.AuthResult(
            status: pigeon.AuthStatus.canceled,
            interrupted: true,
          ),
        ]),
      );
      await Future<void>.delayed(Duration.zero);
      service.dispose();
      await Future<void>.delayed(Duration.zero);
      final listenersAfterDispose = binding.lifecycleListeners.length;
      final result = await first.timeout(
        const Duration(milliseconds: 100),
        onTimeout: () =>
            const SecureContentAuthResult(SecureContentAuthStatus.error),
      );

      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      for (final reply in replies) {
        if (!reply.isCompleted) {
          reply.complete(
            codec.encodeMessage(<Object?>[
              pigeon.AuthResult(status: pigeon.AuthStatus.canceled),
            ]),
          );
        }
      }
      expect(result.status, SecureContentAuthStatus.canceled);
      expect((await joined).status, SecureContentAuthStatus.canceled);
      expect((await waiting).status, SecureContentAuthStatus.canceled);
      expect(await legacy, SecureContentEventType.biometricAuthFailed);
      expect(listenersAfterDispose, initialListeners);
      expect(legacyCalls, 0);
      expect(replies, hasLength(1));
      messenger.setMockMessageHandler('$prefix.authenticate', null);
      messenger.setMockMessageHandler('$prefix.requestBiometricAuth', null);
      SecureContentPlatform.debugIsSupportedPlatformOverride = null;
    },
  );
}
