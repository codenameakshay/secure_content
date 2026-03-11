import 'pigeon/secure_content_api.g.dart' as pigeon;

enum SecureContentEventType {
  platformReady,
  screenshotCaptured,
  recordingStarted,
  recordingStopped,
  appSwitcherProtected,
  appSwitcherUnprotected,
  biometricAuthSucceeded,
  biometricAuthFailed,
  biometricUnavailable,
  integritySafe,
  integrityRiskDetected,
  clipboardSet,
  clipboardCleared,
  idleLockActivated,
  idleLockReleased,
  unknown,
}

class SecureContentEvent {
  const SecureContentEvent({
    required this.type,
    this.platform,
    this.timestamp,
    this.payload,
  });

  final SecureContentEventType type;
  final String? platform;
  final DateTime? timestamp;
  final Map<String, Object?>? payload;

  factory SecureContentEvent.fromPigeon(pigeon.SecureEvent event) {
    return SecureContentEvent(
      type: _eventTypeFromString(event.type),
      platform: event.platform,
      timestamp: _tryParseDateTime(event.timestamp),
      payload: <String, Object?>{
        'type': event.type,
        'platform': event.platform,
        'timestamp': event.timestamp,
      },
    );
  }

  static SecureContentEventType _eventTypeFromString(String type) {
    switch (type) {
      case 'platformReady':
        return SecureContentEventType.platformReady;
      case 'screenshotCaptured':
        return SecureContentEventType.screenshotCaptured;
      case 'recordingStarted':
        return SecureContentEventType.recordingStarted;
      case 'recordingStopped':
        return SecureContentEventType.recordingStopped;
      case 'appSwitcherProtected':
        return SecureContentEventType.appSwitcherProtected;
      case 'appSwitcherUnprotected':
        return SecureContentEventType.appSwitcherUnprotected;
      case 'biometricAuthSucceeded':
        return SecureContentEventType.biometricAuthSucceeded;
      case 'biometricAuthFailed':
        return SecureContentEventType.biometricAuthFailed;
      case 'biometricUnavailable':
        return SecureContentEventType.biometricUnavailable;
      case 'integritySafe':
        return SecureContentEventType.integritySafe;
      case 'integrityRiskDetected':
        return SecureContentEventType.integrityRiskDetected;
      case 'clipboardSet':
        return SecureContentEventType.clipboardSet;
      case 'clipboardCleared':
        return SecureContentEventType.clipboardCleared;
      case 'idleLockActivated':
        return SecureContentEventType.idleLockActivated;
      case 'idleLockReleased':
        return SecureContentEventType.idleLockReleased;
      default:
        return SecureContentEventType.unknown;
    }
  }

  static DateTime? _tryParseDateTime(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return DateTime.tryParse(value);
  }
}
