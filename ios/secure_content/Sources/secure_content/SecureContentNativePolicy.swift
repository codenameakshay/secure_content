import Foundation

enum SecureContentEventType: String, Sendable {
  case platformReady
  case screenshotCaptured
  case recordingStarted
  case recordingStopped
  case appSwitcherProtected
  case appSwitcherUnprotected
  case biometricUnavailable
  case biometricAuthSucceeded
  case biometricAuthFailed
  case integrityRiskDetected
  case integritySafe
  case clipboardSet
  case clipboardCleared
}

enum SecureContentNativePolicy {
  static func shouldCoverAppSwitcher(
    enabled: Bool,
    protectInAppSwitcher: Bool,
    sceneIsActive: Bool
  ) -> Bool {
    enabled && protectInAppSwitcher && !sceneIsActive
  }

  static func recordingEvent(previouslyCaptured: Bool, isCaptured: Bool) -> SecureContentEventType? {
    guard previouslyCaptured != isCaptured else { return nil }
    return isCaptured ? .recordingStarted : .recordingStopped
  }

  static func appSwitcherEvent(
    previouslyProtected: Bool, isProtected: Bool
  ) -> SecureContentEventType? {
    guard previouslyProtected != isProtected else { return nil }
    return isProtected ? .appSwitcherProtected : .appSwitcherUnprotected
  }

  static func opaqueRGB(from argb: Int64) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
    let value = UInt32(truncatingIfNeeded: argb)
    return (
      CGFloat((value >> 16) & 0xff) / 255,
      CGFloat((value >> 8) & 0xff) / 255,
      CGFloat(value & 0xff) / 255
    )
  }

  static func dispatchDelayMilliseconds(until expiration: Date, now: Date) -> Int {
    let maximumDelayMilliseconds = 60 * 60 * 1_000
    let remaining = expiration.timeIntervalSince(now)
    guard remaining > 0 else { return 1 }
    let boundedMilliseconds = min(
      Double(maximumDelayMilliseconds),
      max(1, (remaining * 1_000).rounded(.up))
    )
    return Int(boundedMilliseconds)
  }
}

struct SensitiveClipboardOwnership {
  private struct Claim {
    let content: String
    let changeCount: Int
  }

  private var claim: Claim?

  mutating func record(content: String, changeCount: Int) {
    claim = Claim(content: content, changeCount: changeCount)
  }

  func ownsClipboard(currentChangeCount: Int, currentContent: () -> String?) -> Bool {
    guard let claim,
      currentChangeCount == claim.changeCount
    else {
      return false
    }
    return currentContent() == claim.content
  }

  mutating func clear() {
    claim = nil
  }
}
