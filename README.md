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

<p align="center">A flutter package which allows Flutter apps to wrap up some widgets with a SecureWidget which can stop user from screen recording or screenshot the widget. Works on both Android & iOS, and is in development.</p><br>

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

|                                      Android (screen recording)                                       |                   iOS (screenshot)                    |                   iOS (screen recording)                    |                 iOS (app switcher)                  |
| :---------------------------------------------------------------------------------------------------: | :---------------------------------------------------: | :---------------------------------------------------------: | :-------------------------------------------------: |
| https://user-images.githubusercontent.com/60510869/154502746-830d9198-8f11-46ba-9246-784def00f610.mp4 | <img src="screenshot/screenshot_ios.PNG" width="300"> | https://github.com/user-attachments/assets/0b4e10ac-d592-4b5b-92bf-72f51b2cf570 | https://github.com/user-attachments/assets/b6ef5914-eb3a-4e17-be0c-2f00538cffec |

## Features

The package allows your app to protect content shown on screen and on recent apps screen. It shows a black color on iOS, and on Android it blocks screenshot, and shows black in screen recording. This package is in development, and more features will be added soon.

## Installing

### 1. Depend on it

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  secure_content: ^1.0.0
```

### 2. Install it

You can install packages from the command line:

with `pub`:

```bash
pub get
```

with `Flutter`:

```bash
flutter pub get
```

### 3. Import it

Now in your `Dart` code, you can use:

```dart
import 'package:secure_content/secure_content.dart';
```

## Example

```dart
import 'package:flutter/material.dart';
import 'package:secure_content/secure_content.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Secure Content Example'),
        ),
        body: SecureWidget(
          isSecure: true,
          builder: (context, onInit, onDispose) => Center(
            child: Text('This is a secure widget'),
          ),
        ),
      ),
    );
  }
}
```

> **Note**: The SecureWidget should be the root widget of your app, or the widget which you want to protect.
> See the [example](https://pub.dev/packages/secure_content/example) for more details.

# Bugs or Requests

If you encounter any problems feel free to open an [issue](https://github.com/codenameakshay/secure_content/issues/new?template=bug_report.md). If you feel the library is missing a feature, please raise a [ticket](https://github.com/codenameakshay/secure_content/issues/new?template=feature_request.md) on GitHub and I'll look into it. Pull request are also welcome.

See [Contributing.md](https://github.com/codenameakshay/secure_content/blob/master/CONTRIBUTING.md).
