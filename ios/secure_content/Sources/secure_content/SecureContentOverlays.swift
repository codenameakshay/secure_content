import UIKit

@MainActor
final class SecureContentOverlays {
  private enum Kind {
    case capture
    case appSwitcher
  }

  private var config = ProtectionConfig(
    enabled: false, protectInAppSwitcher: true, appSwitcherColor: 0xFF000000
  )
  private let windowProvider: (() -> [UIWindow])?
  private let sceneActivationProvider: ((UIWindow) -> Bool)?
  private let capture = NSMapTable<UIWindow, PrivacyOverlayView>.weakToStrongObjects()
  private let appSwitcher = NSMapTable<UIWindow, PrivacyOverlayView>.weakToStrongObjects()

  init(
    windowProvider: (() -> [UIWindow])? = nil,
    sceneActivationProvider: ((UIWindow) -> Bool)? = nil
  ) {
    self.windowProvider = windowProvider
    self.sceneActivationProvider = sceneActivationProvider
  }

  var isAppSwitcherProtected: Bool {
    appSwitcher.objectEnumerator()?.allObjects.contains {
      ($0 as? PrivacyOverlayView)?.superview != nil
    } ?? false
  }

  var allWindows: [UIWindow] {
    if let windowProvider { return windowProvider() }
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    return scenes.isEmpty ? UIApplication.shared.windows : scenes.flatMap(\.windows)
  }

  func configure(_ config: ProtectionConfig) {
    self.config = config
    guard config.enabled else {
      removeAll()
      return
    }
    let windows = allWindows
    reconcileCapture(in: windows)
    reconcileAppSwitcher(in: windows)
  }

  func reconcileCapture(in windows: [UIWindow]) {
    for window in windows {
      if config.enabled && SecureContentCapture.isCaptured(in: window) {
        install(.capture, in: window, color: .black)
      } else {
        remove(.capture, from: window)
      }
    }
  }

  func reconcileAppSwitcher(in windows: [UIWindow]) {
    guard config.enabled && config.protectInAppSwitcher else {
      removeAll(from: appSwitcher)
      return
    }
    for window in windows {
      if SecureContentNativePolicy.shouldCoverAppSwitcher(
        enabled: config.enabled,
        protectInAppSwitcher: config.protectInAppSwitcher,
        sceneIsActive: isSceneActive(for: window)
      ) {
        installAppSwitcher(in: window)
      } else {
        remove(.appSwitcher, from: window)
      }
    }
  }

  func coverAppSwitcher(in windows: [UIWindow]) {
    guard config.enabled && config.protectInAppSwitcher else { return }
    for window in windows { installAppSwitcher(in: window) }
  }

  func uncoverAppSwitcher(in windows: [UIWindow]) {
    for window in windows { remove(.appSwitcher, from: window) }
  }

  func removeCaptureOverlays(forMissingWindows connectedWindowIDs: Set<ObjectIdentifier>) {
    for window in capture.keyEnumerator().allObjects.compactMap({ $0 as? UIWindow }) {
      if !connectedWindowIDs.contains(ObjectIdentifier(window)) {
        remove(.capture, from: window)
      }
    }
  }

  func removeAll() {
    removeAll(from: capture)
    removeAll(from: appSwitcher)
  }

  private func isSceneActive(for window: UIWindow) -> Bool {
    if let sceneActivationProvider { return sceneActivationProvider(window) }
    if let scene = window.windowScene {
      return scene.activationState == .foregroundActive
    }
    return UIApplication.shared.applicationState == .active
  }

  private func installAppSwitcher(in window: UIWindow) {
    let color = SecureContentNativePolicy.opaqueRGB(from: config.appSwitcherColor)
    install(
      .appSwitcher,
      in: window,
      color: UIColor(red: color.red, green: color.green, blue: color.blue, alpha: 1),
      imageName: config.appSwitcherImageName
    )
  }

  private func install(
    _ kind: Kind, in window: UIWindow, color: UIColor, imageName: String? = nil
  ) {
    let table = table(for: kind)
    let overlay: PrivacyOverlayView
    if let existing = table.object(forKey: window) {
      overlay = existing
    } else {
      overlay = PrivacyOverlayView(frame: window.bounds)
      table.setObject(overlay, forKey: window)
    }
    if overlay.superview !== window { window.addSubview(overlay) }
    overlay.configure(color: color, imageName: imageName)
    overlay.frame = window.bounds
    window.bringSubviewToFront(overlay)
  }

  private func remove(_ kind: Kind, from window: UIWindow) {
    let table = table(for: kind)
    table.object(forKey: window)?.removeFromSuperview()
    table.removeObject(forKey: window)
  }

  private func table(for kind: Kind) -> NSMapTable<UIWindow, PrivacyOverlayView> {
    switch kind {
    case .capture: capture
    case .appSwitcher: appSwitcher
    }
  }

  private func removeAll(from table: NSMapTable<UIWindow, PrivacyOverlayView>) {
    for overlay in table.objectEnumerator()?.allObjects ?? [] {
      (overlay as? PrivacyOverlayView)?.removeFromSuperview()
    }
    table.removeAllObjects()
  }
}

@MainActor
private final class PrivacyOverlayView: UIView {
  private var imageName: String?
  private var imageWidthConstraint: NSLayoutConstraint?

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    isOpaque = true
    autoresizingMask = [.flexibleWidth, .flexibleHeight]
    accessibilityIdentifier = "secure_content.image:none"
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
  }

  func configure(color: UIColor, imageName: String?) {
    backgroundColor = color
    isHidden = false
    guard self.imageName != imageName else { return }
    self.imageName = imageName
    accessibilityIdentifier = imageName.map { "secure_content.image:\($0)" }
      ?? "secure_content.image:none"
    subviews.forEach { $0.removeFromSuperview() }
    imageWidthConstraint = nil

    guard let imageName, let image = UIImage(named: imageName) else { return }
    let imageView = UIImageView(image: image.withRenderingMode(.alwaysTemplate))
    imageView.tintColor = .white
    imageView.contentMode = .scaleAspectFit
    imageView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(imageView)
    let width = imageView.widthAnchor.constraint(equalToConstant: logoWidth)
    imageWidthConstraint = width
    let aspect = image.size.width > 0 ? image.size.height / image.size.width : 1
    NSLayoutConstraint.activate([
      imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
      imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
      width,
      imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor, multiplier: aspect),
    ])
  }

  override func layoutSubviews() {
    imageWidthConstraint?.constant = logoWidth
    super.layoutSubviews()
  }

  private var logoWidth: CGFloat {
    max(96, min(160, min(bounds.width, bounds.height) * 0.28))
  }
}
