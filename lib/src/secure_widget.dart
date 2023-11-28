import 'dart:io';

import 'package:flutter/material.dart';
import 'package:secure_content/secure_content.dart';

class SecureWidget extends StatelessWidget {
  const SecureWidget({
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

  /// (Optional) [iOS] Callback when screenshot is captured
  final VoidCallback? onScreenshotCaptured;

  /// (Optional) [iOS] Callback when screenRecordingStart is detected
  final VoidCallback? onScreenRecordingStart;

  /// (Optional) [iOS] Callback when screenRecordingStop is detected
  final VoidCallback? onScreenRecordingStop;

  /// (Optional) A bool to show overlay widget, so that debugging is easier. Default is false.
  final bool debug;

  /// (Optional) [iOS] A bool to show a colored overlay on the full app, when it is viewed in app switcher. Default is true.
  final bool protectInAppSwitcherMenu;

  /// (Optional) [iOS] The color for the app overlay when the app is in app switcher. Default is [Colors.black].
  final Color appSwitcherMenuColor;

  @override
  Widget build(BuildContext context) {
    return Platform.isIOS
        ? IOSSecureWidget(
            isSecure: isSecure,
            builder: builder,
            onScreenshotCaptured: onScreenshotCaptured,
            onScreenRecordingStart: onScreenRecordingStart,
            onScreenRecordingStop: onScreenRecordingStop,
            overlayWidgetBuilder: overlayWidgetBuilder,
            debug: debug,
            protectInAppSwitcherMenu: protectInAppSwitcherMenu,
            appSwitcherMenuColor: appSwitcherMenuColor,
          )
        : AndroidSecureWidget(
            builder: builder,
            isSecure: isSecure,
            // onScreenshotCaptured: (filePath) => onScreenshotCaptured,
            // onScreenRecordingStart: onScreenRecordingStart,
            // onScreenRecordingStop: onScreenRecordingStop,
            overlayWidgetBuilder: overlayWidgetBuilder,
            debug: debug,
          );
  }
}
