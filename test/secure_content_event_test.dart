import 'package:flutter_test/flutter_test.dart';
import 'package:secure_content/src/pigeon/secure_content_api.g.dart' as pigeon;
import 'package:secure_content/src/secure_content_event.dart';

void main() {
  test('parses Android epoch milliseconds as UTC', () {
    final event = SecureContentEvent.fromPigeon(
      pigeon.SecureEvent(
        type: 'platformReady',
        platform: 'android',
        timestamp: '1726400000000',
      ),
    );

    expect(event.timestamp, DateTime.utc(2024, 9, 15, 11, 33, 20));
  });

  test('unrecognized event names map to unknown', () {
    for (final type in <String>[
      '',
      'BiometricAuthSucceeded',
      ' futureEvent ',
    ]) {
      final event = SecureContentEvent.fromPigeon(
        pigeon.SecureEvent(type: type, platform: 'test', timestamp: null),
      );
      expect(event.type, SecureContentEventType.unknown, reason: type);
    }
  });

  test('invalid and out-of-range epoch timestamps are ignored', () {
    for (final timestamp in <String>[
      '',
      'not-a-time',
      '8640000000000001',
      '999999999999999999999999999999999999',
    ]) {
      expect(
        () => SecureContentEvent.fromPigeon(
          pigeon.SecureEvent(
            type: 'platformReady',
            platform: 'android',
            timestamp: timestamp,
          ),
        ),
        returnsNormally,
        reason: timestamp,
      );
      final event = SecureContentEvent.fromPigeon(
        pigeon.SecureEvent(
          type: 'platformReady',
          platform: 'android',
          timestamp: timestamp,
        ),
      );
      expect(event.timestamp, isNull, reason: timestamp);
    }
  });
}
