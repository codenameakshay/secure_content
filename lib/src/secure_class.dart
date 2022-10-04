import 'dart:io';

import 'package:screen_capture_event/screen_capture_event.dart';

class SecureContent {
  final ScreenCaptureEvent screenListener = ScreenCaptureEvent();

  /// Call this to change flags for Android on the fly for whole app, rather
  /// than the secured widget. Useful if you just want to protect your whole
  /// app.
  void preventScreenshotAndroid(bool prevent) {
    if (Platform.isAndroid) {
      screenListener.preventAndroidScreenShot(prevent);
    }
  }
}
