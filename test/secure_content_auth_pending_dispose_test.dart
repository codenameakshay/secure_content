import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_content/secure_content.dart';
import 'package:secure_content/src/pigeon/secure_content_api.g.dart' as pigeon;
import 'package:secure_content/src/secure_content_platform.dart';
import 'package:secure_content/src/secure_content_service.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'dispose releases callers even if the native reply never arrives',
    () async {
      SecureContentPlatform.debugIsSupportedPlatformOverride = true;
      final service = SecureContentService.instance;
      const channel =
          'dev.flutter.pigeon.secure_content.SecureContentHostApi.authenticate';
      final codec = pigeon.SecureContentHostApi.pigeonChannelCodec;
      final messenger = binding.defaultBinaryMessenger;
      final reply = Completer<ByteData?>();
      var prompts = 0;
      messenger.setMockMessageHandler(channel, (_) {
        prompts += 1;
        return reply.future;
      });
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final first = service.authenticate('r', persistAcrossBackgrounding: true);
      final joined = service.authenticate(
        'r',
        persistAcrossBackgrounding: true,
      );
      await Future<void>.delayed(Duration.zero);
      service.dispose();
      final results = await Future.wait([first, joined]).timeout(
        const Duration(milliseconds: 100),
        onTimeout: () => const [
          SecureContentAuthResult(SecureContentAuthStatus.error),
        ],
      );
      reply.complete(
        codec.encodeMessage(<Object?>['late-error', 'late', null]),
      );
      await Future<void>.delayed(Duration.zero);
      expect(results.map((result) => result.status), [
        SecureContentAuthStatus.canceled,
        SecureContentAuthStatus.canceled,
      ]);
      expect(
        (await service.authenticate('r')).status,
        SecureContentAuthStatus.canceled,
      );
      expect(prompts, 1);
      messenger.setMockMessageHandler(channel, null);
      SecureContentPlatform.debugIsSupportedPlatformOverride = null;
    },
  );
}
