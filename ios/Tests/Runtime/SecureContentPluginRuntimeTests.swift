import LocalAuthentication
import UIKit
import XCTest

@testable import secure_content

@MainActor
final class SecureContentPluginRuntimeTests: XCTestCase {
  func testSensitiveClipboardUsesSystemExpiration() throws {
    try requireForegroundApplication()
    var plugin: SecureContentPlugin? = SecureContentPlugin()
    try plugin?.setSensitiveClipboard(content: "expires from pasteboard", clearAfterMs: 700)
    XCTAssertEqual(UIPasteboard.general.string, "expires from pasteboard")
    plugin = nil

    let expirationWait = expectation(description: "pasteboard expiration")
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
      expirationWait.fulfill()
    }
    wait(for: [expirationWait], timeout: 3.5)

    XCTAssertTrue(UIPasteboard.general.items.isEmpty)
  }

  func testExpiredTimerPreservesANewerIdenticalClipboardCopy() throws {
    try requireForegroundApplication()
    let plugin = SecureContentPlugin()
    try plugin.setSensitiveClipboard(content: "same text", clearAfterMs: 700)
    let originalChangeCount = UIPasteboard.general.changeCount
    UIPasteboard.general.setItems([["public.utf8-plain-text": "same text"]], options: [:])
    XCTAssertNotEqual(UIPasteboard.general.changeCount, originalChangeCount)

    let expirationWait = expectation(description: "owned clipboard timer expires")
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
      expirationWait.fulfill()
    }
    wait(for: [expirationWait], timeout: 3.2)

    XCTAssertEqual(UIPasteboard.general.string, "same text")
  }

  func testExplicitClipboardClearRemovesOwnedContent() throws {
    try requireForegroundApplication()
    let plugin = SecureContentPlugin()
    try plugin.setSensitiveClipboard(content: "explicit clear", clearAfterMs: 0)

    try plugin.clearSensitiveClipboard()

    XCTAssertTrue(UIPasteboard.general.items.isEmpty)
  }

  func testVeryLongClipboardTTLDoesNotOverflowDispatchDeadline() throws {
    try requireForegroundApplication()
    let plugin = SecureContentPlugin()

    try plugin.setSensitiveClipboard(content: "long ttl", clearAfterMs: Int64.max)

    XCTAssertEqual(UIPasteboard.general.string, "long ttl")
    try plugin.clearSensitiveClipboard()
  }

  func testExplicitClearPreservesANewerIdenticalClipboardCopy() throws {
    try requireForegroundApplication()
    let plugin = SecureContentPlugin()
    try plugin.setSensitiveClipboard(content: "same text", clearAfterMs: 0)
    UIPasteboard.general.setItems([[
      "public.utf8-plain-text": "same text"
    ]], options: [:])

    try plugin.clearSensitiveClipboard()

    XCTAssertEqual(UIPasteboard.general.string, "same text")
  }

  func testInactiveWindowReconfigurationUpdatesCoverAndKeepsItOpaque() throws {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
    var sceneIsActive = false
    let plugin = SecureContentPlugin(
      windowProvider: { [window] },
      sceneActivationProvider: { _ in sceneIsActive }
    )

    try plugin.configureProtection(config: config(color: 0xFF000000, image: "FirstLogo"))
    let originalCover = try XCTUnwrap(switcherCovers(in: window).first)

    try plugin.configureProtection(config: config(color: 0x00123456, image: "SecondLogo"))

    let updatedCover = try XCTUnwrap(switcherCovers(in: window).first)
    XCTAssertTrue(originalCover === updatedCover)
    XCTAssertEqual(updatedCover.accessibilityIdentifier, "secure_content.image:SecondLogo")
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    updatedCover.backgroundColor?.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    XCTAssertEqual(red, CGFloat(0x12) / 255, accuracy: 0.01)
    XCTAssertEqual(green, CGFloat(0x34) / 255, accuracy: 0.01)
    XCTAssertEqual(blue, CGFloat(0x56) / 255, accuracy: 0.01)
    XCTAssertEqual(alpha, 1)
    let attachment = XCTAttachment(image: renderedImage(of: window))
    attachment.name = "Configured app-switcher privacy cover"
    attachment.lifetime = .keepAlways
    add(attachment)

    sceneIsActive = true
    try plugin.configureProtection(config: config(color: 0xFF000000, image: nil))
    XCTAssertTrue(switcherCovers(in: window).isEmpty)
  }

  func testEngineDisableRemovesOnlyThatEnginesOverlay() throws {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
    let pluginA = SecureContentPlugin(
      windowProvider: { [window] },
      sceneActivationProvider: { _ in false }
    )
    let pluginB = SecureContentPlugin(
      windowProvider: { [window] },
      sceneActivationProvider: { _ in false }
    )
    try pluginA.configureProtection(config: config(color: 0xFF000000, image: "A"))
    let pluginACover = try XCTUnwrap(switcherCovers(in: window).first)
    try pluginB.configureProtection(config: config(color: 0xFF000000, image: "B"))
    XCTAssertEqual(switcherCovers(in: window).count, 2)

    try pluginB.configureProtection(
      config: ProtectionConfig(
        enabled: false,
        protectInAppSwitcher: false,
        appSwitcherColor: 0xFF000000,
        appSwitcherImageName: nil
      )
    )

    XCTAssertTrue(pluginACover.superview === window)
    XCTAssertEqual(switcherCovers(in: window).count, 1)
  }

  func testDetachingAuthenticationContextInvalidatesItWithoutShowingPrompt() {
    let context = ControlledAuthenticationContext()
    let authentication = SecureContentAuthentication(contextProvider: { context })
    authentication.request(reason: "test") { _ in }

    authentication.cancel()

    XCTAssertNil(authentication.context)
    var error: NSError?
    XCTAssertFalse(context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error))
    XCTAssertEqual((error as? LAError)?.code, .invalidContext)
  }

  func testLifecycleCoversAllWindowsAndKeepsInactiveScenesCoveredOnActivation() {
    let first = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
    let second = UIWindow(frame: first.frame)
    let runtime = SecureContentRuntime(
      windowProvider: { [first, second] },
      sceneActivationProvider: { $0 === first }
    )
    runtime.setupObservers()
    runtime.configureProtection(config: config(color: 0xFF000000, image: nil))
    XCTAssertTrue(switcherCovers(in: first).isEmpty)
    XCTAssertEqual(switcherCovers(in: second).count, 1)

    NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
    XCTAssertEqual(switcherCovers(in: first).count, 1)
    XCTAssertEqual(switcherCovers(in: second).count, 1)
    NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
    XCTAssertTrue(switcherCovers(in: first).isEmpty)
    XCTAssertEqual(switcherCovers(in: second).count, 1)

    runtime.dispose()
    XCTAssertTrue(switcherCovers(in: second).isEmpty)
  }

  @available(iOS 17.0, *)
  func testSceneCaptureTraitsProtectOnlyCapturedWindows() {
    let first = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
    let second = UIWindow(frame: first.frame)
    first.traitOverrides.sceneCaptureState = .active
    second.traitOverrides.sceneCaptureState = .inactive
    let overlays = SecureContentOverlays(windowProvider: { [first, second] })
    overlays.configure(
      ProtectionConfig(enabled: true, protectInAppSwitcher: false, appSwitcherColor: 0)
    )
    XCTAssertEqual(switcherCovers(in: first).count, 1)
    XCTAssertTrue(switcherCovers(in: second).isEmpty)

    first.traitOverrides.sceneCaptureState = .inactive
    second.traitOverrides.sceneCaptureState = .active
    overlays.reconcileCapture(in: [first, second])
    XCTAssertTrue(switcherCovers(in: first).isEmpty)
    XCTAssertEqual(switcherCovers(in: second).count, 1)
    overlays.removeAll()
  }

  func testReconciliationReattachesAnExternallyRemovedPrivacyCover() throws {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
    let plugin = SecureContentPlugin(
      windowProvider: { [window] },
      sceneActivationProvider: { _ in false }
    )
    try plugin.configureProtection(config: config(color: 0xFF000000, image: nil))
    let cover = try XCTUnwrap(switcherCovers(in: window).first)
    cover.removeFromSuperview()

    try plugin.configureProtection(config: config(color: 0xFF000000, image: nil))

    XCTAssertTrue(cover.superview === window)
  }

  @available(iOS 17.0, *)
  func testScreenNotificationStillReconcilesCaptureOnModernIOS() {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
    window.traitOverrides.sceneCaptureState = .active
    let runtime = SecureContentRuntime(windowProvider: { [window] })
    runtime.setupObservers()
    defer { runtime.dispose() }
    runtime.configureProtection(
      config: ProtectionConfig(enabled: true, protectInAppSwitcher: false, appSwitcherColor: 0)
    )
    window.subviews.forEach { $0.removeFromSuperview() }

    NotificationCenter.default.post(name: UIScreen.capturedDidChangeNotification, object: window.screen)

    XCTAssertEqual(switcherCovers(in: window).count, 1)
  }

  private func requireForegroundApplication() throws {
    let foreground = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
        MainActor.assumeIsolated { Self.foregroundScene != nil }
      },
      object: nil
    )
    wait(for: [foreground], timeout: 5)
    XCTAssertEqual(Bundle.main.bundleIdentifier, "dev.securecontent.runtime-host")
    _ = try XCTUnwrap(
      Self.foregroundScene,
      "Clipboard runtime tests require a foreground application with a visible key window."
    )
  }

  private static var foregroundScene: UIWindowScene? {
    UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first {
      $0.activationState == .foregroundActive
        && $0.windows.contains { $0.isKeyWindow && !$0.isHidden }
    }
  }

  private func config(color: Int64, image: String?) -> ProtectionConfig {
    ProtectionConfig(
      enabled: true,
      protectInAppSwitcher: true,
      appSwitcherColor: color,
      appSwitcherImageName: image
    )
  }

  private func switcherCovers(in window: UIWindow) -> [UIView] {
    window.subviews.filter {
      $0.accessibilityIdentifier?.hasPrefix("secure_content.image:") == true
    }
  }

  private func renderedImage(of view: UIView) -> UIImage {
    UIGraphicsImageRenderer(bounds: view.bounds).image { context in
      view.layer.render(in: context.cgContext)
    }
  }
}
