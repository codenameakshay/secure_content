import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_content/secure_content.dart';
import 'package:secure_content/src/secure_content_service.dart';

void main() {
  const channelPrefix =
      'dev.flutter.pigeon.secure_content.SecureContentHostApi';
  final codec = StandardMessageCodec();

  setUpAll(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final method in [
      'configureProtection',
      'isScreenCaptured',
      'requestBiometricAuth',
      'checkIntegrity',
      'setSensitiveClipboard',
      'clearSensitiveClipboard',
    ]) {
      messenger.setMockMessageHandler(
        '$channelPrefix.$method',
        (ByteData? message) async {
          if (method == 'isScreenCaptured') {
            return codec.encodeMessage(<Object?>[false]);
          }
          return null;
        },
      );
    }
  });

  tearDownAll(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final method in [
      'configureProtection',
      'isScreenCaptured',
      'requestBiometricAuth',
      'checkIntegrity',
      'setSensitiveClipboard',
      'clearSensitiveClipboard',
    ]) {
      messenger.setMockMessageHandler('$channelPrefix.$method', null);
    }
  });

  Widget buildScope({
    bool enabled = true,
    Widget? child,
    SecureContentPolicy? policy,
    LockScreenBuilder? lockScreenBuilder,
    HardBlockBuilder? hardBlockBuilder,
  }) {
    return MaterialApp(
      home: SecureContentScope(
        enabled: enabled,
        policy: policy ?? const SecureContentPolicy(),
        lockScreenBuilder: lockScreenBuilder,
        hardBlockBuilder: hardBlockBuilder,
        child: child ?? const Text('protected'),
      ),
    );
  }

  // (a) Default UI renders when builders are null
  group('default UI', () {
    testWidgets('renders default lock screen when locked', (tester) async {
      await tester.pumpWidget(buildScope(
        policy: const SecureContentPolicy(
          inactivityTimeout: Duration(milliseconds: 10),
        ),
      ));

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Session locked'), findsOneWidget);
      expect(find.byType(ColoredBox), findsWidgets);
    });

    testWidgets('renders default hard block screen when hard blocked',
        (tester) async {
      await tester.pumpWidget(buildScope(
        policy: const SecureContentPolicy(hardBlockOnIntegrityRisk: true),
      ));

      await tester.pump();
      await tester.pump();

      SecureContentService.instance
          .emitLocalEvent(SecureContentEventType.integrityRiskDetected);
      await tester.pump();
      await tester.pump();

      expect(
        find.text('Access blocked for security reasons.'),
        findsOneWidget,
      );
    });

    testWidgets('renders child when not locked', (tester) async {
      await tester.pumpWidget(buildScope());
      await tester.pump();
      await tester.pump();

      expect(find.text('protected'), findsOneWidget);
      expect(find.text('Session locked'), findsNothing);
    });
  });

  // (b) Custom builder renders when provided
  group('custom builders', () {
    testWidgets('renders custom lock screen when lockScreenBuilder is provided',
        (tester) async {
      await tester.pumpWidget(buildScope(
        policy: const SecureContentPolicy(
          inactivityTimeout: Duration(milliseconds: 10),
        ),
        lockScreenBuilder: (context, onUnlock) =>
            const Text('CUSTOM LOCK', key: Key('custom_lock')),
      ));

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('CUSTOM LOCK'), findsOneWidget);
      expect(find.text('Session locked'), findsNothing);
    });

    testWidgets(
        'renders custom hard block screen when hardBlockBuilder is provided',
        (tester) async {
      await tester.pumpWidget(buildScope(
        policy: const SecureContentPolicy(hardBlockOnIntegrityRisk: true),
        hardBlockBuilder: (context) =>
            const Text('CUSTOM BLOCK', key: Key('custom_block')),
      ));

      await tester.pump();
      await tester.pump();

      SecureContentService.instance
          .emitLocalEvent(SecureContentEventType.integrityRiskDetected);
      await tester.pump();
      await tester.pump();

      expect(find.text('CUSTOM BLOCK'), findsOneWidget);
      expect(
        find.text('Access blocked for security reasons.'),
        findsNothing,
      );
    });
  });

  // (c) onUnlock actually unlocks
  group('unlock', () {
    testWidgets('default lock screen unlocks when unlock button is pressed',
        (tester) async {
      await tester.pumpWidget(buildScope(
        policy: const SecureContentPolicy(
          inactivityTimeout: Duration(milliseconds: 10),
        ),
      ));

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Session locked'), findsOneWidget);

      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();

      expect(find.text('Session locked'), findsNothing);
      expect(find.text('protected'), findsOneWidget);
    });

    testWidgets('custom lock screen onUnlock callback dismisses the overlay',
        (tester) async {
      await tester.pumpWidget(buildScope(
        policy: const SecureContentPolicy(
          inactivityTimeout: Duration(milliseconds: 10),
        ),
        lockScreenBuilder: (context, onUnlock) => ElevatedButton(
          key: const Key('custom_unlock_button'),
          onPressed: onUnlock,
          child: const Text('Custom Unlock'),
        ),
      ));

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Custom Unlock'), findsOneWidget);

      await tester.tap(find.byKey(const Key('custom_unlock_button')));
      await tester.pump();

      expect(find.text('Custom Unlock'), findsNothing);
      expect(find.text('protected'), findsOneWidget);
    });
  });
}
