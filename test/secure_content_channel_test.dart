import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_content/secure_content.dart';
import 'package:secure_content/src/secure_content_platform.dart';
import 'package:secure_content/src/pigeon/secure_content_api.g.dart' as pigeon;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channelPrefix =
      'dev.flutter.pigeon.secure_content.SecureContentHostApi';
  final codec = pigeon.SecureContentHostApi.pigeonChannelCodec;
  final configs = <pigeon.ProtectionConfig>[];
  var configureCalls = 0;
  var failNextConfigure = false;

  setUp(() {
    SecureContentPlatform.debugIsSupportedPlatformOverride = true;
    addTearDown(
      () => SecureContentPlatform.debugIsSupportedPlatformOverride = null,
    );
  });

  setUpAll(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMessageHandler('$channelPrefix.configureProtection', (
      ByteData? message,
    ) async {
      configureCalls += 1;
      if (failNextConfigure) {
        failNextConfigure = false;
        return codec.encodeMessage(<Object?>[
          'configure-failed',
          'The test requested a failure',
          null,
        ]);
      }

      final request = codec.decodeMessage(message) as List<Object?>;
      configs.add(request.single as pigeon.ProtectionConfig);
      return codec.encodeMessage(<Object?>[null]);
    });
  });

  tearDown(() {
    configs.clear();
    configureCalls = 0;
    failNextConfigure = false;
  });

  tearDownAll(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMessageHandler('$channelPrefix.configureProtection', null);
  });

  test('configures through Pigeon and retries after a failed call', () async {
    final switcherController = SecureContentController();
    addTearDown(switcherController.dispose);

    await switcherController.enable(
      protectInAppSwitcher: true,
      appSwitcherColor: const Color(0xFF112233),
    );
    expect(configureCalls, 1);
    expect(configs.last.enabled, isTrue);
    expect(configs.last.protectInAppSwitcher, isTrue);
    expect(configs.last.appSwitcherColor, 0xFF112233);

    final nonSwitcherController = SecureContentController();
    addTearDown(nonSwitcherController.dispose);
    await nonSwitcherController.enable(
      protectInAppSwitcher: false,
      appSwitcherColor: const Color(0x00FFFFFF),
    );

    // A source that opted out of app-switcher protection must not override
    // the color from the source that did opt in.
    expect(configureCalls, 1);
    expect(configs.last.appSwitcherColor, 0xFF112233);

    failNextConfigure = true;
    final retryController = SecureContentController();
    addTearDown(retryController.dispose);

    await expectLater(
      retryController.enable(appSwitcherColor: const Color(0xFF445566)),
      throwsA(isA<PlatformException>()),
    );
    expect(configureCalls, 2);
    expect(configs.last.appSwitcherColor, 0xFF112233);

    await retryController.enable(appSwitcherColor: const Color(0xFF445566));
    expect(configureCalls, 3);
    expect(configs.last.enabled, isTrue);
    expect(configs.last.appSwitcherColor, 0xFF445566);
  });
}
