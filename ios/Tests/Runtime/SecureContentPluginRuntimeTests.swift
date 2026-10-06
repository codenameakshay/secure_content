import LocalAuthentication
import UIKit
import XCTest

@testable import secure_content

@MainActor
final class SecureContentPluginRuntimeTests: XCTestCase {
  func testSensitiveClipboardUsesSystemExpiration() async throws {
    var plugin: SecureContentPlugin? = SecureContentPlugin()
    try plugin?.setSensitiveClipboard(content: "expires from pasteboard", clearAfterMs: 700)
    plugin = nil

    try await Task.sleep(nanoseconds: 1_500_000_000)

    XCTAssertTrue(UIPasteboard.general.items.isEmpty)
  }

  func testExpiredTimerPreservesANewerIdenticalClipboardCopy() async throws {
    let plugin = SecureContentPlugin()
    try plugin.setSensitiveClipboard(content: "same text", clearAfterMs: 700)
    let originalChangeCount = UIPasteboard.general.changeCount
    UIPasteboard.general.setItems([["public.utf8-plain-text": "same text"]], options: [:])
    XCTAssertNotEqual(UIPasteboard.general.changeCount, originalChangeCount)

    try await Task.sleep(nanoseconds: 1_200_000_000)

    XCTAssertEqual(UIPasteboard.general.string, "same text")
  }

  func testExplicitClipboardClearRemovesOwnedContent() throws {
    let plugin = SecureContentPlugin()
    try plugin.setSensitiveClipboard(content: "explicit clear", clearAfterMs: 0)

    try plugin.clearSensitiveClipboard()

    XCTAssertTrue(UIPasteboard.general.items.isEmpty)
  }

  func testVeryLongClipboardTTLDoesNotOverflowDispatchDeadline() throws {
    let plugin = SecureContentPlugin()

    try plugin.setSensitiveClipboard(content: "long ttl", clearAfterMs: Int64.max)

    XCTAssertEqual(UIPasteboard.general.string, "long ttl")
    try plugin.clearSensitiveClipboard()
  }

  func testExplicitClearPreservesANewerIdenticalClipboardCopy() throws {
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
    let plugin = SecureContentPlugin()
    let context = LAContext()
    plugin.activeAuthenticationContext = context

    plugin.cancelActiveAuthentication()

    XCTAssertNil(plugin.activeAuthenticationContext)
    var error: NSError?
    XCTAssertFalse(context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error))
    XCTAssertEqual((error as? LAError)?.code, .invalidContext)
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
