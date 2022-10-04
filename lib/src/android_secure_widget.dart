import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_portal/flutter_portal.dart';
import 'package:screen_capture_event/screen_capture_event.dart';

class AndroidSecureWidget extends StatefulWidget {
  const AndroidSecureWidget({
    required this.builder,
    required this.isSecure,
    this.overlayWidgetBuilder,
    this.onScreenshotCaptured,
    this.onScreenRecordingStart,
    this.onScreenRecordingStop,
    this.debug = false,
    Key? key,
  }) : super(key: key);

  /// The builder for child widget to be secured.
  final Widget Function(BuildContext context, VoidCallback onInit, VoidCallback onDispose) builder;

  /// Whether the child widget should be secured (dynamic change for the same widget).
  final bool isSecure;

  /// (Optional) Widget to be shown when the child widget is secured.
  /// If not provided, a default secure widget will be shown in which the whole screen will be blurred.
  final Widget Function(BuildContext context)? overlayWidgetBuilder;

  /// (Optional) Callback when screenshot is captured
  final VoidCallback? onScreenshotCaptured;

  /// (Optional) Callback when screenRecordingStart is detected
  final VoidCallback? onScreenRecordingStart;

  /// (Optional) Callback when screenRecordingStop is detected
  final VoidCallback? onScreenRecordingStop;

  /// (Optional) A bool to show overlay widget, so that debugging is easier. Default is false.
  final bool debug;

  @override
  _AndroidSecureWidgetState createState() => _AndroidSecureWidgetState();
}

class _AndroidSecureWidgetState extends State<AndroidSecureWidget> {
  late ScreenCaptureEvent screenListener;
  bool isBlurred = false;
  bool previousIsBlurred = false;

  void initialiseSecuring() {
    initialiseIsBlurred();

    if (Platform.isAndroid) {
      screenListener.preventAndroidScreenShot(true);
    }
  }

  void disposeSecuring() {
    if (Platform.isAndroid) {
      screenListener.preventAndroidScreenShot(false);
    }
  }

  @override
  void initState() {
    super.initState();
    screenListener = ScreenCaptureEvent(false);

    if (widget.isSecure) {
      initialiseSecuring();
    }
  }

  @override
  void didUpdateWidget(covariant AndroidSecureWidget oldWidget) {
    if (oldWidget.isSecure != widget.isSecure) {
      if (widget.isSecure) {
        initialiseSecuring();
      } else {
        disposeSecuring();
      }
    }
    super.didUpdateWidget(oldWidget);
  }

  void initialiseIsBlurred() async {
    final isRecording = await screenListener.isRecording();
    setState(() {
      isBlurred = isRecording;
    });
    if (isBlurred && widget.onScreenRecordingStart != null) {
      widget.onScreenRecordingStart?.call();
    }
  }

  @override
  void dispose() async {
    disposeSecuring();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PortalTarget(
      portalFollower: widget.overlayWidgetBuilder != null
          ? widget.overlayWidgetBuilder!(context)
          : widget.builder(context, initialiseSecuring, disposeSecuring),
      visible: widget.debug ? true : widget.isSecure && isBlurred,
      child: widget.builder(context, initialiseSecuring, disposeSecuring),
    );
  }
}
