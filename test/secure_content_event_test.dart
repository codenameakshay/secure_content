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
}
