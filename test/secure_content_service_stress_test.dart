import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_content/secure_content.dart';
import 'package:secure_content/src/secure_content_platform.dart';
import 'package:secure_content/src/pigeon/secure_content_api.g.dart' as pigeon;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channelPrefix =
      'dev.flutter.pigeon.secure_content.SecureContentHostApi';
  final codec = pigeon.SecureContentHostApi.pigeonChannelCodec;
  final responses = <_PendingResponse>[];
  var activeNativeCalls = 0;
  var maximumNativeCalls = 0;
  var nativeCallCount = 0;
  var injectedFailureCount = 0;
  var successfulCallsAfterFailure = 0;
  var failureHasOccurred = false;
  var appliedNativeConfig = _Config(
    enabled: false,
    protectInAppSwitcher: true,
    color: Colors.black.toARGB32(),
  );

  setUp(() {
    SecureContentPlatform.debugIsSupportedPlatformOverride = true;
    addTearDown(
      () => SecureContentPlatform.debugIsSupportedPlatformOverride = null,
    );
  });

  setUpAll(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMessageHandler('$channelPrefix.configureProtection', (
      ByteData? message,
    ) async {
      activeNativeCalls += 1;
      maximumNativeCalls = math.max(maximumNativeCalls, activeNativeCalls);
      nativeCallCount += 1;
      final request = codec.decodeMessage(message) as List<Object?>;
      final raw = request.single as pigeon.ProtectionConfig;
      final config = _Config(
        enabled: raw.enabled,
        protectInAppSwitcher: raw.protectInAppSwitcher,
        color: raw.appSwitcherColor,
      );
      final response = _PendingResponse(
        config: config,
        fail: nativeCallCount % 29 == 0,
      );
      responses.add(response);
      try {
        final failed = await response.release.future;
        if (failed) {
          injectedFailureCount += 1;
          failureHasOccurred = true;
          return codec.encodeMessage(<Object?>[
            'injected-config-failure',
            'Failure injected by bounded service stress test',
            null,
          ]);
        }
        if (failureHasOccurred) {
          successfulCallsAfterFailure += 1;
        }
        appliedNativeConfig = config;
        return codec.encodeMessage(<Object?>[null]);
      } finally {
        activeNativeCalls -= 1;
      }
    });
  });

  tearDown(() {
    responses.clear();
    activeNativeCalls = 0;
    maximumNativeCalls = 0;
    nativeCallCount = 0;
    injectedFailureCount = 0;
    successfulCallsAfterFailure = 0;
    failureHasOccurred = false;
    appliedNativeConfig = _Config(
      enabled: false,
      protectInAppSwitcher: true,
      color: Colors.black.toARGB32(),
    );
  });

  tearDownAll(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMessageHandler('$channelPrefix.configureProtection', null);
  });

  test('seeded controller bursts serialize, recover, and converge', () async {
    const seeds = <int>[0x51A7, 0xC0FFEE, 0xBAD5EED, 0x7E57];
    const actionsPerSeed = 512;
    var totalActions = 0;
    var totalLiveOperations = 0;
    var totalReplacements = 0;

    for (final seed in seeds) {
      final random = math.Random(seed);
      final controllers = List<SecureContentController>.generate(
        16,
        (_) => SecureContentController(),
      );
      final models = List<_SourceModel>.generate(
        controllers.length,
        (_) => _SourceModel(),
      );
      final futures = <Future<void>>[];
      var completedCalls = 0;
      var modelSequence = 0;

      for (var action = 0; action < actionsPerSeed; action++) {
        final index = random.nextInt(controllers.length);
        if (models[index].disposed) {
          controllers[index] = SecureContentController();
          models[index] = _SourceModel();
          totalReplacements++;
        }
        final controller = controllers[index];
        final model = models[index];
        final operation = random.nextInt(100);

        if (index != 0 && !model.disposed && operation < 8) {
          model.disposed = true;
          model.enabled = false;
          model.sequence = ++modelSequence;
          model.present = false;
          futures.add(controller.dispose());
        } else if (operation < 38) {
          final protect = random.nextBool();
          final color = random.nextInt(0x1000000) | 0xff000000;
          _updateModel(
            model,
            enabled: true,
            protect: protect,
            color: color,
            sequence: ++modelSequence,
          );
          futures.add(
            controller.enable(
              protectInAppSwitcher: protect,
              appSwitcherColor: Color(color),
            ),
          );
        } else if (operation < 61) {
          _updateModel(
            model,
            enabled: false,
            protect: true,
            color: Colors.black.toARGB32(),
            sequence: ++modelSequence,
          );
          futures.add(controller.disable());
        } else {
          final enabled = random.nextBool();
          final protect = random.nextBool();
          final color = random.nextInt(0x1000000) | 0xff000000;
          _updateModel(
            model,
            enabled: enabled,
            protect: protect,
            color: color,
            sequence: ++modelSequence,
          );
          futures.add(
            controller.setProtection(
              enabled,
              protectInAppSwitcher: protect,
              appSwitcherColor: Color(color),
            ),
          );
        }
        if (!model.disposed) totalLiveOperations++;

        // Keep the future observed as it runs: injected failures belong to
        // their caller, while later queue entries must remain free to finish.
        final original = futures.removeLast();
        futures.add(
          original.then<void>(
            (_) => completedCalls++,
            onError: (Object _) => completedCalls++,
          ),
        );
        totalActions++;

        // Let the first request in each burst become pending, then hold its
        // native response while subsequent source changes pile up behind it.
        if (action % 32 == 31) {
          await _releaseOnePending(responses);
        }
      }

      // Reapply the model's current state through a surviving controller.
      // This provides a fresh synchronization opportunity after any failure
      // on the final queued request, and also checks disposed controllers
      // cannot bring their old source back.
      final anchor = models.first;
      final anchorColor = anchor.color;
      _updateModel(
        anchor,
        enabled: anchor.enabled,
        protect: anchor.protect,
        color: anchorColor,
        sequence: ++modelSequence,
      );
      futures.add(
        controllers.first
            .setProtection(
              anchor.enabled,
              protectInAppSwitcher: anchor.protect,
              appSwitcherColor: Color(anchorColor),
            )
            .then<void>(
              (_) => completedCalls++,
              onError: (Object _) => completedCalls++,
            ),
      );
      totalActions++;

      while (completedCalls < futures.length) {
        if (!_releaseNextPending(responses)) {
          await Future<void>.delayed(Duration.zero);
        }
      }
      await Future.wait(futures);

      final expected = _expectedConfig(models);
      expect(
        appliedNativeConfig,
        expected,
        reason: 'seed $seed did not converge after $actionsPerSeed actions',
      );
      expect(
        maximumNativeCalls,
        1,
        reason: 'seed $seed had overlapping native configure calls',
      );

      // A controller disposed during the sequence must remain inert, even
      // when called after the queue drains.
      for (var index = 1; index < controllers.length; index++) {
        if (models[index].disposed) {
          final before = nativeCallCount;
          await controllers[index].enable(
            appSwitcherColor: const Color(0xFF123456),
          );
          expect(controllers[index].enabled, isFalse);
          expect(nativeCallCount, before);
        }
      }

      final cleanup = <Future<void>>[];
      for (final controller in controllers) {
        if (!controller.isDisposed) {
          cleanup.add(controller.dispose());
        }
      }
      var cleanupCompleted = 0;
      final observedCleanup = cleanup
          .map(
            (future) => future.then<void>(
              (_) => cleanupCompleted++,
              onError: (Object _) => cleanupCompleted++,
            ),
          )
          .toList();
      while (cleanupCompleted < cleanup.length) {
        if (!_releaseNextPending(responses)) {
          await Future<void>.delayed(Duration.zero);
        }
      }
      await Future.wait(observedCleanup);
      await Future<void>.delayed(Duration.zero);
      expect(activeNativeCalls, 0);
      responses.clear();
    }

    expect(totalActions, seeds.length * (actionsPerSeed + 1));
    expect(
      totalLiveOperations,
      greaterThan(seeds.length * actionsPerSeed * 0.8),
    );
    expect(totalReplacements, greaterThan(0));
    expect(nativeCallCount, greaterThan(0));
    expect(injectedFailureCount, greaterThan(0));
    expect(successfulCallsAfterFailure, greaterThan(0));
  });

  test('model orders sources by their shared update sequence', () {
    final sourceA = _SourceModel();
    final sourceB = _SourceModel();
    _updateModel(
      sourceA,
      enabled: true,
      protect: true,
      color: 0xff111111,
      sequence: 1,
    );
    _updateModel(
      sourceA,
      enabled: true,
      protect: true,
      color: 0xff222222,
      sequence: 2,
    );
    _updateModel(
      sourceB,
      enabled: true,
      protect: true,
      color: 0xff333333,
      sequence: 3,
    );

    expect(_expectedConfig(<_SourceModel>[sourceA, sourceB]).color, 0xff333333);
  });
}

void _updateModel(
  _SourceModel model, {
  required bool enabled,
  required bool protect,
  required int color,
  required int sequence,
}) {
  if (model.disposed) {
    return;
  }
  model.present = true;
  model.enabled = enabled;
  model.protect = protect;
  model.color = color;
  model.sequence = sequence;
}

_Config _expectedConfig(List<_SourceModel> models) {
  final active = models.where((model) => model.present && model.enabled);
  final switcher = active.where((model) => model.protect).toList()
    ..sort((a, b) => a.sequence.compareTo(b.sequence));
  return _Config(
    enabled: active.isNotEmpty,
    protectInAppSwitcher: switcher.isNotEmpty,
    color: switcher.isEmpty ? Colors.black.toARGB32() : switcher.last.color,
  );
}

Future<void> _releaseOnePending(List<_PendingResponse> responses) async {
  if (!_releaseNextPending(responses)) {
    await Future<void>.delayed(Duration.zero);
    _releaseNextPending(responses);
  }
}

bool _releaseNextPending(List<_PendingResponse> responses) {
  for (final response in responses) {
    if (!response.release.isCompleted) {
      response.release.complete(response.fail);
      return true;
    }
  }
  return false;
}

class _SourceModel {
  bool present = false;
  bool enabled = false;
  bool protect = true;
  int color = Colors.black.toARGB32();
  int sequence = 0;
  bool disposed = false;
}

class _Config {
  const _Config({
    required this.enabled,
    required this.protectInAppSwitcher,
    required this.color,
  });

  final bool enabled;
  final bool protectInAppSwitcher;
  final int color;

  @override
  bool operator ==(Object other) =>
      other is _Config &&
      other.enabled == enabled &&
      other.protectInAppSwitcher == protectInAppSwitcher &&
      other.color == color;

  @override
  int get hashCode => Object.hash(enabled, protectInAppSwitcher, color);

  @override
  String toString() =>
      'enabled=$enabled switcher=$protectInAppSwitcher color=0x${color.toRadixString(16)}';
}

class _PendingResponse {
  _PendingResponse({required this.config, required this.fail});

  final _Config config;
  final bool fail;
  final Completer<bool> release = Completer<bool>();
}
