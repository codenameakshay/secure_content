import Flutter
import UIKit

public class SwiftSecureContentPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private var methodChannel: FlutterMethodChannel?
  private var eventChannel: FlutterEventChannel?
  private var eventSink: FlutterEventSink?

  private var secureEnabled = false
  private var protectInAppSwitcher = true
  private var appSwitcherColor: UIColor = .black

  private let captureOverlayTag = 991001
  private let appSwitcherOverlayTag = 991002

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = SwiftSecureContentPlugin()

    let methodChannel = FlutterMethodChannel(name: "secure_content/methods", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: methodChannel)

    let eventChannel = FlutterEventChannel(name: "secure_content/events", binaryMessenger: registrar.messenger())
    eventChannel.setStreamHandler(instance)

    instance.methodChannel = methodChannel
    instance.eventChannel = eventChannel
    instance.setupObservers()
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "configureProtection":
      guard let args = call.arguments as? [String: Any] else {
        result(
          FlutterError(
            code: "invalid_args",
            message: "Expected argument map",
            details: nil
          )
        )
        return
      }

      secureEnabled = args["enabled"] as? Bool ?? false
      protectInAppSwitcher = args["protectInAppSwitcher"] as? Bool ?? true
      appSwitcherColor = Self.color(from: args["appSwitcherColor"] as? NSNumber)

      applyProtectionState()
      result(nil)

    case "isScreenCaptured":
      result(UIScreen.main.isCaptured)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    emit(type: "platformReady")
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
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
    eventSink?([
      "type": type,
      "platform": "ios",
      "timestamp": ISO8601DateFormatter().string(from: Date())
    ])
  }

  private static func color(from number: NSNumber?) -> UIColor {
    guard let number else {
      return .black
    }

    let argb = UInt32(truncating: number)
    let alpha = CGFloat((argb >> 24) & 0xff) / 255.0
    let red = CGFloat((argb >> 16) & 0xff) / 255.0
    let green = CGFloat((argb >> 8) & 0xff) / 255.0
    let blue = CGFloat(argb & 0xff) / 255.0

    return UIColor(red: red, green: green, blue: blue, alpha: alpha)
  }
}
