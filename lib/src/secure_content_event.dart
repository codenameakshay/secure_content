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

  static SecureContentEvent fromMap(Map<Object?, Object?> map) {
    final rawType = map['type']?.toString() ?? '';
    return SecureContentEvent(
      type: _eventTypeFromString(rawType),
      platform: map['platform']?.toString(),
      timestamp: _tryParseDateTime(map['timestamp']?.toString()),
      payload: map.cast<Object?, Object?>().map(
        (key, value) => MapEntry(key.toString(), value),
      ),
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
