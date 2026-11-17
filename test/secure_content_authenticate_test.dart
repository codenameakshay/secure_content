import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_content/secure_content.dart';
import 'package:secure_content/src/pigeon/secure_content_api.g.dart' as pigeon;
import 'package:secure_content/src/secure_content_platform.dart';
import 'package:secure_content/src/secure_content_service.dart';

class _LifecycleBinding extends AutomatedTestWidgetsFlutterBinding {
  final Set<WidgetsBindingObserver> lifecycleListeners = {};

  @override
  void addObserver(WidgetsBindingObserver observer) {
    super.addObserver(observer);
    if (observer is AppLifecycleListener) lifecycleListeners.add(observer);
  }

  @override
  bool removeObserver(WidgetsBindingObserver observer) {
    lifecycleListeners.remove(observer);
    return super.removeObserver(observer);
  }
}

void main() {
  final binding = _LifecycleBinding();

  const prefix = 'dev.flutter.pigeon.secure_content.SecureContentHostApi';
  final codec = pigeon.SecureContentHostApi.pigeonChannelCodec;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final service = SecureContentService.instance;

  /// Native authenticate calls, in order, each waiting for its reply.
  late List<({String reason, bool biometricOnly, Completer<ByteData?> reply})>
  calls;
  late int legacyCalls;

  ByteData? encode(pigeon.AuthStatus status, [String? message]) =>
      codec.encodeMessage(<Object?>[
        pigeon.AuthResult(status: status, message: message),
      ]);

  ByteData? interrupted() => codec.encodeMessage(<Object?>[
    pigeon.AuthResult(status: pigeon.AuthStatus.canceled, interrupted: true),
  ]);

  void lifecycle(List<AppLifecycleState> states) {
    for (final state in states) {
      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(state);
    }
  }

  const toBackground = <AppLifecycleState>[
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ];
  const toForeground = <AppLifecycleState>[
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ];

  setUp(() {
    SecureContentPlatform.debugIsSupportedPlatformOverride = true;
    calls = [];
    legacyCalls = 0;
    messenger.setMockMessageHandler('$prefix.authenticate', (message) {
      final args = codec.decodeMessage(message) as List<Object?>;
      final reply = Completer<ByteData?>();
      calls.add((
        reason: args[0] as String,
        biometricOnly: args[1] as bool,
        reply: reply,
      ));
      return reply.future;
    });
    messenger.setMockMessageHandler('$prefix.requestBiometricAuth', (_) async {
      legacyCalls += 1;
      return codec.encodeMessage(<Object?>[null]);
    });
  });

  tearDown(() {
    SecureContentPlatform.debugIsSupportedPlatformOverride = null;
    messenger.setMockMessageHandler('$prefix.authenticate', null);
    messenger.setMockMessageHandler('$prefix.requestBiometricAuth', null);
    messenger.setMockMessageHandler('$prefix.getBiometricCapability', null);
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('maps every native status to the matching public status', () async {
    for (final status in pigeon.AuthStatus.values) {
      final result = SecureContent.authenticate(reason: 'r');
      await settle();
      calls.last.reply.complete(encode(status, 'm-${status.name}'));
      expect(
        await result,
        SecureContentAuthResult(
          SecureContentAuthStatus.values.byName(status.name),
          message: 'm-${status.name}',
        ),
      );
    }
    expect(calls, hasLength(pigeon.AuthStatus.values.length));
  });

  test('passes reason and biometricOnly, defaulting to false', () async {
    final normal = SecureContent.authenticate(reason: 'plain');
    await settle();
    calls.single.reply.complete(encode(pigeon.AuthStatus.success));
    expect((await normal).isSuccess, isTrue);

    final strict = SecureContent.authenticate(
      reason: 'strict',
      biometricOnly: true,
    );
    await settle();
    calls.last.reply.complete(encode(pigeon.AuthStatus.success));
    await strict;

    expect(calls.map((c) => (c.reason, c.biometricOnly)), [
      ('plain', false),
      ('strict', true),
    ]);
  });

  test('matching calls share one native prompt and its result', () async {
    final a = service.authenticate('a', biometricOnly: true);
    final b = SecureContent.authenticate(reason: 'b', biometricOnly: true);
    await settle();
    expect(calls, hasLength(1));

    calls.single.reply.complete(encode(pigeon.AuthStatus.canceled));
    expect(
      await a,
      const SecureContentAuthResult(SecureContentAuthStatus.canceled),
    );
    expect(
      await b,
      const SecureContentAuthResult(SecureContentAuthStatus.canceled),
    );

    // Settled: the next call opens a fresh prompt.
    final c = service.authenticate('c', biometricOnly: true);
    await settle();
    expect(calls, hasLength(2));
    calls.last.reply.complete(encode(pigeon.AuthStatus.success));
    expect((await c).isSuccess, isTrue);
  });

  test(
    'a biometric-only call never joins a prompt that accepts the passcode',
    () async {
      final lenient = service.authenticate('lenient');
      final strict = service.authenticate('strict', biometricOnly: true);
      await settle();
      expect(calls, hasLength(1));
      expect(calls.single.biometricOnly, isFalse);

      calls.single.reply.complete(encode(pigeon.AuthStatus.success));
      expect((await lenient).isSuccess, isTrue);
      await settle();

      // Only now, after the lenient prompt closed, does its own prompt open.
      expect(calls, hasLength(2));
      expect(calls.last.biometricOnly, isTrue);
      calls.last.reply.complete(encode(pigeon.AuthStatus.failed));
      expect(
        await strict,
        const SecureContentAuthResult(SecureContentAuthStatus.failed),
      );
    },
  );

  test('authenticate waits for a legacy prompt, and the legacy prompt waits '
      'for authenticate', () async {
    final legacy = service.requestBiometricAuth('legacy');
    final auth = service.authenticate('auth', biometricOnly: true);
    await settle();
    expect(legacyCalls, 1);
    expect(calls, isEmpty);

    service.emitLocalEvent(SecureContentEventType.biometricAuthSucceeded);
    expect(await legacy, SecureContentEventType.biometricAuthSucceeded);
    await settle();
    expect(calls, hasLength(1));

    final laterLegacy = service.requestBiometricAuth('later');
    await settle();
    expect(legacyCalls, 1, reason: 'waits for the authenticate prompt');
    // An event emitted while waiting belongs to no legacy request.
    service.emitLocalEvent(SecureContentEventType.biometricAuthFailed);

    calls.single.reply.complete(encode(pigeon.AuthStatus.success));
    expect((await auth).isSuccess, isTrue);
    await settle();
    expect(legacyCalls, 2);

    service.emitLocalEvent(SecureContentEventType.biometricUnavailable);
    expect(await laterLegacy, SecureContentEventType.biometricUnavailable);
  });

  test('a native error becomes an error result and frees the slot', () async {
    final first = service.authenticate('first');
    await settle();
    calls.single.reply.complete(
      codec.encodeMessage(<Object?>['native-error', 'boom', null]),
    );
    final result = await first;
    expect(result.status, SecureContentAuthStatus.error);
    expect(result.message, contains('boom'));

    final retry = service.authenticate('retry');
    await settle();
    expect(calls, hasLength(2));
    calls.last.reply.complete(encode(pigeon.AuthStatus.success));
    expect((await retry).isSuccess, isTrue);
  });

  test(
    'unsupported platforms report notAvailable without a native call',
    () async {
      SecureContentPlatform.debugIsSupportedPlatformOverride = false;
      expect(
        await SecureContent.authenticate(reason: 'r', biometricOnly: true),
        const SecureContentAuthResult(SecureContentAuthStatus.notAvailable),
      );
      expect(
        await SecureContent.getBiometricCapability(),
        const SecureContentBiometricCapability(
          isAvailable: false,
          types: <SecureContentBiometryType>[],
        ),
      );
      expect(calls, isEmpty);
    },
  );

  test('maps the biometric capability', () async {
    messenger.setMockMessageHandler(
      '$prefix.getBiometricCapability',
      (_) async => codec.encodeMessage(<Object?>[
        pigeon.BiometricCapability(
          isAvailable: true,
          types: pigeon.BiometryType.values,
        ),
      ]),
    );
    expect(
      await SecureContent.getBiometricCapability(),
      const SecureContentBiometricCapability(
        isAvailable: true,
        types: <SecureContentBiometryType>[
          SecureContentBiometryType.face,
          SecureContentBiometryType.fingerprint,
          SecureContentBiometryType.iris,
          SecureContentBiometryType.unknown,
        ],
      ),
    );
  });

  group('persistAcrossBackgrounding', () {
    setUp(() => lifecycle(const [AppLifecycleState.resumed]));

    test(
      'releases lifecycle listeners for every terminal result and error',
      () async {
        final initialListeners = binding.lifecycleListeners.length;
        for (final status in pigeon.AuthStatus.values) {
          final result = service.authenticate(
            'r',
            persistAcrossBackgrounding: true,
          );
          await settle();
          calls.last.reply.complete(encode(status));
          expect(
            (await result).status,
            SecureContentAuthStatus.values.byName(status.name),
          );
          expect(binding.lifecycleListeners.length, initialListeners);
        }
        final result = service.authenticate(
          'r',
          persistAcrossBackgrounding: true,
        );
        await settle();
        calls.last.reply.complete(
          codec.encodeMessage(<Object?>['native-error', 'boom', null]),
        );
        expect((await result).status, SecureContentAuthStatus.error);
        expect(binding.lifecycleListeners.length, initialListeners);
      },
    );

    test(
      'waits for resume when the native interruption arrives first',
      () async {
        final result = service.authenticate(
          'r',
          persistAcrossBackgrounding: true,
        );
        await settle();
        calls.single.reply.complete(interrupted());
        await settle();
        final callsBeforeResume = calls.length;
        lifecycle([...toBackground, ...toForeground]);
        await settle();
        calls.last.reply.complete(encode(pigeon.AuthStatus.success));
        expect((await result).isSuccess, isTrue);
        expect(callsBeforeResume, 1);
        expect(calls, hasLength(2));
      },
    );

    test('each repeated interruption needs another resume', () async {
      final result = service.authenticate(
        'r',
        persistAcrossBackgrounding: true,
      );
      await settle();
      lifecycle([...toBackground, ...toForeground]);
      calls.single.reply.complete(interrupted());
      await settle();
      expect(calls, hasLength(2));
      calls.last.reply.complete(interrupted());
      await settle();
      final callsBeforeNextResume = calls.length;
      lifecycle([...toBackground, ...toForeground]);
      await settle();
      calls.last.reply.complete(encode(pigeon.AuthStatus.failed));
      expect(
        await result,
        const SecureContentAuthResult(SecureContentAuthStatus.failed),
      );
      expect(callsBeforeNextResume, 2);
      expect(calls, hasLength(3));
    });

    test(
      'does not retry after a resume followed by another background',
      () async {
        final result = service.authenticate(
          'r',
          persistAcrossBackgrounding: true,
        );
        await settle();
        lifecycle(toBackground);
        calls.single.reply.complete(interrupted());
        await settle();
        lifecycle([...toForeground, ...toBackground]);
        await settle();
        final callsWhileBackgrounded = calls.length;
        lifecycle(toForeground);
        await settle();
        calls.last.reply.complete(encode(pigeon.AuthStatus.success));
        expect((await result).isSuccess, isTrue);
        expect(callsWhileBackgrounded, 1);
        expect(calls, hasLength(2));
      },
    );

    test('reopens an interrupted prompt once the app is resumed', () async {
      final first = SecureContent.authenticate(
        reason: 'r',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
      final joined = service.authenticate(
        'r',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
      await settle();
      lifecycle(toBackground);
      calls.single.reply.complete(interrupted());
      await settle();
      expect(calls, hasLength(1), reason: 'waits while in the background');

      lifecycle(toForeground);
      await settle();
      expect(calls, hasLength(2));
      expect(calls.last.biometricOnly, isTrue);
      calls.last.reply.complete(encode(pigeon.AuthStatus.success));

      expect((await first).isSuccess, isTrue);
      expect((await joined).isSuccess, isTrue);
    });

    test(
      'parked joined callers hold the gate before a fresh legacy prompt',
      () async {
        final first = service.authenticate(
          'first',
          persistAcrossBackgrounding: true,
        );
        await settle();
        lifecycle(toBackground);
        calls.single.reply.complete(interrupted());
        await settle();
        final joined = service.authenticate(
          'joined',
          persistAcrossBackgrounding: true,
        );
        final legacy = service.requestBiometricAuth('legacy');
        final differentKey = service.authenticate(
          'strict',
          biometricOnly: true,
        );
        await settle();
        expect(calls, hasLength(1));
        expect(legacyCalls, 0);
        lifecycle(toForeground);
        await settle();
        calls.last.reply.complete(encode(pigeon.AuthStatus.success));
        expect((await first).isSuccess, isTrue);
        expect((await joined).isSuccess, isTrue);
        await settle();
        expect(legacyCalls, 1);
        expect(calls, hasLength(2));
        service.emitLocalEvent(SecureContentEventType.biometricAuthFailed);
        expect(await legacy, SecureContentEventType.biometricAuthFailed);
        await settle();
        expect(calls.last.biometricOnly, isTrue);
        calls.last.reply.complete(encode(pigeon.AuthStatus.failed));
        expect((await differentKey).status, SecureContentAuthStatus.failed);
        expect(calls, hasLength(3));
      },
    );

    test('reopens at once when the app already came back', () async {
      final result = service.authenticate(
        'r',
        persistAcrossBackgrounding: true,
      );
      await settle();
      lifecycle([...toBackground, ...toForeground]);
      calls.single.reply.complete(interrupted());
      await settle();
      expect(calls, hasLength(2));
      calls.last.reply.complete(encode(pigeon.AuthStatus.failed));
      expect(
        await result,
        const SecureContentAuthResult(SecureContentAuthStatus.failed),
      );
    });

    test('a cancel by the person is never reopened', () async {
      final result = service.authenticate(
        'r',
        persistAcrossBackgrounding: true,
      );
      await settle();
      calls.single.reply.complete(encode(pigeon.AuthStatus.canceled));
      expect(
        await result,
        const SecureContentAuthResult(SecureContentAuthStatus.canceled),
      );
      expect(calls, hasLength(1));
    });

    test('without the option an interruption returns canceled', () async {
      final result = service.authenticate('r');
      await settle();
      lifecycle(toBackground);
      calls.single.reply.complete(interrupted());
      expect(
        await result,
        const SecureContentAuthResult(SecureContentAuthStatus.canceled),
      );
      lifecycle(toForeground);
      await settle();
      expect(calls, hasLength(1));
    });

    test(
      'calls with a different persist value do not share a prompt',
      () async {
        final sticky = service.authenticate(
          'r',
          persistAcrossBackgrounding: true,
        );
        final plain = service.authenticate('r');
        await settle();
        expect(calls, hasLength(1));
        calls.single.reply.complete(encode(pigeon.AuthStatus.success));
        await sticky;
        await settle();
        expect(calls, hasLength(2));
        calls.last.reply.complete(encode(pigeon.AuthStatus.success));
        expect((await plain).isSuccess, isTrue);
      },
    );
  });
}
