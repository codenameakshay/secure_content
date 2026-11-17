import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/pigeon/secure_content_api.g.dart',
    kotlinOut:
        'android/src/main/kotlin/com/codenameakshay/secure_content/pigeon/SecureContentApi.g.kt',
    kotlinOptions: KotlinOptions(
      package: 'com.codenameakshay.secure_content.pigeon',
    ),
    swiftOut:
        'ios/secure_content/Sources/secure_content/SecureContentApi.g.swift',
    dartPackageName: 'secure_content',
  ),
)
class ProtectionConfig {
  ProtectionConfig({
    required this.enabled,
    required this.protectInAppSwitcher,
    required this.appSwitcherColor,
    this.appSwitcherImageName,
  });

  final bool enabled;
  final bool protectInAppSwitcher;
  final int appSwitcherColor;

  /// Optional name of an image in the host app's native asset catalog to
  /// center on the app-switcher / privacy overlay (rendered as a template,
  /// tinted to contrast the background). When null the overlay is a plain fill.
  final String? appSwitcherImageName;
}

class SecureEvent {
  SecureEvent({required this.type, required this.platform, this.timestamp});

  final String type;
  final String platform;
  final String? timestamp;
}

/// Outcome of [SecureContentHostApi.authenticate].
enum AuthStatus {
  success,
  failed,
  canceled,
  timeout,
  temporaryLockout,
  permanentLockout,
  notEnrolled,
  notAvailable,
  error,
}

class AuthResult {
  AuthResult({required this.status, this.message});

  final AuthStatus status;
  final String? message;
}

enum BiometryType { face, fingerprint, iris, unknown }

class BiometricCapability {
  BiometricCapability({required this.isAvailable, required this.types});

  final bool isAvailable;
  final List<BiometryType> types;
}

@HostApi()
abstract class SecureContentHostApi {
  void configureProtection(ProtectionConfig config);

  bool isScreenCaptured();

  void requestBiometricAuth(String reason);

  /// Replies with the outcome of this one prompt. Emits no biometric events.
  @asyncCallback
  AuthResult authenticate(String reason, bool biometricOnly);

  BiometricCapability getBiometricCapability();

  void checkIntegrity();

  void setSensitiveClipboard(String content, int clearAfterMs);

  void clearSensitiveClipboard();
}

@FlutterApi()
abstract class SecureContentFlutterApi {
  @asyncCallback
  void onEvent(SecureEvent event);
}
