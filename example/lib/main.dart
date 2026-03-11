import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:secure_content/secure_content.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'secure_content v2 example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final SecureContentController _controller = SecureContent.createController();

  bool _scopeEnabled = true;
  bool _hardBlockMode = false;
  int _counter = 0;
  String _lastEvent = 'No events yet';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _toggleGlobalProtection() async {
    if (_controller.enabled) {
      await _controller.disable();
    } else {
      await _controller.enable(
        protectInAppSwitcher: true,
        appSwitcherColor: Colors.black,
      );
    }

    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Secure Content v2')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Global protection: ${_controller.enabled ? 'ON' : 'OFF'}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Scoped protection: ${_scopeEnabled ? 'ON' : 'OFF'}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton(
                    onPressed: _toggleGlobalProtection,
                    child: const Text('Toggle global protection'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _scopeEnabled = !_scopeEnabled;
                      });
                    },
                    child: const Text('Toggle scope protection'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _counter++;
                      });
                    },
                    child: const Text('Increment secure counter'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      SecureContent.requestBiometricAuth(
                        reason: 'Unlock secure content',
                      );
                    },
                    child: const Text('Request biometric auth'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      SecureContent.checkIntegrity();
                    },
                    child: const Text('Run integrity check'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      SecureContent.setSensitiveClipboard(
                        'Sensitive counter=$_counter',
                        clearAfter: const Duration(seconds: 10),
                      );
                    },
                    child: const Text('Copy secure text (10s)'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _hardBlockMode = !_hardBlockMode;
                      });
                    },
                    child: Text(
                      _hardBlockMode
                          ? 'Hard block mode: ON'
                          : 'Hard block mode: OFF',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'Protected content area',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 280,
                child: SecureContentScope(
                  enabled: _scopeEnabled,
                  protectInAppSwitcher: true,
                  appSwitcherColor: Colors.black,
                  policy: SecureContentPolicy(
                    requireBiometricOnResume: true,
                    inactivityTimeout: const Duration(seconds: 20),
                    enableIntegrityChecks: true,
                    hardBlockOnIntegrityRisk: _hardBlockMode,
                    enableRiskWatermark: true,
                    watermarkText: 'EXAMPLE SENSITIVE',
                  ),
                  onEvent: (event) {
                    if (!mounted) {
                      return;
                    }
                    setState(() {
                      _lastEvent = event.type.name;
                    });
                  },
                  overlayBuilder: (context) => BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.55),
                    ),
                  ),
                  child: Card(
                    child: Center(
                      child: Text(
                        'Secure counter: $_counter',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text('Last secure event: $_lastEvent'),
              const SizedBox(height: 4),
              const Text(
                'Tip: Android screenshot callback requires Android 14+.',
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
