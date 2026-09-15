import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_content/secure_content.dart';
import 'package:secure_content/src/secure_content_platform.dart';
import 'package:secure_content/src/secure_content_service.dart';

void main() {
  const channelPrefix =
      'dev.flutter.pigeon.secure_content.SecureContentHostApi';
  final codec = StandardMessageCodec();

  setUp(() {
    SecureContentPlatform.debugIsSupportedPlatformOverride = false;

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
      messenger.setMockMessageHandler('$channelPrefix.$method', (
        ByteData? message,
      ) async {
        if (method == 'isScreenCaptured') {
          return codec.encodeMessage(<Object?>[false]);
        }
        return codec.encodeMessage(<Object?>[]);
      });
    }
  });

  tearDown(() {
    SecureContentPlatform.debugIsSupportedPlatformOverride = null;
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
    ValueChanged<SecureContentEvent>? onEvent,
  }) {
    return MaterialApp(
      home: SecureContentScope(
        enabled: enabled,
        policy: policy ?? const SecureContentPolicy(),
        lockScreenBuilder: lockScreenBuilder,
        hardBlockBuilder: hardBlockBuilder,
        onEvent: onEvent,
        child: child ?? const Text('protected'),
      ),
    );
  }

  // (a) Default UI renders when builders are null
  group('default UI', () {
    testWidgets('renders default lock screen when locked', (tester) async {
      await tester.pumpWidget(
        buildScope(
          policy: const SecureContentPolicy(
            inactivityTimeout: Duration(milliseconds: 10),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Session locked'), findsOneWidget);
      expect(find.byType(ColoredBox), findsWidgets);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is ColoredBox && widget.color == Colors.black,
        ),
        findsOneWidget,
      );
    });

    testWidgets('renders default hard block screen when hard blocked', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildScope(
          policy: const SecureContentPolicy(hardBlockOnIntegrityRisk: true),
        ),
      );

      await tester.pump();
      await tester.pump();

      SecureContentService.instance.emitLocalEvent(
        SecureContentEventType.integrityRiskDetected,
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Access blocked for security reasons.'), findsOneWidget);
    });

    testWidgets('renders child when not locked', (tester) async {
      await tester.pumpWidget(buildScope());
      await tester.pump();
      await tester.pump();

      expect(find.text('protected'), findsOneWidget);
      expect(find.text('Session locked'), findsNothing);
    });
  });

  // AUTH-02: initial biometric lock must be synchronous, before any async
  // integrity work, so protected content never flashes on the first frame.
  group('initial lock timing', () {
    testWidgets(
      'locks on the very first frame, before integrity checks can resolve',
      (tester) async {
        await tester.pumpWidget(
          buildScope(
            policy: const SecureContentPolicy(
              requireBiometricOnResume: true,
              enableIntegrityChecks: true,
            ),
          ),
        );

        // No extra pump: this is the first frame produced by pumpWidget.
        // The lock overlay must already be present (it is opaque and covers
        // the child), proving the lock was applied before the async
        // integrity check could possibly have resolved.
        expect(find.text('Session locked'), findsOneWidget);

        // Resolve the in-flight biometric request so it does not leak into
        // later tests sharing the SecureContentService singleton.
        SecureContentService.instance.emitLocalEvent(
          SecureContentEventType.biometricAuthSucceeded,
        );
        await tester.pump();
      },
    );
  });

  group('biometric request lifecycle', () {
    testWidgets('a stale result cannot unlock a re-enabled scope', (
      tester,
    ) async {
      SecureContentPlatform.debugIsSupportedPlatformOverride = true;
      const policy = SecureContentPolicy(requireBiometricOnResume: true);

      await tester.pumpWidget(buildScope(policy: policy));
      expect(find.text('Session locked'), findsOneWidget);

      await tester.pumpWidget(buildScope(enabled: false, policy: policy));
      await tester.pump();
      expect(find.text('protected'), findsOneWidget);

      await tester.pumpWidget(buildScope(policy: policy));
      await tester.pump();
      expect(find.text('Session locked'), findsOneWidget);

      // Complete the original request. The scope must ignore it, wait for the
      // fresh request to start, and remain locked.
      SecureContentService.instance.emitLocalEvent(
        SecureContentEventType.biometricAuthSucceeded,
      );
      await tester.pump();
      expect(find.text('Session locked'), findsOneWidget);

      // Complete the fresh request to release this scope.
      SecureContentService.instance.emitLocalEvent(
        SecureContentEventType.biometricAuthSucceeded,
      );
      await tester.pump();
      expect(find.text('protected'), findsOneWidget);
    });
  });

  // (b) Custom builder renders when provided
  group('custom builders', () {
    testWidgets(
      'renders custom lock screen when lockScreenBuilder is provided',
      (tester) async {
        await tester.pumpWidget(
          buildScope(
            policy: const SecureContentPolicy(
              inactivityTimeout: Duration(milliseconds: 10),
            ),
            lockScreenBuilder: (context, onUnlock) =>
                const Text('CUSTOM LOCK', key: Key('custom_lock')),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text('CUSTOM LOCK'), findsOneWidget);
        expect(find.text('Session locked'), findsNothing);
      },
    );

    testWidgets(
      'renders custom hard block screen when hardBlockBuilder is provided',
      (tester) async {
        await tester.pumpWidget(
          buildScope(
            policy: const SecureContentPolicy(hardBlockOnIntegrityRisk: true),
            hardBlockBuilder: (context) =>
                const Text('CUSTOM BLOCK', key: Key('custom_block')),
          ),
        );

        await tester.pump();
        await tester.pump();

        SecureContentService.instance.emitLocalEvent(
          SecureContentEventType.integrityRiskDetected,
        );
        await tester.pump();
        await tester.pump();

        expect(find.text('CUSTOM BLOCK'), findsOneWidget);
        expect(find.text('Access blocked for security reasons.'), findsNothing);
      },
    );
  });

  // STATE-01: enabled:false must disable integrity checks / hard-block UI.
  group('disabled scope', () {
    testWidgets(
      'does not show the hard block screen when disabled, even on integrity risk',
      (tester) async {
        await tester.pumpWidget(
          buildScope(
            enabled: false,
            policy: const SecureContentPolicy(hardBlockOnIntegrityRisk: true),
          ),
        );
        await tester.pump();
        await tester.pump();

        SecureContentService.instance.emitLocalEvent(
          SecureContentEventType.integrityRiskDetected,
        );
        await tester.pump();
        await tester.pump();

        expect(find.text('Access blocked for security reasons.'), findsNothing);
        expect(find.text('protected'), findsOneWidget);
      },
    );
  });

  // AUTH-03: explicit biometric-unavailable state/UI with a clear, still
  // fail-closed recovery path.
  group('biometric unavailable', () {
    testWidgets('shows an explicit unavailable message and stays locked, then '
        'recovers once biometrics succeed on retry', (tester) async {
      SecureContentPlatform.debugIsSupportedPlatformOverride = true;

      await tester.pumpWidget(
        buildScope(
          policy: const SecureContentPolicy(requireBiometricOnResume: true),
        ),
      );

      SecureContentService.instance.emitLocalEvent(
        SecureContentEventType.biometricUnavailable,
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Biometric authentication unavailable'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);

      // Fail-closed: tapping the recovery action re-attempts biometric
      // auth, it never unlocks directly.
      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(find.text('Biometric authentication unavailable'), findsOneWidget);

      SecureContentService.instance.emitLocalEvent(
        SecureContentEventType.biometricAuthSucceeded,
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('protected'), findsOneWidget);
      expect(find.text('Biometric authentication unavailable'), findsNothing);
    });
  });

  // EVENT-01: a throwing onEvent callback must not block internal handling.
  group('onEvent error isolation', () {
    testWidgets('internal event handling still runs when onEvent throws', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildScope(
          onEvent: (event) {
            if (event.type == SecureContentEventType.recordingStarted) {
              throw StateError('boom from consumer onEvent');
            }
          },
        ),
      );
      await tester.pump();
      await tester.pump();

      SecureContentService.instance.emitLocalEvent(
        SecureContentEventType.recordingStarted,
      );
      await tester.pump();
      await tester.pump();

      // The callback's exception is reported through FlutterError, not
      // swallowed silently and not left to crash the stream listener.
      expect(tester.takeException(), isA<StateError>());

      // Internal state (the capture overlay) must still have updated
      // despite the callback throwing.
      expect(find.byType(DecoratedBox), findsWidgets);
    });
  });

  // LIFE-01: runtime policy/enabled changes must take effect immediately.
  group('policy changes take effect', () {
    testWidgets('disabling the scope clears an active hard block immediately', (
      tester,
    ) async {
      const policy = SecureContentPolicy(hardBlockOnIntegrityRisk: true);
      await tester.pumpWidget(buildScope(policy: policy));
      await tester.pump();
      await tester.pump();

      SecureContentService.instance.emitLocalEvent(
        SecureContentEventType.integrityRiskDetected,
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Access blocked for security reasons.'), findsOneWidget);

      await tester.pumpWidget(buildScope(enabled: false, policy: policy));
      await tester.pump();

      expect(find.text('Access blocked for security reasons.'), findsNothing);
    });

    testWidgets('disabling hard-block policy removes an active hard block', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildScope(
          policy: const SecureContentPolicy(hardBlockOnIntegrityRisk: true),
        ),
      );
      await tester.pump();

      SecureContentService.instance.emitLocalEvent(
        SecureContentEventType.integrityRiskDetected,
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Access blocked for security reasons.'), findsOneWidget);

      await tester.pumpWidget(buildScope());
      await tester.pump();

      expect(find.text('Access blocked for security reasons.'), findsNothing);
      expect(find.text('protected'), findsOneWidget);
    });

    testWidgets('re-enabling a scope reapplies biometric locking', (
      tester,
    ) async {
      SecureContentPlatform.debugIsSupportedPlatformOverride = true;
      const policy = SecureContentPolicy(requireBiometricOnResume: true);

      await tester.pumpWidget(buildScope(enabled: false, policy: policy));
      await tester.pump();
      expect(find.text('protected'), findsOneWidget);

      await tester.pumpWidget(buildScope(policy: policy));
      await tester.pump();

      expect(find.text('Session locked'), findsOneWidget);

      SecureContentService.instance.emitLocalEvent(
        SecureContentEventType.biometricAuthSucceeded,
      );
      await tester.pump();
    });
  });

  // LIFE-02: lifecycle-derived UI state must update through setState.
  group('lifecycle-driven risk state', () {
    testWidgets('app becoming inactive shows the risk watermark immediately', (
      tester,
    ) async {
      await tester.pumpWidget(buildScope());
      await tester.pump();
      await tester.pump();

      bool hasWatermark() => find
          .byWidgetPredicate(
            (widget) => widget.runtimeType.toString() == '_RiskWatermarkLayer',
          )
          .evaluate()
          .isNotEmpty;

      expect(hasWatermark(), isFalse);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();

      expect(hasWatermark(), isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(hasWatermark(), isFalse);
    });
  });

  // (c) onUnlock actually unlocks
  group('unlock', () {
    testWidgets('default lock screen unlocks when unlock button is pressed', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildScope(
          policy: const SecureContentPolicy(
            inactivityTimeout: Duration(milliseconds: 10),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Session locked'), findsOneWidget);

      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();

      expect(find.text('Session locked'), findsNothing);
      expect(find.text('protected'), findsOneWidget);
    });

    testWidgets('custom lock screen onUnlock callback dismisses the overlay', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildScope(
          policy: const SecureContentPolicy(
            inactivityTimeout: Duration(milliseconds: 10),
          ),
          lockScreenBuilder: (context, onUnlock) => ElevatedButton(
            key: const Key('custom_unlock_button'),
            onPressed: onUnlock,
            child: const Text('Custom Unlock'),
          ),
        ),
      );

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
