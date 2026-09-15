import 'package:flutter_test/flutter_test.dart';
import 'package:secure_content/secure_content.dart';
import 'package:secure_content/src/secure_content_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SecureContentPlatform.debugIsSupportedPlatformOverride = false;
  });

  tearDown(() {
    SecureContentPlatform.debugIsSupportedPlatformOverride = null;
  });

  // CTRL-01: dispose must mark the controller disposed, set enabled false,
  // and make later calls no-ops.
  test(
    'dispose marks disposed, clears enabled, and ignores later calls',
    () async {
      final controller = SecureContentController();

      await controller.enable();
      expect(controller.enabled, isTrue);
      expect(controller.isDisposed, isFalse);

      await controller.dispose();
      expect(controller.isDisposed, isTrue);
      expect(controller.enabled, isFalse);

      // Later calls are ignored: enabled stays false, no exception, and a
      // second dispose() call is a safe no-op.
      await controller.enable();
      expect(controller.enabled, isFalse);

      await controller.setProtection(true);
      expect(controller.enabled, isFalse);

      await controller.dispose();
      expect(controller.isDisposed, isTrue);
    },
  );
}
