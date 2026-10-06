import Flutter
import UIKit

@MainActor
final class SecureContentRuntime: NSObject {
  let authentication = SecureContentAuthentication()
  private let clipboard = SecureContentClipboard()
  private let capture = SecureContentCapture()
  private let overlays: SecureContentOverlays
  private var flutterApi: SecureContentFlutterApi?
  private let timestampFormatter = ISO8601DateFormatter()
  private var secureEnabled = false
  private var platformReadyEmitted = false
  private var observing = false
  private var isAnyScreenCaptured = false

  init(
    windowProvider: (() -> [UIWindow])? = nil,
    sceneActivationProvider: ((UIWindow) -> Bool)? = nil
  ) {
    overlays = SecureContentOverlays(
      windowProvider: windowProvider,
      sceneActivationProvider: sceneActivationProvider
    )
    super.init()
  }

  var isScreenCaptured: Bool { capture.isCaptured }

  func connect(binaryMessenger: FlutterBinaryMessenger) {
    flutterApi = SecureContentFlutterApi(binaryMessenger: binaryMessenger)
    setupObservers()
  }

  func configureProtection(config: ProtectionConfig) {
    secureEnabled = config.enabled
    capture.observeScenes()
    reconcileAppSwitcherEvents { overlays.configure(config) }
    if !platformReadyEmitted {
      platformReadyEmitted = true
      emit(.platformReady)
    }
  }

  func requestBiometricAuth(reason: String) {
    authentication.request(reason: reason) { [weak self] event in self?.emit(event) }
  }

  func checkIntegrity() {
    emit(SecureContentIntegrity.riskDetected ? .integrityRiskDetected : .integritySafe)
  }

  func setSensitiveClipboard(content: String, clearAfterMs: Int64) {
    clipboard.set(content: content, clearAfterMs: clearAfterMs) { [weak self] in
      self?.emit(.clipboardCleared)
    }
    emit(.clipboardSet)
  }

  func clearSensitiveClipboard() {
    clipboard.clear()
    emit(.clipboardCleared)
  }

  func dispose() {
    NotificationCenter.default.removeObserver(self)
    observing = false
    authentication.cancel()
    clipboard.dispose()
    capture.dispose()
    overlays.removeAll()
    flutterApi = nil
  }

  func setupObservers() {
    guard !observing else { return }
    observing = true
    capture.onChange = { [weak self] in self?.handleCaptureStateChange() }
    capture.observeScenes()
    isAnyScreenCaptured = isScreenCaptured
    let observers: [(Notification.Name, Selector)] = [
      (UIApplication.userDidTakeScreenshotNotification, #selector(handleScreenshot)),
      (UIApplication.willResignActiveNotification, #selector(handleAppWillResignActive)),
      (UIApplication.didBecomeActiveNotification, #selector(handleAppDidBecomeActive)),
      (UIScene.willDeactivateNotification, #selector(handleSceneWillDeactivate)),
      (UIScene.didActivateNotification, #selector(handleSceneDidActivate)),
      (UIScene.didDisconnectNotification, #selector(handleCaptureStateChange)),
      (UIScene.willConnectNotification, #selector(handleCaptureStateChange)),
      (UIWindow.didBecomeVisibleNotification, #selector(handleWindowDidBecomeVisible)),
      (UIScreen.capturedDidChangeNotification, #selector(handleCaptureStateChange)),
      (UIScreen.didConnectNotification, #selector(handleCaptureStateChange)),
      (UIScreen.didDisconnectNotification, #selector(handleCaptureStateChange)),
    ]
    for (name, selector) in observers {
      NotificationCenter.default.addObserver(self, selector: selector, name: name, object: nil)
    }
  }

  @objc private func handleScreenshot() {
    if secureEnabled { emit(.screenshotCaptured) }
  }

  @objc private func handleCaptureStateChange() {
    capture.observeScenes()
    let windows = overlays.allWindows
    overlays.reconcileCapture(in: windows)
    overlays.removeCaptureOverlays(
      forMissingWindows: Set(windows.map { ObjectIdentifier($0) })
    )
    let captured = capture.isCaptured
    if let event = SecureContentNativePolicy.recordingEvent(
      previouslyCaptured: isAnyScreenCaptured, isCaptured: captured
    ) {
      emit(event)
    }
    isAnyScreenCaptured = captured
  }

  @objc private func handleAppWillResignActive() {
    reconcileAppSwitcherEvents { overlays.coverAppSwitcher(in: overlays.allWindows) }
  }

  @objc private func handleAppDidBecomeActive() {
    reconcileAppSwitcherEvents { overlays.reconcileAppSwitcher(in: overlays.allWindows) }
    overlays.reconcileCapture(in: overlays.allWindows)
  }

  @objc private func handleSceneWillDeactivate(_ notification: Notification) {
    guard let scene = notification.object as? UIWindowScene else { return }
    reconcileAppSwitcherEvents { overlays.coverAppSwitcher(in: scene.windows) }
  }

  @objc private func handleSceneDidActivate(_ notification: Notification) {
    guard let scene = notification.object as? UIWindowScene else { return }
    reconcileAppSwitcherEvents { overlays.uncoverAppSwitcher(in: scene.windows) }
    overlays.reconcileCapture(in: scene.windows)
  }

  @objc private func handleWindowDidBecomeVisible(_ notification: Notification) {
    guard let window = notification.object as? UIWindow else { return }
    capture.observeScenes()
    overlays.reconcileCapture(in: [window])
    reconcileAppSwitcherEvents { overlays.reconcileAppSwitcher(in: [window]) }
  }

  private func reconcileAppSwitcherEvents(_ update: () -> Void) {
    let wasProtected = overlays.isAppSwitcherProtected
    update()
    if let event = SecureContentNativePolicy.appSwitcherEvent(
      previouslyProtected: wasProtected,
      isProtected: overlays.isAppSwitcherProtected
    ) {
      emit(event)
    }
  }

  private func emit(_ type: SecureContentEventType) {
    flutterApi?.onEvent(
      event: SecureEvent(
        type: type.rawValue, platform: "ios", timestamp: timestampFormatter.string(from: Date())
      )
    ) { _ in }
  }
}
