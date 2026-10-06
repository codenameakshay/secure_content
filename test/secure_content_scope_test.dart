import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_content/secure_content.dart';
import 'package:secure_content/src/pigeon/secure_content_api.g.dart' as pigeon;
import 'package:secure_content/src/secure_content_platform.dart';
import 'package:secure_content/src/secure_content_service.dart';

void scopeTestWidgets(String description, WidgetTesterCallback body) {
  testWidgets(description, (tester) async {
    try {
      await body(tester);
    } finally {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.idle();
    }
  });
}

void main() {
  const channelPrefix =
      'dev.flutter.pigeon.secure_content.SecureContentHostApi';
  final codec = StandardMessageCodec();
  Completer<bool>? pendingCaptureQuery;
  Completer<void>? pendingConfiguration;
  Color? pendingConfigurationColor;
  Color? failConfigurationColor;
  final configurationColors = <int>[];
  final hostMethods = <String>[];
  var biometricPromptCount = 0;
  var mockCaptureState = false;

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
        hostMethods.add(method);
        if (method == 'isScreenCaptured') {
          final pending = pendingCaptureQuery;
          final captured = pending == null
              ? mockCaptureState
              : await pending.future;
          return codec.encodeMessage(<Object?>[captured]);
        }
        if (method == 'configureProtection') {
          final config =
              (pigeon.SecureContentHostApi.pigeonChannelCodec.decodeMessage(
                            message,
                          )!
                          as List<Object?>)
                      .first
                  as pigeon.ProtectionConfig;
          configurationColors.add(config.appSwitcherColor);
          if (config.appSwitcherColor ==
              pendingConfigurationColor?.toARGB32()) {
            await pendingConfiguration?.future;
          }
          if (config.appSwitcherColor == failConfigurationColor?.toARGB32()) {
            failConfigurationColor = null;
            return codec.encodeMessage(<Object?>[
              'configure-failed',
              'The test requested a failure',
              null,
            ]);
          }
        }
        if (method == 'requestBiometricAuth') {
          biometricPromptCount += 1;
        }
        return codec.encodeMessage(<Object?>[]);
      });
    }
  });

  tearDown(() {
    pendingCaptureQuery = null;
    pendingConfiguration = null;
    pendingConfigurationColor = null;
    failConfigurationColor = null;
    configurationColors.clear();
    hostMethods.clear();
    biometricPromptCount = 0;
    mockCaptureState = false;
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
    Color appSwitcherColor = Colors.black,
    SecureContentPolicy? policy,
    WidgetBuilder? overlayBuilder,
    LockScreenBuilder? lockScreenBuilder,
    HardBlockBuilder? hardBlockBuilder,
    ValueChanged<SecureContentEvent>? onEvent,
  }) {
    return MaterialApp(
      home: SecureContentScope(
        enabled: enabled,
        appSwitcherColor: appSwitcherColor,
        policy: policy ?? const SecureContentPolicy(),
        overlayBuilder: overlayBuilder,
        lockScreenBuilder: lockScreenBuilder,
        hardBlockBuilder: hardBlockBuilder,
        onEvent: onEvent,
        child: child ?? const Text('protected'),
      ),
    );
  }

  // (a) Default UI renders when builders are null
  group('default UI', () {
    scopeTestWidgets('renders default lock screen when locked', (tester) async {
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

    scopeTestWidgets('keyboard and pointer-signal input reset inactivity', (
      tester,
    ) async {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      await tester.pumpWidget(
        buildScope(
          policy: const SecureContentPolicy(
            inactivityTimeout: Duration(milliseconds: 100),
          ),
          child: Material(
            child: TextField(
              key: const Key('active-field'),
              focusNode: focusNode,
              autofocus: true,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 60));

      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('Session locked'), findsNothing);

      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(find.byKey(const Key('active-field'))),
          scrollDelta: const Offset(0, 12),
        ),
      );
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('Session locked'), findsNothing);
    });

    scopeTestWidgets('soft keyboard text entry resets inactivity', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildScope(
          policy: const SecureContentPolicy(
            inactivityTimeout: Duration(milliseconds: 100),
          ),
          child: const Material(child: TextField(autofocus: true)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 60));

      await tester.enterText(find.byType(TextField), 'new text');
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('Session locked'), findsNothing);

      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('Session locked'), findsOneWidget);
    });

    scopeTestWidgets('a child semantics action resets inactivity', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        buildScope(
          policy: const SecureContentPolicy(
            inactivityTimeout: Duration(milliseconds: 100),
          ),
          child: Semantics(
            key: const Key('accessible-control'),
            button: true,
            onTap: () {},
            child: const Text('Accessible control'),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 60));

      final node = tester.getSemantics(
        find.byKey(const Key('accessible-control')),
      );
      tester.binding.platformDispatcher.onSemanticsActionEvent!(
        SemanticsActionEvent(
          type: SemanticsAction.tap,
          viewId: tester.view.viewId,
          nodeId: node.id,
        ),
      );
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('Session locked'), findsNothing);

      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('Session locked'), findsOneWidget);
      semantics.dispose();
    });

    scopeTestWidgets(
      'an inactive-only transition keeps the current auth request',
      (tester) async {
        SecureContentPlatform.debugIsSupportedPlatformOverride = true;
        await tester.pumpWidget(
          buildScope(
            policy: const SecureContentPolicy(requireBiometricOnResume: true),
          ),
        );
        await tester.pump();
        expect(biometricPromptCount, 1);

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        expect(biometricPromptCount, 1);

        SecureContentService.instance.emitLocalEvent(
          SecureContentEventType.biometricAuthSucceeded,
        );
        await tester.pump();
        await tester.pump();
        expect(find.text('Session locked'), findsNothing);
        expect(biometricPromptCount, 1);
      },
    );

    scopeTestWidgets('inactivity elapsed in the background locks on resume', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildScope(
          policy: const SecureContentPolicy(
            inactivityTimeout: Duration(milliseconds: 80),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 30));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);

      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('Session locked'), findsOneWidget);
    });

    scopeTestWidgets(
      'a lock removes protected descendants from focus and semantics',
      (tester) async {
        final focusNode = FocusNode();
        addTearDown(focusNode.dispose);
        final semantics = tester.ensureSemantics();

        await tester.pumpWidget(
          buildScope(
            policy: const SecureContentPolicy(
              inactivityTimeout: Duration(milliseconds: 10),
            ),
            child: Material(
              child: TextField(
                key: const Key('secret-field'),
                focusNode: focusNode,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Secret account'),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));

        expect(find.text('Session locked'), findsOneWidget);
        expect(focusNode.hasFocus, isFalse);
        final semanticsTree = tester
            .binding
            .renderViews
            .single
            .owner!
            .semanticsOwner!
            .rootSemanticsNode!
            .toStringDeep();
        expect(semanticsTree, isNot(contains('Secret account')));
        semantics.dispose();
      },
    );

    scopeTestWidgets('renders default hard block screen when hard blocked', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildScope(
          policy: const SecureContentPolicy(
            enableIntegrityChecks: true,
            hardBlockOnIntegrityRisk: true,
          ),
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

    scopeTestWidgets('renders child when not locked', (tester) async {
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
    scopeTestWidgets(
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

  scopeTestWidgets(
    'supported scope covers content until native setup completes',
    (tester) async {
      SecureContentPlatform.debugIsSupportedPlatformOverride = true;
      pendingConfiguration = Completer<void>();
      pendingConfigurationColor = Colors.purple;
      var actionCount = 0;
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        buildScope(
          appSwitcherColor: Colors.purple,
          child: Material(
            child: ElevatedButton(
              key: const Key('protected-action'),
              onPressed: () => actionCount += 1,
              child: const Text('Sensitive action'),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1)),
      );
      await tester.pump();

      expect(
        tester
            .binding
            .renderViews
            .single
            .owner!
            .semanticsOwner!
            .rootSemanticsNode!
            .toStringDeep(),
        isNot(contains('Sensitive action')),
      );
      await tester.tap(
        find.byKey(const Key('protected-action')),
        warnIfMissed: false,
      );
      expect(actionCount, 0);

      pendingConfiguration!.complete();
      pendingConfiguration = null;
      pendingConfigurationColor = null;
      await tester.idle();
      await tester.pumpAndSettle();
      expect(
        configurationColors,
        contains(Colors.purple.toARGB32()),
        reason: 'host calls: $hostMethods',
      );
      expect(
        tester.getSemantics(find.byKey(const Key('protected-action'))),
        isNotNull,
      );
      await tester.tap(find.byKey(const Key('protected-action')));
      expect(actionCount, 1);
      semantics.dispose();
    },
  );

  scopeTestWidgets('native setup failure stays covered and retries on resume', (
    tester,
  ) async {
    SecureContentPlatform.debugIsSupportedPlatformOverride = true;
    failConfigurationColor = Colors.orange;
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      buildScope(
        appSwitcherColor: Colors.orange,
        child: const Text('Retry protected content'),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
    await tester.idle();
    await tester.pumpAndSettle();
    expect(
      configurationColors,
      contains(Colors.orange.toARGB32()),
      reason: 'host calls: $hostMethods',
    );

    expect(tester.takeException(), isA<PlatformException>());
    expect(
      tester
          .binding
          .renderViews
          .single
          .owner!
          .semanticsOwner!
          .rootSemanticsNode!
          .toStringDeep(),
      isNot(contains('Retry protected content')),
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(
      tester
          .binding
          .renderViews
          .single
          .owner!
          .semanticsOwner!
          .rootSemanticsNode!
          .toStringDeep(),
      contains('Retry protected content'),
    );
    semantics.dispose();
  });

  scopeTestWidgets(
    'a stale capture query cannot clear a newer recording event',
    (tester) async {
      SecureContentPlatform.debugIsSupportedPlatformOverride = true;
      pendingCaptureQuery = Completer<bool>();
      await tester.pumpWidget(
        buildScope(overlayBuilder: (_) => const Text('CAPTURE COVER')),
      );

      SecureContentService.instance.emitLocalEvent(
        SecureContentEventType.recordingStarted,
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('CAPTURE COVER'), findsOneWidget);

      pendingCaptureQuery!.complete(false);
      await tester.pump();
      await tester.pump();

      expect(find.text('CAPTURE COVER'), findsOneWidget);
    },
  );

  scopeTestWidgets('seeded bounded lifecycle and policy action sequences', (
    tester,
  ) async {
    SecureContentPlatform.debugIsSupportedPlatformOverride = true;
    const seeds = <int>[0x5eed, 0x1bad, 0xc0ffee, 0x7a11];
    const actionCount = 256;
    final semantics = tester.ensureSemantics();

    for (final seed in seeds) {
      final random = math.Random(seed);
      var enabled = true;
      var requireBiometrics = false;
      var lifecycle = AppLifecycleState.resumed;
      var biometricRequestActive = false;
      var requestCrossedBackground = false;
      final actions = <int>[];
      final receivedEvents = <SecureContentEventType>[];

      SecureContentPolicy policy() =>
          SecureContentPolicy(requireBiometricOnResume: requireBiometrics);

      Future<void> pumpCurrentScope() async {
        await tester.pumpWidget(
          buildScope(
            enabled: enabled,
            policy: policy(),
            overlayBuilder: (_) => const Text('SEQUENCE CAPTURE COVER'),
            onEvent: (event) => receivedEvents.add(event.type),
          ),
        );
        await tester.pump();
      }

      mockCaptureState = false;
      await pumpCurrentScope();
      for (var index = 0; index < actionCount; index += 1) {
        final action = random.nextInt(8);
        actions.add(action);
        switch (action) {
          case 0:
            mockCaptureState = true;
            SecureContentService.instance.emitLocalEvent(
              SecureContentEventType.recordingStarted,
            );
          case 1:
            mockCaptureState = false;
            SecureContentService.instance.emitLocalEvent(
              SecureContentEventType.recordingStopped,
            );
          case 2:
            enabled = !enabled;
            if (!enabled) {
              biometricRequestActive = false;
              requestCrossedBackground = false;
            } else if (requireBiometrics) {
              if (lifecycle == AppLifecycleState.resumed) {
                biometricRequestActive = true;
                requestCrossedBackground = false;
              }
            }
            await pumpCurrentScope();
          case 3:
            requireBiometrics = !requireBiometrics;
            if (!requireBiometrics) {
              biometricRequestActive = false;
              requestCrossedBackground = false;
            } else if (enabled) {
              if (lifecycle == AppLifecycleState.resumed) {
                biometricRequestActive = true;
                requestCrossedBackground = false;
              }
            }
            await pumpCurrentScope();
          case 4:
            lifecycle = AppLifecycleState.inactive;
            tester.binding.handleAppLifecycleStateChanged(lifecycle);
          case 5:
            lifecycle = AppLifecycleState.paused;
            tester.binding.handleAppLifecycleStateChanged(lifecycle);
            if (enabled && requireBiometrics) {
              requestCrossedBackground |= biometricRequestActive;
            }
          case 6:
            lifecycle = AppLifecycleState.resumed;
            tester.binding.handleAppLifecycleStateChanged(lifecycle);
            if (enabled && requireBiometrics) {
              if (!biometricRequestActive) {
                biometricRequestActive = true;
                requestCrossedBackground = false;
              }
            }
          case 7:
            final outcome = <SecureContentEventType>[
              SecureContentEventType.biometricAuthSucceeded,
              SecureContentEventType.biometricAuthFailed,
              SecureContentEventType.biometricUnavailable,
            ][random.nextInt(3)];
            SecureContentService.instance.emitLocalEvent(outcome);
            if (biometricRequestActive) {
              biometricRequestActive = false;
              if (requestCrossedBackground) {
                requestCrossedBackground = false;
                if (lifecycle == AppLifecycleState.resumed &&
                    enabled &&
                    requireBiometrics) {
                  biometricRequestActive = true;
                }
              } else if (outcome ==
                  SecureContentEventType.biometricAuthSucceeded) {
                // The targeted lifecycle tests below assert when a paused
                // request may release this lock.
              }
            }
        }
        await tester.idle();
        await tester.pump();
        await tester.pump();

        if (action == 0 || action == 1) {
          expect(
            receivedEvents,
            contains(
              action == 0
                  ? SecureContentEventType.recordingStarted
                  : SecureContentEventType.recordingStopped,
            ),
            reason: 'seed=$seed step=$index capture event delivered',
          );
        }

        if (!enabled) {
          expect(
            find.text('protected'),
            findsOneWidget,
            reason: 'seed=$seed step=$index disabled child invariant',
          );
        }
        expect(
          tester.takeException(),
          isNull,
          reason: 'seed=$seed actions=$actionCount step=$index',
        );
      }
    }
    semantics.dispose();
  });

  group('biometric request lifecycle', () {
    scopeTestWidgets(
      'a result received while disabled cannot unlock on re-enable',
      (tester) async {
        SecureContentPlatform.debugIsSupportedPlatformOverride = true;
        const policy = SecureContentPolicy(requireBiometricOnResume: true);

        await tester.pumpWidget(buildScope(enabled: false, policy: policy));
        await tester.pump();
        expect(find.text('protected'), findsOneWidget);

        SecureContentService.instance.emitLocalEvent(
          SecureContentEventType.biometricAuthSucceeded,
        );
        await tester.pump();

        await tester.pumpWidget(buildScope(policy: policy));
        await tester.pump();
        expect(find.text('Session locked'), findsOneWidget);

        SecureContentService.instance.emitLocalEvent(
          SecureContentEventType.biometricAuthSucceeded,
        );
        await tester.pump();
        expect(find.text('protected'), findsOneWidget);
      },
    );

    scopeTestWidgets(
      'auth success received while paused cannot reveal the child',
      (tester) async {
        SecureContentPlatform.debugIsSupportedPlatformOverride = true;
        const policy = SecureContentPolicy(requireBiometricOnResume: true);
        await tester.pumpWidget(buildScope(policy: policy));
        expect(find.text('Session locked'), findsOneWidget);

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        SecureContentService.instance.emitLocalEvent(
          SecureContentEventType.biometricAuthSucceeded,
        );
        await tester.pump();
        await tester.pump();
        expect(find.text('Session locked'), findsOneWidget);

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        SecureContentService.instance.emitLocalEvent(
          SecureContentEventType.biometricAuthSucceeded,
        );
        await tester.pump();
        await tester.pump();
        expect(find.text('Session locked'), findsNothing);
        expect(find.text('protected'), findsOneWidget);
      },
    );

    scopeTestWidgets(
      'auth started before background is rejected after resume',
      (tester) async {
        SecureContentPlatform.debugIsSupportedPlatformOverride = true;
        const policy = SecureContentPolicy(requireBiometricOnResume: true);
        await tester.pumpWidget(buildScope(policy: policy));
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();

        SecureContentService.instance.emitLocalEvent(
          SecureContentEventType.biometricAuthSucceeded,
        );
        await tester.pump();
        await tester.pump();
        expect(find.text('Session locked'), findsOneWidget);

        SecureContentService.instance.emitLocalEvent(
          SecureContentEventType.biometricAuthSucceeded,
        );
        await tester.pump();
        await tester.pump();
        expect(find.text('Session locked'), findsNothing);
      },
    );
  });

  scopeTestWidgets('capture cover blocks protected input and is fully opaque', (
    tester,
  ) async {
    var actionCount = 0;
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      buildScope(
        child: Material(
          child: ElevatedButton(
            key: const Key('captured-action'),
            onPressed: () => actionCount += 1,
            child: const Text('Captured secret'),
          ),
        ),
      ),
    );
    await tester.pump();

    SecureContentService.instance.emitLocalEvent(
      SecureContentEventType.recordingStarted,
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.byWidgetPredicate(
        (widget) => widget is ColoredBox && widget.color == Colors.black,
      ),
      findsOneWidget,
    );
    expect(
      tester
          .binding
          .renderViews
          .single
          .owner!
          .semanticsOwner!
          .rootSemanticsNode!
          .toStringDeep(),
      isNot(contains('Captured secret')),
    );
    await tester.tap(
      find.byKey(const Key('captured-action')),
      warnIfMissed: false,
    );
    expect(actionCount, 0);

    SecureContentService.instance.emitLocalEvent(
      SecureContentEventType.recordingStopped,
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const Key('captured-action')));
    expect(actionCount, 1);
    semantics.dispose();
  });

  // (b) Custom builder renders when provided
  group('custom builders', () {
    scopeTestWidgets(
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

    scopeTestWidgets(
      'renders custom hard block screen when hardBlockBuilder is provided',
      (tester) async {
        await tester.pumpWidget(
          buildScope(
            policy: const SecureContentPolicy(
              enableIntegrityChecks: true,
              hardBlockOnIntegrityRisk: true,
            ),
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
    scopeTestWidgets(
      'does not show the hard block screen when disabled, even on integrity risk',
      (tester) async {
        await tester.pumpWidget(
          buildScope(
            enabled: false,
            policy: const SecureContentPolicy(
              enableIntegrityChecks: true,
              hardBlockOnIntegrityRisk: true,
            ),
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
    scopeTestWidgets(
      'shows an explicit unavailable message and stays locked, then '
      'recovers once biometrics succeed on retry',
      (tester) async {
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

        expect(
          find.text('Biometric authentication unavailable'),
          findsOneWidget,
        );
        expect(find.text('Try again'), findsOneWidget);

        // Fail-closed: tapping the recovery action re-attempts biometric
        // auth, it never unlocks directly.
        await tester.tap(find.text('Try again'));
        await tester.pump();
        expect(
          find.text('Biometric authentication unavailable'),
          findsOneWidget,
        );

        SecureContentService.instance.emitLocalEvent(
          SecureContentEventType.biometricAuthSucceeded,
        );
        await tester.pump();
        await tester.pump();

        expect(find.text('protected'), findsOneWidget);
        expect(find.text('Biometric authentication unavailable'), findsNothing);
      },
    );
  });

  // EVENT-01: a throwing onEvent callback must not block internal handling.
  group('onEvent error isolation', () {
    scopeTestWidgets('internal event handling still runs when onEvent throws', (
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
      expect(find.byType(ColoredBox), findsWidgets);
    });
  });

  // LIFE-01: runtime policy/enabled changes must take effect immediately.
  group('policy changes take effect', () {
    scopeTestWidgets(
      'disabling the scope clears an active hard block immediately',
      (tester) async {
        const policy = SecureContentPolicy(
          enableIntegrityChecks: true,
          hardBlockOnIntegrityRisk: true,
        );
        await tester.pumpWidget(buildScope(policy: policy));
        await tester.pump();
        await tester.pump();

        SecureContentService.instance.emitLocalEvent(
          SecureContentEventType.integrityRiskDetected,
        );
        await tester.pump();
        await tester.pump();
        expect(
          find.text('Access blocked for security reasons.'),
          findsOneWidget,
        );

        await tester.pumpWidget(buildScope(enabled: false, policy: policy));
        await tester.pump();

        expect(find.text('Access blocked for security reasons.'), findsNothing);
      },
    );

    scopeTestWidgets(
      'disabling hard-block policy removes an active hard block',
      (tester) async {
        await tester.pumpWidget(
          buildScope(
            policy: const SecureContentPolicy(
              enableIntegrityChecks: true,
              hardBlockOnIntegrityRisk: true,
            ),
          ),
        );
        await tester.pump();

        SecureContentService.instance.emitLocalEvent(
          SecureContentEventType.integrityRiskDetected,
        );
        await tester.pump();
        await tester.pump();
        expect(
          find.text('Access blocked for security reasons.'),
          findsOneWidget,
        );

        await tester.pumpWidget(buildScope());
        await tester.pump();

        expect(find.text('Access blocked for security reasons.'), findsNothing);
        expect(find.text('protected'), findsOneWidget);
      },
    );

    scopeTestWidgets(
      'disabling integrity checks clears and ignores risk state',
      (tester) async {
        const enabledPolicy = SecureContentPolicy(
          enableIntegrityChecks: true,
          hardBlockOnIntegrityRisk: true,
        );
        await tester.pumpWidget(buildScope(policy: enabledPolicy));
        await tester.pump();

        SecureContentService.instance.emitLocalEvent(
          SecureContentEventType.integrityRiskDetected,
        );
        await tester.pump();
        await tester.pump();
        expect(
          find.text('Access blocked for security reasons.'),
          findsOneWidget,
        );

        await tester.pumpWidget(
          buildScope(
            policy: const SecureContentPolicy(hardBlockOnIntegrityRisk: true),
          ),
        );
        await tester.pump();
        expect(find.text('Access blocked for security reasons.'), findsNothing);

        SecureContentService.instance.emitLocalEvent(
          SecureContentEventType.integrityRiskDetected,
        );
        await tester.pump();
        await tester.pump();
        expect(find.text('Access blocked for security reasons.'), findsNothing);
      },
    );

    scopeTestWidgets('re-enabling a scope reapplies biometric locking', (
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
    scopeTestWidgets(
      'app becoming inactive shows the risk watermark immediately',
      (tester) async {
        await tester.pumpWidget(buildScope());
        await tester.pump();
        await tester.pump();

        bool hasWatermark() => find
            .byWidgetPredicate(
              (widget) =>
                  widget.runtimeType.toString() == '_RiskWatermarkLayer',
            )
            .evaluate()
            .isNotEmpty;

        expect(hasWatermark(), isFalse);

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();

        expect(hasWatermark(), isTrue);

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();

        expect(hasWatermark(), isFalse);
      },
    );
  });

  // (c) onUnlock actually unlocks
  group('unlock', () {
    scopeTestWidgets(
      'default lock screen unlocks when unlock button is pressed',
      (tester) async {
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
      },
    );

    scopeTestWidgets(
      'custom lock screen onUnlock callback dismisses the overlay',
      (tester) async {
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
      },
    );
  });
}
