import Flutter
import LocalAuthentication
import UIKit
import Darwin

public class SwiftSecureContentPlugin: NSObject, FlutterPlugin, SecureContentHostApi {
  private var flutterApi: SecureContentFlutterApi?

  private var secureEnabled = false
  private var protectInAppSwitcher = true
  private var appSwitcherColor: UIColor = .black

  private let captureOverlayTag = 991001
  private let appSwitcherOverlayTag = 991002
  private var clipboardClearWorkItem: DispatchWorkItem?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = SwiftSecureContentPlugin()
    instance.flutterApi = SecureContentFlutterApi(binaryMessenger: registrar.messenger())

    SecureContentHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: instance)
    instance.setupObservers()
    instance.emit(type: "platformReady")
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  func configureProtection(config: ProtectionConfig) throws {
    secureEnabled = config.enabled
    protectInAppSwitcher = config.protectInAppSwitcher
    appSwitcherColor = Self.color(from: config.appSwitcherColor)

    applyProtectionState()
  }

  func isScreenCaptured() throws -> Bool {
    return UIScreen.main.isCaptured
  }

  func requestBiometricAuth(reason: String) throws {
    let context = LAContext()
    var error: NSError?

    guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
      emit(type: "biometricUnavailable")
      return
    }

    let localizedReason = reason.isEmpty ? "Authenticate" : reason
    context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: localizedReason) {
      [weak self] success, _ in
      DispatchQueue.main.async {
        self?.emit(type: success ? "biometricAuthSucceeded" : "biometricAuthFailed")
      }
    }
  }

  func checkIntegrity() throws {
    let riskDetected = isJailbroken() || isDebuggerAttached() || isRunningOnSimulator()
    emit(type: riskDetected ? "integrityRiskDetected" : "integritySafe")
  }

  func setSensitiveClipboard(content: String, clearAfterMs: Int64) throws {
    UIPasteboard.general.string = content
    emit(type: "clipboardSet")

    clipboardClearWorkItem?.cancel()
    clipboardClearWorkItem = nil

    guard clearAfterMs > 0 else {
      return
    }

    let workItem = DispatchWorkItem { [weak self] in
      try? self?.clearSensitiveClipboard()
    }
    clipboardClearWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int(clearAfterMs)), execute: workItem)
  }

  func clearSensitiveClipboard() throws {
    UIPasteboard.general.string = ""
    clipboardClearWorkItem?.cancel()
    clipboardClearWorkItem = nil
    emit(type: "clipboardCleared")
  }

  private func setupObservers() {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleScreenshot),
      name: UIApplication.userDidTakeScreenshotNotification,
      object: nil
    )

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleCaptureStateChange),
      name: UIScreen.capturedDidChangeNotification,
      object: nil
    )

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleAppWillResignActive),
      name: UIApplication.willResignActiveNotification,
      object: nil
    )

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleAppDidBecomeActive),
      name: UIApplication.didBecomeActiveNotification,
      object: nil
    )
  }

  private func applyProtectionState() {
    if !secureEnabled {
      hideOverlay(tag: captureOverlayTag)
      hideOverlay(tag: appSwitcherOverlayTag)
      return
    }

    if UIScreen.main.isCaptured {
      showOverlay(tag: captureOverlayTag, color: .black)
    } else {
      hideOverlay(tag: captureOverlayTag)
    }
  }

  @objc private func handleScreenshot() {
    guard secureEnabled else { return }
    emit(type: "screenshotCaptured")
  }

  @objc private func handleCaptureStateChange() {
    let isCaptured = UIScreen.main.isCaptured

    if secureEnabled {
      if isCaptured {
        showOverlay(tag: captureOverlayTag, color: .black)
      } else {
        hideOverlay(tag: captureOverlayTag)
      }
    }

    emit(type: isCaptured ? "recordingStarted" : "recordingStopped")
  }

  @objc private func handleAppWillResignActive() {
    guard secureEnabled && protectInAppSwitcher else { return }
    showOverlay(tag: appSwitcherOverlayTag, color: appSwitcherColor)
    emit(type: "appSwitcherProtected")
  }

  @objc private func handleAppDidBecomeActive() {
    hideOverlay(tag: appSwitcherOverlayTag)
    if secureEnabled {
      emit(type: "appSwitcherUnprotected")
    }
  }

  private func showOverlay(tag: Int, color: UIColor) {
    guard let window = keyWindow() else { return }

    if let existing = window.viewWithTag(tag) {
      existing.backgroundColor = color
      existing.isHidden = false
      return
    }

    let overlay = UIView(frame: window.bounds)
    overlay.tag = tag
    overlay.backgroundColor = color
    overlay.isUserInteractionEnabled = false
    overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]

    window.addSubview(overlay)
  }

  private func hideOverlay(tag: Int) {
    guard let window = keyWindow() else { return }
    window.viewWithTag(tag)?.removeFromSuperview()
  }

  private func keyWindow() -> UIWindow? {
    if #available(iOS 13.0, *) {
      return UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
        .first(where: { $0.isKeyWindow })
    }

    return UIApplication.shared.windows.first(where: { $0.isKeyWindow })
  }

  private func emit(type: String) {
    let event = SecureEvent(
      type: type,
      platform: "ios",
      timestamp: ISO8601DateFormatter().string(from: Date())
    )

    flutterApi?.onEvent(event: event) { _ in }
  }

  private func isRunningOnSimulator() -> Bool {
    #if targetEnvironment(simulator)
      return true
    #else
      return false
    #endif
  }

  private func isJailbroken() -> Bool {
    #if targetEnvironment(simulator)
      return false
    #else
      let suspiciousPaths = [
        "/Applications/Cydia.app",
        "/Library/MobileSubstrate/MobileSubstrate.dylib",
        "/bin/bash",
        "/usr/sbin/sshd",
        "/etc/apt",
        "/private/var/lib/apt/",
      ]

      if suspiciousPaths.contains(where: { FileManager.default.fileExists(atPath: $0) }) {
        return true
      }

      let testPath = "/private/secure_content_jb_test.txt"
      do {
        try "test".write(toFile: testPath, atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(atPath: testPath)
        return true
      } catch {
        return false
      }
    #endif
  }

  private func isDebuggerAttached() -> Bool {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]

    let result = name.withUnsafeMutableBufferPointer { pointer in
      sysctl(pointer.baseAddress, 4, &info, &size, nil, 0)
    }

    if result != 0 {
      return false
    }

    return (info.kp_proc.p_flag & P_TRACED) != 0
  }

  private static func color(from argb: Int64) -> UIColor {
    let value = UInt32(truncatingIfNeeded: argb)
    let alpha = CGFloat((value >> 24) & 0xff) / 255.0
    let red = CGFloat((value >> 16) & 0xff) / 255.0
    let green = CGFloat((value >> 8) & 0xff) / 255.0
    let blue = CGFloat(value & 0xff) / 255.0

    return UIColor(red: red, green: green, blue: blue, alpha: alpha)
  }
}
