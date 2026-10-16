import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_content/secure_content.dart';
import 'package:secure_content/src/secure_content_platform.dart';

void watermarkTestWidgets(String description, WidgetTesterCallback body) {
  testWidgets(description, (tester) async {
    SecureContentPlatform.debugIsSupportedPlatformOverride = false;
    try {
      await body(tester);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      SecureContentPlatform.debugIsSupportedPlatformOverride = null;
    }
  });
}

void main() {
  watermarkTestWidgets(
    'custom watermark shadows stay inside the scope and leave siblings untouched',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: RepaintBoundary(
              key: const Key('paint-boundary'),
              child: SizedBox(
                width: 220,
                height: 100,
                child: Stack(
                  children: [
                    const Positioned.fill(
                      child: ColoredBox(color: Colors.green),
                    ),
                    Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: 100,
                        height: 100,
                        child: SecureContentScope(
                          enabled: true,
                          policy: const SecureContentPolicy(
                            watermarkText: 'WATERMARK',
                            watermarkStyle: TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              shadows: [
                                Shadow(
                                  color: Colors.red,
                                  offset: Offset(250, 0),
                                ),
                              ],
                            ),
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();

      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('paint-boundary')),
      );
      final pendingImage = await tester.runAsync(boundary.toImage);
      expect(pendingImage, isNotNull);
      final image = pendingImage!;
      addTearDown(image.dispose);
      expect(image.width, 220);
      expect(image.height, 100);
      final pendingPixels = await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
      );
      expect(pendingPixels, isNotNull);
      final pixels = pendingPixels!;
      var watermarkVisible = false;
      for (var y = 0; y < 100; y += 2) {
        for (var x = 0; x < 100; x += 2) {
          final offset = (y * image.width + x) * 4;
          if (pixels.getUint8(offset) != 76 ||
              pixels.getUint8(offset + 1) != 175 ||
              pixels.getUint8(offset + 2) != 80 ||
              pixels.getUint8(offset + 3) != 255) {
            watermarkVisible = true;
            break;
          }
        }
        if (watermarkVisible) {
          break;
        }
      }
      expect(watermarkVisible, isTrue);

      for (var y = 0; y < image.height; y += 10) {
        for (var x = 100; x < image.width; x += 10) {
          final offset = (y * image.width + x) * 4;
          expect(
            [
              pixels.getUint8(offset),
              pixels.getUint8(offset + 1),
              pixels.getUint8(offset + 2),
              pixels.getUint8(offset + 3),
            ],
            [76, 175, 80, 255],
            reason: 'watermark painting escaped into sibling at ($x, $y)',
          );
        }
      }
      expect(tester.takeException(), isNull);
    },
  );

  watermarkTestWidgets(
    'empty watermark text with a custom style is safe in a zero-size scope',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: SizedBox(
              width: 0,
              height: 0,
              child: SecureContentScope(
                enabled: true,
                policy: SecureContentPolicy(
                  watermarkText: '',
                  watermarkStyle: TextStyle(fontSize: 24, shadows: [Shadow()]),
                ),
                child: SizedBox.shrink(),
              ),
            ),
          ),
        ),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();

      expect(tester.getSize(find.byType(SecureContentScope)), Size.zero);
      expect(tester.takeException(), isNull);
    },
  );

  watermarkTestWidgets(
    'watermark paints for a finite child in an unbounded scroll parent',
    (tester) async {
      const scopeKey = Key('scroll-scope');
      await tester.pumpWidget(
        MaterialApp(
          home: SingleChildScrollView(
            child: Align(
              alignment: Alignment.topLeft,
              child: SecureContentScope(
                key: scopeKey,
                enabled: true,
                child: const SizedBox(
                  width: 200,
                  height: 120,
                  child: Text('protected'),
                ),
              ),
            ),
          ),
        ),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();

      final scopeSize = tester.getSize(find.byKey(scopeKey));
      expect(scopeSize, const Size(200, 120));
      expect(tester.takeException(), isNull);
    },
  );
}
