import 'package:flutter/foundation.dart';

import 'pigeon/secure_content_api.g.dart' as pigeon;

/// The outcome of one [SecureContent.authenticate] prompt.
enum SecureContentAuthStatus {
  /// The person authenticated.
  success,

  /// The biometric was not recognized.
  failed,

  /// The person, the app, or the system closed the prompt. On iOS this
  /// includes the fallback button, and on Android the negative button.
  canceled,

  /// The prompt timed out (Android only).
  timeout,

  /// Too many attempts. Biometrics come back after a short wait (Android only).
  temporaryLockout,

  /// Too many attempts. The person must unlock the device with its passcode,
  /// PIN, or pattern before biometrics work again.
  permanentLockout,

  /// The device has biometric hardware, but no biometric is enrolled.
  notEnrolled,

  /// Authentication cannot run: no hardware, no screen lock, no host
  /// activity, or an unsupported platform.
  notAvailable,

  /// Any other error. [SecureContentAuthResult.message] has the platform's
  /// description.
  error,
}

/// The result of [SecureContent.authenticate].
@immutable
class SecureContentAuthResult {
  const SecureContentAuthResult(this.status, {this.message});

  final SecureContentAuthStatus status;

  /// The platform's description of an error, when it gave one. For logs, not
  /// for display.
  final String? message;

  bool get isSuccess => status == SecureContentAuthStatus.success;

  @override
  bool operator ==(Object other) =>
      other is SecureContentAuthResult &&
      other.status == status &&
      other.message == message;

  @override
  int get hashCode => Object.hash(status, message);

  @override
  String toString() => 'SecureContentAuthResult($status, $message)';

  static SecureContentAuthResult fromPigeon(pigeon.AuthResult result) {
    final status = switch (result.status) {
      pigeon.AuthStatus.success => SecureContentAuthStatus.success,
      pigeon.AuthStatus.failed => SecureContentAuthStatus.failed,
      pigeon.AuthStatus.canceled => SecureContentAuthStatus.canceled,
      pigeon.AuthStatus.timeout => SecureContentAuthStatus.timeout,
      pigeon.AuthStatus.temporaryLockout =>
        SecureContentAuthStatus.temporaryLockout,
      pigeon.AuthStatus.permanentLockout =>
        SecureContentAuthStatus.permanentLockout,
      pigeon.AuthStatus.notEnrolled => SecureContentAuthStatus.notEnrolled,
      pigeon.AuthStatus.notAvailable => SecureContentAuthStatus.notAvailable,
      pigeon.AuthStatus.error => SecureContentAuthStatus.error,
    };
    return SecureContentAuthResult(status, message: result.message);
  }
}

/// The kind of biometric sensor a device has.
enum SecureContentBiometryType {
  face,
  fingerprint,
  iris,

  /// Android reports usable biometrics but no sensor feature this package
  /// recognizes.
  unknown,
}

/// What [SecureContent.getBiometricCapability] found on this device.
@immutable
class SecureContentBiometricCapability {
  const SecureContentBiometricCapability({
    required this.isAvailable,
    required this.types,
  });

  /// True when a biometric is enrolled and biometric-only authentication can
  /// run. Stays true during a lockout: [SecureContent.authenticate] reports
  /// the lockout.
  final bool isAvailable;

  /// The biometric sensors the device has, enrolled or not. Use it to pick a
  /// label such as "Unlock with Face ID". On Android this comes from the
  /// device's declared features and is best effort.
  final List<SecureContentBiometryType> types;

  @override
  bool operator ==(Object other) =>
      other is SecureContentBiometricCapability &&
      other.isAvailable == isAvailable &&
      listEquals(other.types, types);

  @override
  int get hashCode => Object.hash(isAvailable, Object.hashAll(types));

  @override
  String toString() => 'SecureContentBiometricCapability($isAvailable, $types)';

  static SecureContentBiometricCapability fromPigeon(
    pigeon.BiometricCapability capability,
  ) {
    return SecureContentBiometricCapability(
      isAvailable: capability.isAvailable,
      types: List.unmodifiable(
        capability.types.map(
          (type) => switch (type) {
            pigeon.BiometryType.face => SecureContentBiometryType.face,
            pigeon.BiometryType.fingerprint =>
              SecureContentBiometryType.fingerprint,
            pigeon.BiometryType.iris => SecureContentBiometryType.iris,
            pigeon.BiometryType.unknown => SecureContentBiometryType.unknown,
          },
        ),
      ),
    );
  }
}
