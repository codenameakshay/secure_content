import 'package:flutter/material.dart';

class SecureContentPolicy {
  const SecureContentPolicy({
    this.requireBiometricOnResume = false,
    this.biometricReason = 'Authenticate to continue',
    this.inactivityTimeout,
    this.enableIntegrityChecks = false,
    this.hardBlockOnIntegrityRisk = false,
    this.enableRiskWatermark = true,
    this.watermarkText = 'Sensitive',
    this.watermarkStyle,
    this.clipboardClearAfter = const Duration(seconds: 30),
  });

  final bool requireBiometricOnResume;
  final String biometricReason;
  final Duration? inactivityTimeout;
  final bool enableIntegrityChecks;
  final bool hardBlockOnIntegrityRisk;
  final bool enableRiskWatermark;
  final String watermarkText;
  final TextStyle? watermarkStyle;
  final Duration clipboardClearAfter;
}
