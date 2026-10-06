import Foundation

enum SecureContentNativePolicy {
  static func shouldCoverAppSwitcher(
    enabled: Bool,
    protectInAppSwitcher: Bool,
    sceneIsActive: Bool
  ) -> Bool {
    enabled && protectInAppSwitcher && !sceneIsActive
  }

  static func recordingEvent(previouslyCaptured: Bool, isCaptured: Bool) -> String? {
    guard previouslyCaptured != isCaptured else { return nil }
    return isCaptured ? "recordingStarted" : "recordingStopped"
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
  private(set) var content: String?
  private(set) var changeCount: Int?

  mutating func record(content: String, changeCount: Int) {
    self.content = content
    self.changeCount = changeCount
  }

  func ownsClipboard(currentChangeCount: Int, currentContent: () -> String?) -> Bool {
    guard let expectedContent = content,
      let expectedChangeCount = changeCount,
      currentChangeCount == expectedChangeCount
    else {
      return false
    }
    return currentContent() == expectedContent
  }

  mutating func clear() {
    content = nil
    changeCount = nil
  }
}
