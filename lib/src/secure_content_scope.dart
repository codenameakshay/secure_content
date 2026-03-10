import 'dart:async';

import 'package:flutter/material.dart';

import 'secure_content_event.dart';
import 'secure_content_service.dart';

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
  });

  final Widget child;
  final bool enabled;
  final WidgetBuilder? overlayBuilder;
  final ValueChanged<SecureContentEvent>? onEvent;
  final bool debugShowOverlay;
  final bool protectInAppSwitcher;
  final Color appSwitcherColor;

  @override
  State<SecureContentScope> createState() => _SecureContentScopeState();
}

class _SecureContentScopeState extends State<SecureContentScope> {
  final Object _sourceKey = Object();
  final SecureContentService _service = SecureContentService.instance;

  StreamSubscription<SecureContentEvent>? _eventsSubscription;
  bool _isCaptured = false;

  @override
  void initState() {
    super.initState();
    _bindSource();

    _eventsSubscription = _service.events.listen((event) {
      widget.onEvent?.call(event);

      if (event.type == SecureContentEventType.recordingStarted) {
        if (mounted) {
          setState(() {
            _isCaptured = true;
          });
        }
      }

      if (event.type == SecureContentEventType.recordingStopped) {
        if (mounted) {
          setState(() {
            _isCaptured = false;
          });
        }
      }
    });

    _primeCaptureState();
  }

  @override
  void didUpdateWidget(covariant SecureContentScope oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.enabled != widget.enabled ||
        oldWidget.protectInAppSwitcher != widget.protectInAppSwitcher ||
        oldWidget.appSwitcherColor != widget.appSwitcherColor) {
      _bindSource();
    }
  }

  @override
  void dispose() {
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

  @override
  Widget build(BuildContext context) {
    final showOverlay =
        widget.debugShowOverlay || (widget.enabled && _isCaptured);

    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        if (showOverlay)
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
      ],
    );
  }
}
