import 'package:flutter_test/flutter_test.dart';
import 'package:secure_content/src/secure_content_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('unsupported platforms use safe no-op fallbacks', () async {
    SecureContentPlatform.debugIsSupportedPlatformOverride = null;
    addTearDown(
      () => SecureContentPlatform.debugIsSupportedPlatformOverride = null,
    );

    final platform = SecureContentPlatform.instance;
    expect(platform.isSupportedPlatform, isFalse);
    await platform.configureProtection(
      enabled: true,
      protectInAppSwitcher: true,
      appSwitcherColor: 0xFF000000,
    );
    expect(await platform.isScreenCaptured(), isFalse);
    await platform.requestBiometricAuth('reason');
    await platform.checkIntegrity();
    await platform.setSensitiveClipboard('secret', clearAfter: Duration.zero);
    await platform.clearSensitiveClipboard();
  });
}
