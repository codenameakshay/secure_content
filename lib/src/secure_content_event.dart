import 'pigeon/secure_content_api.g.dart' as pigeon;

enum SecureContentEventType {
  screenshotCaptured,
  recordingStarted,
  recordingStopped,
  appSwitcherProtected,
  appSwitcherUnprotected,
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
