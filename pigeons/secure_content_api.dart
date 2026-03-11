import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/pigeon/secure_content_api.g.dart',
    kotlinOut:
        'android/src/main/kotlin/com/codenameakshay/secure_content/pigeon/SecureContentApi.g.kt',
    kotlinOptions: KotlinOptions(
      package: 'com.codenameakshay.secure_content.pigeon',
    ),
    swiftOut: 'ios/Classes/SecureContentApi.g.swift',
    dartPackageName: 'secure_content',
  ),
)
class ProtectionConfig {
  ProtectionConfig({
    required this.enabled,
    required this.protectInAppSwitcher,
    required this.appSwitcherColor,
  });

  final bool enabled;
  final bool protectInAppSwitcher;
  final int appSwitcherColor;
}

class SecureEvent {
  SecureEvent({required this.type, required this.platform, this.timestamp});

  final String type;
  final String platform;
  final String? timestamp;
}

@HostApi()
abstract class SecureContentHostApi {
  void configureProtection(ProtectionConfig config);

  bool isScreenCaptured();

  void requestBiometricAuth(String reason);

  void checkIntegrity();

  void setSensitiveClipboard(String content, int clearAfterMs);

  void clearSensitiveClipboard();
}

@FlutterApi()
abstract class SecureContentFlutterApi {
  void onEvent(SecureEvent event);
}
