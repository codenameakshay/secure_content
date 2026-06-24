import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'secure_content_event.dart';
import 'secure_content_policy.dart';
import 'secure_content_service.dart';

typedef LockScreenBuilder = Widget Function(
  BuildContext context,
  VoidCallback onUnlock,
);

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
    this.policy = const SecureContentPolicy(),
    this.lockScreenBuilder,
    this.hardBlockBuilder,
  });

  final Widget child;
  final bool enabled;
  final WidgetBuilder? overlayBuilder;
  final ValueChanged<SecureContentEvent>? onEvent;
  final bool debugShowOverlay;
  final bool protectInAppSwitcher;
  final Color appSwitcherColor;
  final SecureContentPolicy policy;
  final LockScreenBuilder? lockScreenBuilder;
  final HardBlockBuilder? hardBlockBuilder;

  @override
  State<SecureContentScope> createState() => _SecureContentScopeState();
}

class _SecureContentScopeState extends State<SecureContentScope>
    with WidgetsBindingObserver {
  final Object _sourceKey = Object();
  final SecureContentService _service = SecureContentService.instance;

  StreamSubscription<SecureContentEvent>? _eventsSubscription;
  Timer? _idleTimer;

  bool _isCaptured = false;
  bool _isLocked = false;
  bool _isAuthenticating = false;
  bool _needsBiometricAuth = false;
  bool _integrityRiskDetected = false;
  bool _appSwitcherProtected = false;
  bool _isAppActive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bindSource();

    _eventsSubscription = _service.events.listen(_handleEvent);

    _primeCaptureState();
    _needsBiometricAuth =
        widget.policy.requireBiometricOnResume && widget.enabled;
    _primePolicy();
    _restartIdleTimer();
  }

  @override
  void didUpdateWidget(covariant SecureContentScope oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.enabled != widget.enabled ||
        oldWidget.protectInAppSwitcher != widget.protectInAppSwitcher ||
        oldWidget.appSwitcherColor != widget.appSwitcherColor) {
      _bindSource();
    }

    if (oldWidget.policy.inactivityTimeout != widget.policy.inactivityTimeout) {
      _restartIdleTimer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isAppActive = state == AppLifecycleState.resumed;

    if (state == AppLifecycleState.resumed) {
      if (widget.policy.requireBiometricOnResume &&
          widget.enabled &&
          _needsBiometricAuth) {
        _lockAndRequestBiometric();
      }
      if (widget.policy.enableIntegrityChecks) {
        unawaited(_service.checkIntegrity());
      }
      _restartIdleTimer();
      return;
    }

    if (widget.policy.requireBiometricOnResume &&
        widget.enabled &&
        !_isAuthenticating) {
      _needsBiometricAuth = true;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _idleTimer?.cancel();
    _eventsSubscription?.cancel();
    unawaited(_service.removeSource(_sourceKey));
    super.dispose();
  }

  Future<void> _bindSource() {
    return _service.updateSource(
      key: _sourceKey,
      enabled: widget.enabled,
      protectInAppSwitcher: widget.protectInAppSwitcher,
      appSwitcherColor: widget.appSwitcherColor,
    );
  }

  Future<void> _primeCaptureState() async {
    final captured = await _service.isScreenCaptured();
    if (!mounted) {
      return;
    }
    setState(() {
      _isCaptured = captured;
    });
  }

  Future<void> _primePolicy() async {
    if (widget.policy.enableIntegrityChecks) {
      await _service.checkIntegrity();
    }
    if (_needsBiometricAuth) {
      _lockAndRequestBiometric();
    }
  }

  void _handleEvent(SecureContentEvent event) {
    widget.onEvent?.call(event);

    switch (event.type) {
      case SecureContentEventType.recordingStarted:
        _updateState(() {
          _isCaptured = true;
        });
      case SecureContentEventType.recordingStopped:
        _updateState(() {
          _isCaptured = false;
        });
      case SecureContentEventType.appSwitcherProtected:
        _updateState(() {
          _appSwitcherProtected = true;
        });
      case SecureContentEventType.appSwitcherUnprotected:
        _updateState(() {
          _appSwitcherProtected = false;
        });
      case SecureContentEventType.integrityRiskDetected:
        _updateState(() {
          _integrityRiskDetected = true;
          if (widget.policy.hardBlockOnIntegrityRisk) {
            _isLocked = true;
          }
        });
      case SecureContentEventType.integritySafe:
        _updateState(() {
          _integrityRiskDetected = false;
          if (widget.policy.hardBlockOnIntegrityRisk) {
            _isLocked = false;
          }
        });
      case SecureContentEventType.biometricAuthSucceeded:
        _isAuthenticating = false;
        _needsBiometricAuth = false;
        _unlock();
      case SecureContentEventType.biometricAuthFailed:
        _isAuthenticating = false;
      case SecureContentEventType.biometricUnavailable:
        _isAuthenticating = false;
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
    setState(updater);
  }

  void _restartIdleTimer() {
    _idleTimer?.cancel();
    final timeout = widget.policy.inactivityTimeout;
    if (timeout == null || !widget.enabled) {
      return;
    }

    _idleTimer = Timer(timeout, _activateIdleLock);
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
    });
    _service.emitLocalEvent(SecureContentEventType.idleLockReleased);
    _restartIdleTimer();
  }

  void _lockAndRequestBiometric() {
    if (_isAuthenticating || !widget.enabled) {
      return;
    }
    _isAuthenticating = true;
    _activateIdleLock();
    unawaited(_service.requestBiometricAuth(widget.policy.biometricReason));
  }

  void _onUserInteraction() {
    if (!widget.enabled) {
      return;
    }
    _restartIdleTimer();
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
        widget.policy.hardBlockOnIntegrityRisk && _integrityRiskDetected;

    final showCaptureOverlay =
        widget.debugShowOverlay || (widget.enabled && _isCaptured);

    final riskyState =
        widget.enabled &&
        (_isCaptured ||
            _isLocked ||
            _integrityRiskDetected ||
            _appSwitcherProtected ||
            !_isAppActive);

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _onUserInteraction(),
      onPointerMove: (_) => _onUserInteraction(),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          if (showCaptureOverlay)
            Positioned.fill(
              child: IgnorePointer(
                child:
                    widget.overlayBuilder?.call(context) ??
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.92),
                      ),
                    ),
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
              child: widget.lockScreenBuilder != null
                  ? widget.lockScreenBuilder!(context, _handleUnlock)
                  : _buildDefaultLockScreen(),
            ),
          if (isHardBlocked)
            Positioned.fill(
              child: widget.hardBlockBuilder != null
                  ? widget.hardBlockBuilder!(context)
                  : _buildDefaultHardBlockScreen(),
            ),
        ],
      ),
    );
  }

  Widget _buildDefaultLockScreen() {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.88),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.lock_outline,
              color: Colors.white,
              size: 36,
            ),
            const SizedBox(height: 12),
            const Text(
              'Session locked',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _handleUnlock,
              child: Text(
                widget.policy.requireBiometricOnResume
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
              Icon(
                Icons.warning_amber_rounded,
                color: Colors.white,
                size: 40,
              ),
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
