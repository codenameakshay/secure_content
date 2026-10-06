import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'secure_content_event.dart';
import 'secure_content_policy.dart';
import 'secure_content_platform.dart';
import 'secure_content_service.dart';

int _nextScopeSemanticsIdentifier = 0;

/// Builder for a custom lock screen overlay.
///
/// The returned widget **must** be fully opaque and fill the available space,
/// otherwise the protected child content may be visible underneath.
typedef LockScreenBuilder =
    Widget Function(BuildContext context, VoidCallback onUnlock);

/// Builder for a custom hard-block screen overlay.
///
/// The returned widget **must** be fully opaque and fill the available space,
/// otherwise the protected child content may be visible underneath.
typedef HardBlockBuilder = Widget Function(BuildContext context);

class SecureContentScope extends StatefulWidget {
  const SecureContentScope({
    super.key,
    required this.child,
    required this.enabled,
    this.overlayBuilder,
    this.onEvent,
    this.debugShowOverlay = false,
    this.protectInAppSwitcher = true,
    this.appSwitcherColor = Colors.black,
    this.appSwitcherImageName,
    this.policy = const SecureContentPolicy(),
    this.lockScreenBuilder,
    this.hardBlockBuilder,
  });

  final Widget child;
  final bool enabled;

  /// Custom screen-capture cover builder. The returned widget must be fully
  /// opaque and fill the available space.
  final WidgetBuilder? overlayBuilder;
  final ValueChanged<SecureContentEvent>? onEvent;
  final bool debugShowOverlay;
  final bool protectInAppSwitcher;
  final Color appSwitcherColor;

  /// Optional image in the host app's native asset catalog (iOS) to center on
  /// the app-switcher / privacy overlay, rendered as a white-tinted template so
  /// the multitasking snapshot shows branding instead of a flat fill.
  final String? appSwitcherImageName;
  final SecureContentPolicy policy;

  /// Custom lock screen overlay builder.
  ///
  /// When non-null, replaces the default lock screen. The returned widget
  /// **must** be fully opaque and fill the available space.
  final LockScreenBuilder? lockScreenBuilder;

  /// Custom hard-block screen overlay builder.
  ///
  /// When non-null, replaces the default hard-block screen. The returned
  /// widget **must** be fully opaque and fill the available space.
  final HardBlockBuilder? hardBlockBuilder;

  @override
  State<SecureContentScope> createState() => _SecureContentScopeState();
}

class _SecureContentScopeState extends State<SecureContentScope>
    with WidgetsBindingObserver {
  final Object _sourceKey = Object();
  final SecureContentService _service = SecureContentService.instance;
  final SecureContentPlatform _platform = SecureContentPlatform.instance;
  final FocusScopeNode _childFocusScope = FocusScopeNode(
    debugLabel: 'SecureContentScope protected child',
  );
  late final String _childSemanticsIdentifier;
  TextEditingController? _focusedTextController;

  StreamSubscription<SecureContentEvent>? _eventsSubscription;
  Timer? _idleTimer;
  DateTime _lastUserInteractionAt = DateTime.now();
  final Stopwatch _idleStopwatch = Stopwatch()..start();

  bool _isCaptured = false;
  bool _captureStatePrimed = false;
  int _captureStateRequestGeneration = 0;
  int _protectionConfigGeneration = 0;
  bool _nativeProtectionReady = false;
  bool _isLocked = false;
  bool _isAuthenticating = false;
  bool _isBiometricLocked = false;
  bool _needsBiometricAuth = false;
  bool _biometricRequestCrossedBackground = false;
  bool _biometricUnavailable = false;
  int _biometricRequestGeneration = 0;
  bool _integrityRiskDetected = false;
  bool _appSwitcherProtected = false;
  bool _isAppActive = true;
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    _appLifecycleState =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    _childSemanticsIdentifier =
        'secure-content-scope-${_nextScopeSemanticsIdentifier++}';
    _isAppActive = _appLifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_handleHardwareKeyEvent);
    FocusManager.instance.addListener(_handlePrimaryFocusChanged);
    SemanticsBinding.instance.addSemanticsActionListener(
      _handleSemanticsActionEvent,
    );
    _nativeProtectionReady = !widget.enabled || !_platform.isSupportedPlatform;
    _captureStatePrimed = !widget.enabled || !_platform.isSupportedPlatform;
    _bindSource();

    _eventsSubscription = _service.events.listen(_handleEvent);

    _primeCaptureState();

    _needsBiometricAuth =
        widget.policy.requireBiometricOnResume && widget.enabled;
    if (_needsBiometricAuth) {
      // Set the initial lock synchronously, before the first build and
      // before any async integrity/biometric work starts, so protected
      // content is never rendered even for a single frame (AUTH-02).
      _isLocked = true;
      _isBiometricLocked = true;
      if (_appLifecycleState == AppLifecycleState.resumed) {
        _isAuthenticating = true;
        final generation = ++_biometricRequestGeneration;
        unawaited(
          _awaitBiometricResult(widget.policy.biometricReason, generation),
        );
      }
    }

    _maybeCheckIntegrity();
    _restartIdleTimer();
  }

  @override
  void didUpdateWidget(covariant SecureContentScope oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.enabled != widget.enabled ||
        oldWidget.protectInAppSwitcher != widget.protectInAppSwitcher ||
        oldWidget.appSwitcherColor != widget.appSwitcherColor ||
        oldWidget.appSwitcherImageName != widget.appSwitcherImageName) {
      _bindSource();
    }

    // LIFE-01: centralize policy application here so every policy field
    // that can change at runtime actually takes effect immediately, instead
    // of only inactivityTimeout doing so.
    final enabledChanged = oldWidget.enabled != widget.enabled;

    if (enabledChanged && !widget.enabled) {
      // STATE-01: disabling protection must hard-block every side effect
      // right away, not just stop new ones from starting.
      _biometricRequestGeneration += 1;
      _isAuthenticating = false;
      _isBiometricLocked = false;
      _needsBiometricAuth = false;
      _captureStateRequestGeneration += 1;
      _captureStatePrimed = true;
      _nativeProtectionReady = true;
      _updateState(() {
        _isLocked = false;
        _integrityRiskDetected = false;
        _biometricUnavailable = false;
      });
    }

    if (enabledChanged && widget.enabled) {
      final supported = _platform.isSupportedPlatform;
      _nativeProtectionReady = !supported;
      _captureStatePrimed = !supported;
      if (supported) {
        _primeCaptureState();
      }
    }

    final biometricPolicyDisabled =
        oldWidget.policy.requireBiometricOnResume &&
        !widget.policy.requireBiometricOnResume;
    if (biometricPolicyDisabled) {
      // A policy that no longer requires biometrics must not leave a stale
      // pending request behind. Incrementing the generation makes any late
      // result from that request inert.
      _biometricRequestGeneration += 1;
      _needsBiometricAuth = false;
      _isAuthenticating = false;
      if (_isBiometricLocked) {
        _unlock();
      }
    }

    final biometricJustRequired =
        widget.enabled &&
        widget.policy.requireBiometricOnResume &&
        (!oldWidget.enabled || !oldWidget.policy.requireBiometricOnResume);
    if (biometricJustRequired) {
      _needsBiometricAuth = true;
      _isLocked = true;
      _isBiometricLocked = true;
      if (_appLifecycleState == AppLifecycleState.resumed) {
        _lockAndRequestBiometric();
      }
    }

    final integrityChecksJustDisabled =
        oldWidget.policy.enableIntegrityChecks &&
        !widget.policy.enableIntegrityChecks;
    if (integrityChecksJustDisabled && _integrityRiskDetected) {
      _updateState(() {
        _integrityRiskDetected = false;
      });
    }

    final integrityChecksJustEnabled =
        widget.policy.enableIntegrityChecks &&
        (enabledChanged || !oldWidget.policy.enableIntegrityChecks);
    if (integrityChecksJustEnabled) {
      _maybeCheckIntegrity();
    }

    if (enabledChanged ||
        oldWidget.policy.inactivityTimeout != widget.policy.inactivityTimeout) {
      _restartIdleTimer(resetElapsed: enabledChanged);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;
    // LIFE-02: this feeds build()'s riskyState derivation, so it must go
    // through setState (when mounted) instead of a raw field assignment,
    // or the watermark/risk UI can go stale until some unrelated rebuild.
    _updateState(() {
      _isAppActive = state == AppLifecycleState.resumed;
    });

    if (state == AppLifecycleState.resumed) {
      if (widget.enabled && _platform.isSupportedPlatform) {
        if (!_nativeProtectionReady) {
          unawaited(_bindSource());
        }
        if (!_captureStatePrimed) {
          unawaited(_primeCaptureState());
        }
      }
      if (widget.policy.requireBiometricOnResume &&
          widget.enabled &&
          _needsBiometricAuth) {
        _lockAndRequestBiometric();
      }
      _maybeCheckIntegrity();
      _restartIdleTimer(resetElapsed: false);
      return;
    }

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _idleTimer?.cancel();
      _idleTimer = null;
      if (_isAuthenticating) {
        _biometricRequestCrossedBackground = true;
      }
    }

    if (widget.policy.requireBiometricOnResume &&
        widget.enabled &&
        (state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden ||
            state == AppLifecycleState.detached)) {
      _needsBiometricAuth = true;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_handleHardwareKeyEvent);
    FocusManager.instance.removeListener(_handlePrimaryFocusChanged);
    _focusedTextController?.removeListener(_handleFocusedTextChanged);
    SemanticsBinding.instance.removeSemanticsActionListener(
      _handleSemanticsActionEvent,
    );
    _idleTimer?.cancel();
    _eventsSubscription?.cancel();
    _captureStateRequestGeneration += 1;
    _protectionConfigGeneration += 1;
    _childFocusScope.dispose();
    unawaited(_removeSource());
    super.dispose();
  }

  Future<void> _removeSource() async {
    try {
      await _service.removeSource(_sourceKey);
    } catch (error, stackTrace) {
      _reportInternalError(
        error,
        stackTrace,
        'while removing native secure-content protection',
      );
    }
  }

  Future<void> _bindSource() async {
    final generation = ++_protectionConfigGeneration;
    try {
      await _service.updateSource(
        key: _sourceKey,
        enabled: widget.enabled,
        protectInAppSwitcher: widget.protectInAppSwitcher,
        appSwitcherColor: widget.appSwitcherColor,
        appSwitcherImageName: widget.appSwitcherImageName,
      );
      if (mounted && generation == _protectionConfigGeneration) {
        _updateState(() {
          _nativeProtectionReady = true;
        });
      }
    } catch (error, stackTrace) {
      _reportInternalError(
        error,
        stackTrace,
        'while configuring native secure-content protection',
      );
    }
  }

  Future<void> _primeCaptureState() async {
    final generation = ++_captureStateRequestGeneration;
    try {
      final captured = await _service.isScreenCaptured();
      if (!mounted || generation != _captureStateRequestGeneration) {
        return;
      }
      _updateState(() {
        _isCaptured = captured;
        _captureStatePrimed = true;
      });
    } catch (error, stackTrace) {
      _reportInternalError(
        error,
        stackTrace,
        'while reading the initial screen-capture state',
      );
    }
  }

  void _maybeCheckIntegrity() {
    if (widget.enabled && widget.policy.enableIntegrityChecks) {
      unawaited(_checkIntegrity());
    }
  }

  Future<void> _checkIntegrity() async {
    try {
      await _service.checkIntegrity();
    } catch (error, stackTrace) {
      _reportInternalError(
        error,
        stackTrace,
        'while checking device integrity',
      );
    }
  }

  void _handleEvent(SecureContentEvent event) {
    // A throwing consumer callback must not prevent this scope from
    // processing the event internally (EVENT-01): report the error through
    // the normal Flutter error pipeline instead of letting it propagate out
    // of this stream listener and skip the switch below.
    try {
      widget.onEvent?.call(event);
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'secure_content',
          context: ErrorDescription(
            'while handling a SecureContentScope onEvent callback',
          ),
        ),
      );
    }

    switch (event.type) {
      case SecureContentEventType.recordingStarted:
        _captureStateRequestGeneration += 1;
        _updateState(() {
          _isCaptured = true;
          _captureStatePrimed = true;
        });
        break;
      case SecureContentEventType.recordingStopped:
        _captureStateRequestGeneration += 1;
        _updateState(() {
          _isCaptured = false;
          _captureStatePrimed = true;
        });
        break;
      case SecureContentEventType.appSwitcherProtected:
        _updateState(() {
          _appSwitcherProtected = true;
        });
        break;
      case SecureContentEventType.appSwitcherUnprotected:
        _updateState(() {
          _appSwitcherProtected = false;
        });
        break;
      case SecureContentEventType.integrityRiskDetected:
        if (!widget.enabled || !widget.policy.enableIntegrityChecks) {
          break;
        }
        _updateState(() {
          _integrityRiskDetected = true;
        });
        break;
      case SecureContentEventType.integritySafe:
        if (!widget.enabled || !widget.policy.enableIntegrityChecks) {
          break;
        }
        _updateState(() {
          _integrityRiskDetected = false;
        });
        break;
      case SecureContentEventType.biometricAuthSucceeded:
      case SecureContentEventType.biometricAuthFailed:
      case SecureContentEventType.biometricUnavailable:
        // Biometric outcomes are correlated per-request through the Future
        // returned by SecureContentService.requestBiometricAuth (see
        // _awaitBiometricResult). This raw broadcast event may belong to a
        // request some other SecureContentScope made, so it must not mutate
        // this scope's lock state.
        break;
      case SecureContentEventType.platformReady:
      case SecureContentEventType.screenshotCaptured:
      case SecureContentEventType.clipboardSet:
      case SecureContentEventType.clipboardCleared:
      case SecureContentEventType.idleLockActivated:
      case SecureContentEventType.idleLockReleased:
      case SecureContentEventType.unknown:
        break;
    }
  }

  void _updateState(VoidCallback updater) {
    if (!mounted) {
      return;
    }
    setState(() {
      updater();
      if (_blocksProtectedContent) {
        _childFocusScope.unfocus();
      }
    });
  }

  void _restartIdleTimer({bool resetElapsed = true}) {
    _idleTimer?.cancel();
    _idleTimer = null;
    if (resetElapsed) {
      _lastUserInteractionAt = DateTime.now();
      _idleStopwatch
        ..reset()
        ..start();
    }
    final timeout = widget.policy.inactivityTimeout;
    if (timeout == null || !widget.enabled) {
      return;
    }

    final elapsed = DateTime.now().difference(_lastUserInteractionAt);
    final nonNegativeElapsed = elapsed.isNegative ? Duration.zero : elapsed;
    final elapsedIdle = nonNegativeElapsed > _idleStopwatch.elapsed
        ? nonNegativeElapsed
        : _idleStopwatch.elapsed;
    final remaining = timeout - elapsedIdle;
    if (remaining <= Duration.zero) {
      _activateIdleLock();
      return;
    }
    if (_appLifecycleState == AppLifecycleState.paused ||
        _appLifecycleState == AppLifecycleState.hidden ||
        _appLifecycleState == AppLifecycleState.detached) {
      return;
    }
    _idleTimer = Timer(remaining, _activateIdleLock);
  }

  void _activateIdleLock() {
    if (!widget.enabled) {
      return;
    }
    _updateState(() {
      _isLocked = true;
    });
    _service.emitLocalEvent(SecureContentEventType.idleLockActivated);
  }

  void _unlock() {
    _updateState(() {
      _isLocked = false;
      _isBiometricLocked = false;
    });
    _service.emitLocalEvent(SecureContentEventType.idleLockReleased);
    _restartIdleTimer();
  }

  void _lockAndRequestBiometric() {
    if (_isAuthenticating || !widget.enabled) {
      return;
    }
    _isAuthenticating = true;
    _biometricRequestCrossedBackground = false;
    _isBiometricLocked = true;
    final generation = ++_biometricRequestGeneration;
    _activateIdleLock();
    unawaited(_awaitBiometricResult(widget.policy.biometricReason, generation));
  }

  /// Awaits the outcome of this scope's own biometric request and updates
  /// only this scope's state from it, instead of reacting to the shared
  /// broadcast event stream (which every SecureContentScope listens to and
  /// which may carry another scope's request outcome).
  Future<void> _awaitBiometricResult(String reason, int generation) async {
    late final SecureContentEventType outcome;
    try {
      outcome = await _service.requestBiometricAuth(reason);
    } catch (error, stackTrace) {
      _reportInternalError(
        error,
        stackTrace,
        'while requesting biometric authentication',
      );
      if (!mounted || generation != _biometricRequestGeneration) {
        return;
      }
      _isAuthenticating = false;
      _updateState(() {
        _biometricUnavailable = true;
      });
      return;
    }
    if (!mounted || generation != _biometricRequestGeneration) {
      return;
    }
    _isAuthenticating = false;
    if (_biometricRequestCrossedBackground) {
      _biometricRequestCrossedBackground = false;
      _needsBiometricAuth = true;
      if (_appLifecycleState == AppLifecycleState.resumed &&
          widget.enabled &&
          widget.policy.requireBiometricOnResume) {
        _lockAndRequestBiometric();
      }
      return;
    }
    switch (outcome) {
      case SecureContentEventType.biometricAuthSucceeded:
        _needsBiometricAuth = false;
        _updateState(() {
          _biometricUnavailable = false;
        });
        if (_appLifecycleState == AppLifecycleState.paused ||
            _appLifecycleState == AppLifecycleState.hidden ||
            _appLifecycleState == AppLifecycleState.detached) {
          _needsBiometricAuth = true;
        } else {
          _unlock();
        }
        break;
      case SecureContentEventType.biometricUnavailable:
        // AUTH-03: fail closed. Stay locked and surface an explicit
        // unavailable state so the UI can explain why, instead of leaving
        // the user stuck on a generic "unlock with biometrics" prompt that
        // will never succeed on this device.
        _updateState(() {
          _biometricUnavailable = true;
        });
        break;
      default:
        _updateState(() {
          _biometricUnavailable = false;
        });
        break;
    }
  }

  void _onUserInteraction() {
    if (!widget.enabled) {
      return;
    }
    _restartIdleTimer();
  }

  bool _handleHardwareKeyEvent(KeyEvent event) {
    if (!_blocksProtectedContent && _childFocusScope.hasFocus) {
      _onUserInteraction();
    }
    return false;
  }

  void _handlePrimaryFocusChanged() {
    TextEditingController? controller;
    FocusManager.instance.primaryFocus?.context?.visitAncestorElements((
      element,
    ) {
      final widget = element.widget;
      if (widget is EditableText) {
        controller = widget.controller;
        return false;
      }
      return true;
    });

    if (identical(controller, _focusedTextController)) {
      return;
    }
    _focusedTextController?.removeListener(_handleFocusedTextChanged);
    _focusedTextController = controller;
    _focusedTextController?.addListener(_handleFocusedTextChanged);
  }

  void _handleFocusedTextChanged() {
    if (!_blocksProtectedContent && _childFocusScope.hasFocus) {
      _onUserInteraction();
    }
  }

  void _handleSemanticsActionEvent(SemanticsActionEvent event) {
    if (_isChildSemanticsAction(event)) {
      _onUserInteraction();
    }
  }

  bool _isChildSemanticsAction(SemanticsActionEvent event) {
    SemanticsNode? root;
    for (final renderView in RendererBinding.instance.renderViews) {
      if (renderView.flutterView.viewId == event.viewId) {
        root = renderView.owner?.semanticsOwner?.rootSemanticsNode;
        break;
      }
    }
    if (root == null) {
      return false;
    }

    SemanticsNode? findActionNode(SemanticsNode node) {
      if (node.id == event.nodeId) {
        return node;
      }
      SemanticsNode? match;
      node.visitChildren((child) {
        match = findActionNode(child);
        return match == null;
      });
      return match;
    }

    var actionNode = findActionNode(root);
    while (actionNode != null) {
      if (actionNode.getSemanticsData().identifier ==
          _childSemanticsIdentifier) {
        return true;
      }
      actionNode = actionNode.parent;
    }
    return false;
  }

  bool get _blocksProtectedContent =>
      widget.enabled &&
      (!_nativeProtectionReady ||
          !_captureStatePrimed ||
          _isCaptured ||
          _isLocked ||
          (widget.policy.hardBlockOnIntegrityRisk && _integrityRiskDetected));

  void _reportInternalError(
    Object error,
    StackTrace stackTrace,
    String context,
  ) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'secure_content',
        context: ErrorDescription(context),
      ),
    );
  }

  void _handleUnlock() {
    if (widget.policy.requireBiometricOnResume) {
      _lockAndRequestBiometric();
    } else {
      _unlock();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isHardBlocked =
        widget.enabled &&
        widget.policy.hardBlockOnIntegrityRisk &&
        _integrityRiskDetected;

    final showCaptureOverlay =
        widget.debugShowOverlay || (widget.enabled && _isCaptured);

    final riskyState =
        widget.enabled &&
        (_isCaptured ||
            _isLocked ||
            _integrityRiskDetected ||
            _appSwitcherProtected ||
            !_isAppActive);
    final protectionPending =
        widget.enabled && (!_nativeProtectionReady || !_captureStatePrimed);
    final blocksProtectedContent = _blocksProtectedContent;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _onUserInteraction(),
      onPointerMove: (_) => _onUserInteraction(),
      onPointerSignal: (_) => _onUserInteraction(),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          FocusScope(
            node: _childFocusScope,
            canRequestFocus: !blocksProtectedContent,
            descendantsAreFocusable: !blocksProtectedContent,
            child: IgnorePointer(
              ignoring: blocksProtectedContent,
              child: ExcludeSemantics(
                excluding: blocksProtectedContent,
                child: Semantics(
                  container: true,
                  identifier: _childSemanticsIdentifier,
                  child: widget.child,
                ),
              ),
            ),
          ),
          if (protectionPending)
            const Positioned.fill(child: ColoredBox(color: Colors.black)),
          if (showCaptureOverlay)
            Positioned.fill(
              child: IgnorePointer(
                child:
                    widget.overlayBuilder?.call(context) ??
                    const ColoredBox(color: Colors.black),
              ),
            ),
          if (widget.policy.enableRiskWatermark && riskyState)
            Positioned.fill(
              child: IgnorePointer(
                child: _RiskWatermarkLayer(
                  text: widget.policy.watermarkText,
                  textStyle: widget.policy.watermarkStyle,
                ),
              ),
            ),
          if (_isLocked && !isHardBlocked)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: widget.lockScreenBuilder != null
                    ? widget.lockScreenBuilder!(context, _handleUnlock)
                    : _buildDefaultLockScreen(),
              ),
            ),
          if (isHardBlocked)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: widget.hardBlockBuilder != null
                    ? widget.hardBlockBuilder!(context)
                    : _buildDefaultHardBlockScreen(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDefaultLockScreen() {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _biometricUnavailable
                  ? Icons.fingerprint_outlined
                  : Icons.lock_outline,
              color: Colors.white,
              size: 36,
            ),
            const SizedBox(height: 12),
            Text(
              _biometricUnavailable
                  ? 'Biometric authentication unavailable'
                  : 'Session locked',
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
            if (_biometricUnavailable) ...[
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'This device cannot verify biometrics right now. '
                  'The screen stays locked until it can.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ],
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _handleUnlock,
              child: Text(
                _biometricUnavailable
                    ? 'Try again'
                    : widget.policy.requireBiometricOnResume
                    ? 'Unlock with biometrics'
                    : 'Unlock',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultHardBlockScreen() {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.warning_amber_rounded, color: Colors.white, size: 40),
              SizedBox(height: 12),
              Text(
                'Access blocked for security reasons.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RiskWatermarkLayer extends StatelessWidget {
  const _RiskWatermarkLayer({required this.text, this.textStyle});

  final String text;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RiskWatermarkPainter(text: text, textStyle: textStyle),
    );
  }
}

class _RiskWatermarkPainter extends CustomPainter {
  const _RiskWatermarkPainter({required this.text, this.textStyle});

  final String text;
  final TextStyle? textStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style:
            textStyle ??
            const TextStyle(
              color: Color(0x66FFFFFF),
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final spacingX = textPainter.width + 52;
    final spacingY = textPainter.height + 42;

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-math.pi / 6);
    canvas.translate(-size.width / 2, -size.height / 2);

    for (double y = -size.height; y < size.height * 2; y += spacingY) {
      for (double x = -size.width; x < size.width * 2; x += spacingX) {
        textPainter.paint(canvas, Offset(x, y));
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RiskWatermarkPainter oldDelegate) {
    return oldDelegate.text != text || oldDelegate.textStyle != textStyle;
  }
}
