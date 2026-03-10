import Flutter
import UIKit

public class SwiftSecureContentPlugin: NSObject, FlutterPlugin, SecureContentHostApi {
  private var flutterApi: SecureContentFlutterApi?

  private var secureEnabled = false
  private var protectInAppSwitcher = true
  private var appSwitcherColor: UIColor = .black

  private let captureOverlayTag = 991001
  private let appSwitcherOverlayTag = 991002

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

  public func configureProtection(config: ProtectionConfig) throws {
    secureEnabled = config.enabled
    protectInAppSwitcher = config.protectInAppSwitcher
    appSwitcherColor = Self.color(from: config.appSwitcherColor)

    applyProtectionState()
  }

  public func isScreenCaptured() throws -> Bool {
    return UIScreen.main.isCaptured
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

  private static func color(from argb: Int64) -> UIColor {
    let value = UInt32(truncatingIfNeeded: argb)
    let alpha = CGFloat((value >> 24) & 0xff) / 255.0
    let red = CGFloat((value >> 16) & 0xff) / 255.0
    let green = CGFloat((value >> 8) & 0xff) / 255.0
    let blue = CGFloat(value & 0xff) / 255.0

    return UIColor(red: red, green: green, blue: blue, alpha: alpha)
  }
}
