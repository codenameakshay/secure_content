import 'package:flutter/material.dart';
import 'package:flutter_portal/flutter_portal.dart';
import 'package:screen_protector/lifecycle/lifecycle_state.dart';
import 'package:screen_protector/screen_protector.dart';

class IOSSecureWidget extends StatefulWidget {
  const IOSSecureWidget({
    Key? key,
    required this.builder,
    required this.isSecure,
    this.overlayWidgetBuilder,
    this.onScreenshotCaptured,
    this.onScreenRecordingStart,
    this.onScreenRecordingStop,
    this.debug = false,
    this.protectInAppSwitcherMenu = true,
    this.appSwitcherMenuColor = Colors.black,
  }) : super(key: key);

  /// The builder for child widget to be secured.
  final Widget Function(
          BuildContext context, VoidCallback onInit, VoidCallback onDispose)
      builder;

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

  /// (Optional) A bool to show a colored overlay on the full app, when it is viewed in app switcher. Default is true.
  final bool protectInAppSwitcherMenu;

  /// (Optional) The color for the app overlay when the app is in app switcher. Default is [Colors.black].
  final Color appSwitcherMenuColor;

  @override
  State<IOSSecureWidget> createState() => _IOSSecureWidgetState();
}

class _IOSSecureWidgetState extends LifecycleState<IOSSecureWidget> {
  bool isBlurred = false;

  @override
  void initState() {
    if (widget.isSecure) {
      initialiseSecuring();
    }
    super.initState();
  }

  void initialiseIsBlurred() async {
    final isRecording = await ScreenProtector.isRecording();
    setState(() {
      isBlurred = isRecording;
    });
    if (isBlurred && widget.onScreenRecordingStart != null) {
      widget.onScreenRecordingStart?.call();
    }
  }

  void initialiseSecuring() {
    initialiseIsBlurred();
    if (widget.protectInAppSwitcherMenu) {
      _protectDataLeakageWithColor(widget.appSwitcherMenuColor);
    }

    _addListenerPreventScreenshot();
    _preventScreenshotOn();
  }

  @override
  void onResumed() {
    if (widget.isSecure) {
      _protectDataLeakageWithBlurOff();
    }
    super.onResumed();
  }

  @override
  void onInactive() {
    if (widget.isSecure) {
      _protectDataLeakageWithBlur();
    }
    super.onInactive();
  }

  @override
  void didUpdateWidget(covariant IOSSecureWidget oldWidget) {
    if (oldWidget.isSecure != widget.isSecure) {
      if (widget.isSecure) {
        initialiseSecuring();
      } else {
        disposeSecuring();
      }
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    disposeSecuring();
    super.dispose();
  }

  void disposeSecuring() {
    if (widget.protectInAppSwitcherMenu) {
      _protectDataLeakageWithColorOff();
    }
    _removeListenerPreventScreenshot();
    _preventScreenshotOff();
  }

  void _protectDataLeakageWithColor(Color color) async =>
      await ScreenProtector.protectDataLeakageWithColor(color);
  void _protectDataLeakageWithColorOff() async =>
      await ScreenProtector.protectDataLeakageWithColorOff();

  void _protectDataLeakageWithBlur() async =>
      await ScreenProtector.protectDataLeakageWithBlur();
  void _protectDataLeakageWithBlurOff() async =>
      await ScreenProtector.protectDataLeakageWithBlurOff();

  void _preventScreenshotOn() async =>
      await ScreenProtector.preventScreenshotOn();
  void _preventScreenshotOff() async =>
      await ScreenProtector.preventScreenshotOff();

  void _addListenerPreventScreenshot() async {
    ScreenProtector.addListener(() {
      // Screenshot
      widget.onScreenshotCaptured?.call();
    }, (isCaptured) {
      // Screen Record
      setState(() {
        isBlurred = isCaptured;
      });
      if (isBlurred) {
        widget.onScreenRecordingStart?.call();
      } else {
        widget.onScreenRecordingStop?.call();
      }
      // print("isBlurred : $isBlurred");
    });
  }

  void _removeListenerPreventScreenshot() async {
    ScreenProtector.removeListener();
  }

  @override
  Widget build(BuildContext context) {
    return PortalTarget(
      portalFollower: widget.overlayWidgetBuilder != null
          ? widget.overlayWidgetBuilder!(context)
          : null,
      visible: widget.debug ? true : widget.isSecure && isBlurred,
      child: Container(
        decoration: widget.debug
            ? BoxDecoration(
                color: Colors.amber,
                border: Border.all(
                  color: Colors.red,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(10),
              )
            : null,
        child: widget.builder(context, initialiseSecuring, disposeSecuring),
      ),
    );
  }
}
