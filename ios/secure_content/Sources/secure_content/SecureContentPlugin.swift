import Darwin
import Flutter
import LocalAuthentication
import UIKit

public class SecureContentPlugin: NSObject, FlutterPlugin, SecureContentHostApi {
  private enum OverlayKind {
    case capture
    case appSwitcher
  }

  private var flutterApi: SecureContentFlutterApi?

  private var secureEnabled = false
  private var protectInAppSwitcher = true
  private var appSwitcherColor: UIColor = .black
  private var appSwitcherImageName: String?
  private var platformReadyEmitted = false

  private let windowProvider: (() -> [UIWindow])?
  private let sceneActivationProvider: ((UIWindow) -> Bool)?
  private let captureOverlays = NSMapTable<UIWindow, UIView>.weakToStrongObjects()
  private let appSwitcherOverlays = NSMapTable<UIWindow, UIView>.weakToStrongObjects()
  private var clipboardClearWorkItem: DispatchWorkItem?
  private var sensitiveClipboardOwnership = SensitiveClipboardOwnership()
  private var sensitiveClipboardExpirationDate: Date?
  private var isAnyScreenCaptured = false
  var activeAuthenticationContext: LAContext?
  private var biometricRequestGeneration = 0

  public override init() {
    self.windowProvider = nil
    self.sceneActivationProvider = nil
    super.init()
  }

  init(
    windowProvider: (() -> [UIWindow])?,
    sceneActivationProvider: ((UIWindow) -> Bool)?
  ) {
    self.windowProvider = windowProvider
    self.sceneActivationProvider = sceneActivationProvider
    super.init()
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = SecureContentPlugin()
    instance.flutterApi = SecureContentFlutterApi(binaryMessenger: registrar.messenger())

    SecureContentHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: instance)
    instance.setupObservers()
    registrar.publish(instance)
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
    clipboardClearWorkItem?.cancel()
    activeAuthenticationContext?.invalidate()

    let ownedOverlays =
      (captureOverlays.objectEnumerator()?.allObjects ?? [])
      + (appSwitcherOverlays.objectEnumerator()?.allObjects ?? [])
    let cleanup = {
      for overlay in ownedOverlays {
        (overlay as? UIView)?.removeFromSuperview()
      }
    }
    if Thread.isMainThread {
      cleanup()
    } else {
      DispatchQueue.main.async(execute: cleanup)
    }
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    SecureContentHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: nil)
    NotificationCenter.default.removeObserver(self)
    clipboardClearWorkItem?.cancel()
    clipboardClearWorkItem = nil
    cancelActiveAuthentication()
    removeAllOverlays()
    flutterApi = nil
  }

  func configureProtection(config: ProtectionConfig) throws {
    secureEnabled = config.enabled
    protectInAppSwitcher = config.protectInAppSwitcher
    appSwitcherColor = Self.color(from: config.appSwitcherColor)
    appSwitcherImageName = config.appSwitcherImageName

    applyProtectionState()
    emitPlatformReadyOnce()
  }

  func isScreenCaptured() throws -> Bool {
    return UIScreen.screens.contains(where: \.isCaptured)
  }

  func requestBiometricAuth(reason: String) throws {
    cancelActiveAuthentication()
    let context = LAContext()
    var error: NSError?

    guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
      emit(type: "biometricUnavailable")
      return
    }

    let localizedReason = reason.isEmpty ? "Authenticate" : reason
    activeAuthenticationContext = context
    let requestGeneration = biometricRequestGeneration
    context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: localizedReason) {
      [weak self] success, _ in
      DispatchQueue.main.async {
        guard let self,
          self.biometricRequestGeneration == requestGeneration,
          self.activeAuthenticationContext === context
        else {
          return
        }
        self.activeAuthenticationContext = nil
        self.emit(type: success ? "biometricAuthSucceeded" : "biometricAuthFailed")
      }
    }
  }

  func cancelActiveAuthentication() {
    biometricRequestGeneration += 1
    activeAuthenticationContext?.invalidate()
    activeAuthenticationContext = nil
  }

  func checkIntegrity() throws {
    let riskDetected = isJailbroken() || isDebuggerAttached() || isRunningOnSimulator()
    emit(type: riskDetected ? "integrityRiskDetected" : "integritySafe")
  }

  func setSensitiveClipboard(content: String, clearAfterMs: Int64) throws {
    var options: [UIPasteboard.OptionsKey: Any] = [.localOnly: true]
    let expirationDate: Date?
    if clearAfterMs > 0 {
      let date = Date().addingTimeInterval(TimeInterval(clearAfterMs) / 1_000)
      expirationDate = date
      options[.expirationDate] = date
    } else {
      expirationDate = nil
    }

    UIPasteboard.general.setItems(
      [["public.utf8-plain-text": content]],
      options: options
    )
    sensitiveClipboardOwnership.record(
      content: content,
      changeCount: UIPasteboard.general.changeCount
    )
    sensitiveClipboardExpirationDate = expirationDate
    emit(type: "clipboardSet")

    clipboardClearWorkItem?.cancel()
    clipboardClearWorkItem = nil

    guard let expirationDate else {
      return
    }

    scheduleClipboardClear(at: expirationDate)
  }

  func clearSensitiveClipboard() throws {
    let pasteboard = UIPasteboard.general
    if sensitiveClipboardOwnership.ownsClipboard(currentChangeCount: pasteboard.changeCount, currentContent: {
      pasteboard.string
    }) {
      pasteboard.items = []
    }
    sensitiveClipboardOwnership.clear()
    sensitiveClipboardExpirationDate = nil
    clipboardClearWorkItem?.cancel()
    clipboardClearWorkItem = nil
    emit(type: "clipboardCleared")
  }

  private func scheduleClipboardClear(at expirationDate: Date) {
    // Keep each dispatch interval bounded. Very long TTLs are rescheduled in
    // chunks, avoiding integer overflow in DispatchTime's nanosecond deadline.
    let delayMilliseconds = SecureContentNativePolicy.dispatchDelayMilliseconds(
      until: expirationDate,
      now: Date()
    )
    let workItem = DispatchWorkItem { [weak self] in
      guard let self, self.sensitiveClipboardExpirationDate == expirationDate else {
        return
      }

      if Date() < expirationDate {
        self.scheduleClipboardClear(at: expirationDate)
      } else {
        try? self.clearSensitiveClipboard()
      }
    }
    clipboardClearWorkItem = workItem
    DispatchQueue.main.asyncAfter(
      deadline: .now() + .milliseconds(delayMilliseconds),
      execute: workItem
    )
  }

  func setupObservers() {
    isAnyScreenCaptured = UIScreen.screens.contains(where: \.isCaptured)

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleScreenshot),
      name: UIApplication.userDidTakeScreenshotNotification,
      object: nil
    )

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleCaptureStateChange(_:)),
      name: UIScreen.capturedDidChangeNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleScreenTopologyChange(_:)),
      name: UIScreen.didConnectNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleScreenTopologyChange(_:)),
      name: UIScreen.didDisconnectNotification,
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

    if #available(iOS 13.0, *) {
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(handleSceneWillDeactivate(_:)),
        name: UIScene.willDeactivateNotification,
        object: nil
      )
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(handleSceneDidActivate(_:)),
        name: UIScene.didActivateNotification,
        object: nil
      )
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(handleWindowDidBecomeVisible(_:)),
        name: UIWindow.didBecomeVisibleNotification,
        object: nil
      )
    }
  }

  private func applyProtectionState() {
    if !secureEnabled {
      removeAllOverlays()
      return
    }

    applyCaptureProtection(in: allWindows())
    reconcileAppSwitcherProtection(in: allWindows())
  }

  private func emitPlatformReadyOnce() {
    guard !platformReadyEmitted else { return }
    platformReadyEmitted = true
    emit(type: "platformReady")
  }

  @objc private func handleScreenshot() {
    guard secureEnabled else { return }
    emit(type: "screenshotCaptured")
  }

  @objc private func handleCaptureStateChange(_ notification: Notification) {
    updateCaptureState()
  }

  @objc private func handleScreenTopologyChange(_ notification: Notification) {
    updateCaptureState()
  }

  private func updateCaptureState() {
    let connectedScreens = UIScreen.screens
    let connectedScreenIDs = Set(connectedScreens.map { ObjectIdentifier($0) })
    applyCaptureProtection(in: allWindows())
    removeCaptureOverlays(forDisconnectedScreens: connectedScreenIDs)

    let anyScreenCaptured = connectedScreens.contains(where: \.isCaptured)
    if let eventType = SecureContentNativePolicy.recordingEvent(
      previouslyCaptured: isAnyScreenCaptured,
      isCaptured: anyScreenCaptured
    ) {
      emit(type: eventType)
    }
    isAnyScreenCaptured = anyScreenCaptured
  }

  @objc private func handleAppWillResignActive() {
    guard secureEnabled && protectInAppSwitcher else { return }
    let windows = allWindows()
    let wasCovered = hasAppSwitcherCover(in: windows)
    let installed = showOverlay(
      kind: .appSwitcher,
      color: appSwitcherColor,
      imageName: appSwitcherImageName
    )
    if installed && !wasCovered {
      emit(type: "appSwitcherProtected")
    }
  }

  @objc private func handleAppDidBecomeActive() {
    let windows = allWindows()
    reconcileAppSwitcherProtection(in: windows)
    if secureEnabled && protectInAppSwitcher && !hasAppSwitcherCover(in: windows) {
      emit(type: "appSwitcherUnprotected")
    }
  }

  @available(iOS 13.0, *)
  @objc private func handleSceneWillDeactivate(_ notification: Notification) {
    guard secureEnabled && protectInAppSwitcher,
      let scene = notification.object as? UIWindowScene
    else {
      return
    }
    let installed = showOverlay(
      kind: .appSwitcher,
      color: appSwitcherColor,
      imageName: appSwitcherImageName,
      in: scene.windows
    )
    if installed {
      emit(type: "appSwitcherProtected")
    }
  }

  @available(iOS 13.0, *)
  @objc private func handleSceneDidActivate(_ notification: Notification) {
    guard let scene = notification.object as? UIWindowScene else { return }
    let windows = scene.windows
    let removedCover = windows.contains { appSwitcherOverlays.object(forKey: $0) != nil }
    hideOverlay(kind: .appSwitcher, in: windows)
    applyCaptureProtection(in: windows)
    if removedCover && secureEnabled && protectInAppSwitcher
      && !hasAppSwitcherCover(in: allWindows())
    {
      emit(type: "appSwitcherUnprotected")
    }
  }

  @available(iOS 13.0, *)
  @objc private func handleWindowDidBecomeVisible(_ notification: Notification) {
    guard let window = notification.object as? UIWindow else { return }
    if secureEnabled && window.screen.isCaptured {
      showOverlay(kind: .capture, color: .black, in: [window])
    }
    let sceneIsActive = isSceneActive(for: window)
    if SecureContentNativePolicy.shouldCoverAppSwitcher(
      enabled: secureEnabled,
      protectInAppSwitcher: protectInAppSwitcher,
      sceneIsActive: sceneIsActive
    ) {
      showOverlay(
        kind: .appSwitcher,
        color: appSwitcherColor,
        imageName: appSwitcherImageName,
        in: [window]
      )
    }
  }

  // Installs (or removes) the privacy overlay on every window of every
  // connected scene, not just the key window, so multi-window/multi-scene
  // apps (iPad Split View, Stage Manager, multiple UIWindowScenes) stay
  // covered. On a single-scene app this is exactly the same window set as
  // before.
  @discardableResult
  private func showOverlay(
    kind: OverlayKind,
    color: UIColor,
    imageName: String? = nil,
    in windows: [UIWindow]? = nil
  ) -> Bool {
    let windows = windows ?? allWindows()
    guard !windows.isEmpty else { return false }

    var installed = false
    for window in windows {
      installed =
        installOverlay(in: window, kind: kind, color: color, imageName: imageName) || installed
    }
    return installed
  }

  @discardableResult
  private func installOverlay(
    in window: UIWindow, kind: OverlayKind, color: UIColor, imageName: String?
  ) -> Bool {
    let overlay: UIView
    let wasVisible: Bool
    let overlays = overlayTable(for: kind)
    if let existing = overlays.object(forKey: window) {
      overlay = existing
      wasVisible = !existing.isHidden
    } else {
      overlay = UIView(frame: window.bounds)
      overlay.isUserInteractionEnabled = false
      overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      window.addSubview(overlay)
      overlays.setObject(overlay, forKey: window)
      wasVisible = false
    }
    overlay.backgroundColor = color
    overlay.isHidden = false
    overlay.frame = window.bounds

    let imageState = imageName.map { "secure_content.image:\($0)" } ?? "secure_content.image:none"
    if overlay.accessibilityIdentifier != imageState {
      for subview in overlay.subviews {
        subview.removeFromSuperview()
      }
      overlay.accessibilityIdentifier = imageState

      if let name = imageName, let raw = UIImage(named: name) {
        let imageView = UIImageView(image: raw.withRenderingMode(.alwaysTemplate))
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(imageView)

        let shorterSide = min(window.bounds.width, window.bounds.height)
        let logoWidth = max(96, min(160, shorterSide * 0.28))
        let aspect = raw.size.width > 0 ? raw.size.height / raw.size.width : 1
        NSLayoutConstraint.activate([
          imageView.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
          imageView.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
          imageView.widthAnchor.constraint(equalToConstant: logoWidth),
          imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor, multiplier: aspect),
        ])
      }
    }

    window.bringSubviewToFront(overlay)
    return !wasVisible
  }

  private func hideOverlay(kind: OverlayKind, in windows: [UIWindow]? = nil) {
    let overlays = overlayTable(for: kind)
    guard let windows else {
      removeOverlays(from: overlays)
      return
    }
    for window in windows {
      overlays.object(forKey: window)?.removeFromSuperview()
      overlays.removeObject(forKey: window)
    }
  }

  private func applyCaptureProtection(in windows: [UIWindow]) {
    for screen in Set(windows.map(\.screen)) {
      let screenWindows = windows.filter { $0.screen === screen }
      if secureEnabled && screen.isCaptured {
        showOverlay(kind: .capture, color: .black, in: screenWindows)
      } else {
        hideOverlay(kind: .capture, in: screenWindows)
      }
    }
  }

  private func reconcileAppSwitcherProtection(in windows: [UIWindow]) {
    guard secureEnabled && protectInAppSwitcher else {
      hideOverlay(kind: .appSwitcher, in: windows)
      return
    }

    for window in windows {
      let shouldCover = SecureContentNativePolicy.shouldCoverAppSwitcher(
        enabled: secureEnabled,
        protectInAppSwitcher: protectInAppSwitcher,
        sceneIsActive: isSceneActive(for: window)
      )

      if shouldCover {
        showOverlay(
          kind: .appSwitcher,
          color: appSwitcherColor,
          imageName: appSwitcherImageName,
          in: [window]
        )
      } else {
        hideOverlay(kind: .appSwitcher, in: [window])
      }
    }
  }

  private func hasAppSwitcherCover(in windows: [UIWindow]) -> Bool {
    windows.contains { window in
      guard let overlay = appSwitcherOverlays.object(forKey: window) else { return false }
      return !overlay.isHidden
    }
  }

  private func isSceneActive(for window: UIWindow) -> Bool {
    if let sceneActivationProvider {
      return sceneActivationProvider(window)
    }
    if #available(iOS 13.0, *), let scene = window.windowScene {
      return scene.activationState == .foregroundActive
    }
    return UIApplication.shared.applicationState == .active
  }

  private func overlayTable(for kind: OverlayKind) -> NSMapTable<UIWindow, UIView> {
    switch kind {
    case .capture:
      return captureOverlays
    case .appSwitcher:
      return appSwitcherOverlays
    }
  }

  private func removeAllOverlays() {
    removeOverlays(from: captureOverlays)
    removeOverlays(from: appSwitcherOverlays)
  }

  private func removeCaptureOverlays(forDisconnectedScreens connectedScreenIDs: Set<ObjectIdentifier>) {
    let windows = captureOverlays.keyEnumerator().allObjects.compactMap { $0 as? UIWindow }
    for window in windows where !connectedScreenIDs.contains(ObjectIdentifier(window.screen)) {
      hideOverlay(kind: .capture, in: [window])
    }
  }

  private func removeOverlays(from overlays: NSMapTable<UIWindow, UIView>) {
    for overlay in overlays.objectEnumerator()?.allObjects ?? [] {
      (overlay as? UIView)?.removeFromSuperview()
    }
    overlays.removeAllObjects()
  }

  private func allWindows() -> [UIWindow] {
    if let windowProvider {
      return windowProvider()
    }
    if #available(iOS 13.0, *) {
      return UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
    }

    return UIApplication.shared.windows
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
    let red = CGFloat((value >> 16) & 0xff) / 255.0
    let green = CGFloat((value >> 8) & 0xff) / 255.0
    let blue = CGFloat(value & 0xff) / 255.0

    // Privacy covers must remain opaque even if the caller passes a color
    // with a transparent ARGB alpha channel.
    return UIColor(red: red, green: green, blue: blue, alpha: 1)
  }
}
