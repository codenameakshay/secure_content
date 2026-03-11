<!--
This README describes the package. If you publish this package to pub.dev,
this README's contents appear on the landing page for your package.

For information about how to write a good package README, see the guide for
[writing package pages](https://dart.dev/guides/libraries/writing-package-pages).

For general information about developing packages, see the Dart guide for
[creating packages](https://dart.dev/guides/libraries/create-library-packages)
and the Flutter guide for
[developing packages and plugins](https://flutter.dev/developing-packages).
-->

<h1 align="center">Secure Content</h1>

<p align="center">A flutter package which allows Flutter apps to wrap up some widgets with a SecureWidget which can stop user from screen recording or screenshot the widget. Works on both Android & iOS.</p><br>

<p align="center">
  <a href="https://flutter.dev">
    <img src="https://img.shields.io/badge/Platform-Flutter-02569B?logo=flutter"
      alt="Platform" />
  </a>
  <a href="https://pub.dartlang.org/packages/secure_content">
    <img src="https://img.shields.io/pub/v/secure_content.svg"
      alt="Pub Package" />
  </a>
  <a href="https://opensource.org/licenses/MIT">
    <img src="https://img.shields.io/github/license/aagarwal1012/animated-text-kit?color=red"
      alt="License: MIT" />
  </a>
  <a href="https://www.paypal.me/codenameakshay">
    <img src="https://img.shields.io/badge/Donate-PayPal-00457C?logo=paypal"
      alt="Donate" />
  </a>
</p><br>

## Screenshots

|                                      Android (screen recording)                                       |                   iOS (screenshot)                    |                             iOS (screen recording)                              |                               iOS (app switcher)                                |
| :---------------------------------------------------------------------------------------------------: | :---------------------------------------------------: | :-----------------------------------------------------------------------------: | :-----------------------------------------------------------------------------: |
| https://user-images.githubusercontent.com/60510869/154502746-830d9198-8f11-46ba-9246-784def00f610.mp4 | <img src="screenshot/screenshot_ios.PNG" width="300"> | https://github.com/user-attachments/assets/0b4e10ac-d592-4b5b-92bf-72f51b2cf570 | https://github.com/user-attachments/assets/b6ef5914-eb3a-4e17-be0c-2f00538cffec |

## Features

- 🔒 **Screenshot Protection**: Prevents users from taking screenshots of sensitive content
- 📹 **Screen Recording Protection**: Blocks screen recording attempts
- 📱 **App Switcher Protection**: Secures content in the app switcher preview
- ⚡ **Dynamic Security**: Enable/disable protection on the fly
- 🎨 **Customizable Overlay**: Define custom widgets to show when content is protected
- 📢 **Event Callbacks**: Get notified of screenshot and recording attempts
- 💪 **Cross-Platform**: Works on both Android & iOS
- 🔄 **State Aware**: Maintains security across route transitions

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  secure_content: ^1.0.1
```

## Basic Setup

1. First, wrap your MaterialApp with Portal widget:

```dart
void main() {
  runApp(
    Portal(
      child: MaterialApp(
        home: MyHomePage(),
      ),
    ),
  );
}
```

2. Import the package:

```dart
import 'package:secure_content/secure_content.dart';
```

## 🚨 Important Note

This package requires wrapping your `MaterialApp` with the `Portal` widget from the `flutter_portal` package. This is a crucial step to make the secure content functionality work properly. Here's how to do it:

```dart
import 'package:flutter_portal/flutter_portal.dart';

// In your app's root widget:
return Portal(
  child: MaterialApp(
    // Your MaterialApp configuration
  ),
);
```

If you don't wrap your `MaterialApp` with `Portal`, you'll encounter the following error:

```
PortalNotFoundError: Could not find a Portal above this PortalTarget
```

## Usage

### Basic Implementation

Wrap any widget that needs to be protected with `SecureWidget`:

```dart
SecureWidget(
  isSecure: true,
  builder: (context, onInit, onDispose) => Text(
    'This content is protected',
    style: Theme.of(context).textTheme.headlineMedium,
  ),
)
```

### Advanced Implementation

```dart
SecureWidget(
  isSecure: true,
  onScreenshotCaptured: () {
    // Handle screenshot attempt
    print('Screenshot attempted!');
  },
  onScreenRecordingStart: () {
    // Handle recording start
    print('Screen recording started!');
  },
  onScreenRecordingStop: () {
    // Handle recording stop
    print('Screen recording stopped!');
  },
  builder: (context, onInit, onDispose) => YourWidget(),
  overlayWidgetBuilder: (context) => BackdropFilter(
    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
    child: const SizedBox(),
  ),
  appSwitcherMenuColor: Colors.black,
  protectInAppSwitcherMenu: true,
)
```

## Configuration Options

| Parameter                  | Type                                                        | Description                              |
| -------------------------- | ----------------------------------------------------------- | ---------------------------------------- |
| `isSecure`                 | `bool`                                                      | Enable/disable protection                |
| `builder`                  | `Widget Function(BuildContext, VoidCallback, VoidCallback)` | Builder for the protected content        |
| `overlayWidgetBuilder`     | `Widget Function(BuildContext)?`                            | Custom overlay when content is protected |
| `onScreenshotCaptured`     | `VoidCallback?`                                             | Callback for screenshot attempts         |
| `onScreenRecordingStart`   | `VoidCallback?`                                             | Callback when recording starts           |
| `onScreenRecordingStop`    | `VoidCallback?`                                             | Callback when recording stops            |
| `debug`                    | `bool`                                                      | Show overlay widget for debugging        |
| `protectInAppSwitcherMenu` | `bool`                                                      | Enable protection in app switcher        |
| `appSwitcherMenuColor`     | `Color`                                                     | Background color in app switcher         |

## Protecting Entire App

To protect your entire app on Android:

```dart
final secureContent = SecureContent();

// Enable protection
secureContent.preventScreenshotAndroid(true);

// Disable protection
secureContent.preventScreenshotAndroid(false);
```

## Platform-Specific Behavior

### Feature Comparison

| Feature                         | iOS                                   | Android                 |
| ------------------------------- | ------------------------------------- | ----------------------- |
| Screenshot Prevention           | ✅                                    | ✅                      |
| Screen Recording Prevention     | ✅ (Shows black screen)               | ✅ (Shows black screen) |
| Screenshot Detection Callback   | ✅                                    | ✅ (Android 14+)        |
| Screen Recording Start Callback | ✅                                    | ❌                      |
| Screen Recording Stop Callback  | ✅                                    | ❌                      |
| App Switcher Protection         | ✅                                    | ✅                      |
| Custom Overlay Support          | ✅                                    | ✅                      |
| Dynamic Security Toggle         | ✅                                    | ✅                      |
| Full App Protection             | ✅ (Add widget to top of widget tree) | ✅                      |

### iOS

- Shows black screen during screen recording
- Prevents screenshots
- Provides callbacks for screenshot and screen recording events
- Customizable protection in app switcher
- Protection is widget-specific

### Android

- Blocks screenshots
- Shows black screen during recording
- Supports screenshot callback on Android 14+
- No callback support for screen recording start/stop events
- Supports full app protection through `preventScreenshotAndroid()`
- Protection can be applied globally or widget-specific

## Best Practices

1. **Platform-Specific Implementation**:

   - For iOS, utilize callbacks to provide user feedback
   - For Android, consider using global protection if needed
   - For iOS, use `SecureWidget` at the top of the widget tree, for global protection

   ```dart
   // iOS-specific implementation
   SecureWidget(
     isSecure: true,
     onScreenshotCaptured: Platform.isIOS ? () {
       // Only triggered on iOS
       showAlert('Screenshot attempted');
     } : null,
     builder: (context, onInit, onDispose) => YourWidget(),
   )

   // Android global protection
   if (Platform.isAndroid) {
     SecureContent().preventScreenshotAndroid(true);
   }
   ```

2. **Performance**: Only wrap widgets that need protection to maintain optimal performance
3. **State Management**: Use `isSecure` to dynamically toggle protection
4. **User Experience**: Provide alternative feedback mechanisms for Android
5. **Testing**: Test protection in both debug and release modes on both platforms

## Example

A complete example showing different use cases:

```dart
class SecureScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Secure Screen')),
      body: Column(
        children: [
          // Regular content
          Text('This content can be captured'),

          // Secure content
          SecureWidget(
            isSecure: true,
            onScreenshotCaptured: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Screenshots not allowed!')),
              );
            },
            builder: (context, onInit, onDispose) => Container(
              padding: EdgeInsets.all(16),
              child: Text('This content is protected'),
            ),
          ),
        ],
      ),
    );
  }
}
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
