import Foundation
import Testing

@testable import SecureContentNativePolicies

struct SecureContentNativePolicyTests {
  @Test
  func replacedClipboardWithIdenticalContentIsNotOwnedOrRead() {
    var ownership = SensitiveClipboardOwnership()
    ownership.record(content: "one-time code", changeCount: 10)
    var clipboardReads = 0

    #expect(ownership.ownsClipboard(currentChangeCount: 10) {
      clipboardReads += 1
      return "one-time code"
    })
    #expect(!ownership.ownsClipboard(currentChangeCount: 11) {
      clipboardReads += 1
      return "one-time code"
    })
    #expect(clipboardReads == 1)
    #expect(!ownership.ownsClipboard(currentChangeCount: 10) { "different" })

    ownership.clear()
    #expect(!ownership.ownsClipboard(currentChangeCount: 10) { "one-time code" })
  }

  @Test(arguments: [
    (Double(Int64.max), 3_600_000),
    (3_600.001, 3_600_000),
    (0.0011, 2),
    (0.0001, 1),
    (0, 1),
    (-1, 1),
  ])
  func clipboardDispatchDelayIsBoundedAndRoundsUp(seconds: Double, expected: Int) {
    let now = Date(timeIntervalSince1970: 0)
    #expect(
      SecureContentNativePolicy.dispatchDelayMilliseconds(
        until: now.addingTimeInterval(seconds), now: now
      ) == expected
    )
  }

  @Test(arguments: [
    (false, false, false), (false, false, true),
    (false, true, false), (false, true, true),
    (true, false, false), (true, false, true),
    (true, true, false), (true, true, true),
  ])
  func appSwitcherCoverRequiresEnabledProtectedInactiveScene(
    enabled: Bool, protected: Bool, active: Bool
  ) {
    #expect(
      SecureContentNativePolicy.shouldCoverAppSwitcher(
        enabled: enabled, protectInAppSwitcher: protected, sceneIsActive: active
      ) == (enabled && protected && !active)
    )
  }

  @Test(arguments: [
    (false, true, SecureContentEventType.recordingStarted),
    (true, false, SecureContentEventType.recordingStopped),
  ])
  func recordingEventsRepresentAggregateCaptureTransitions(
    before: Bool, after: Bool, expected: SecureContentEventType
  ) {
    #expect(
      SecureContentNativePolicy.recordingEvent(previouslyCaptured: before, isCaptured: after)
        == expected
    )
    #expect(
      SecureContentNativePolicy.recordingEvent(previouslyCaptured: before, isCaptured: before)
        == nil
    )
  }

  @Test(arguments: [
    (false, true, SecureContentEventType.appSwitcherProtected),
    (true, false, SecureContentEventType.appSwitcherUnprotected),
  ])
  func appSwitcherEventsOnlyReportChangedAggregateCoverage(
    before: Bool, after: Bool, expected: SecureContentEventType
  ) {
    #expect(
      SecureContentNativePolicy.appSwitcherEvent(previouslyProtected: before, isProtected: after)
        == expected
    )
    #expect(
      SecureContentNativePolicy.appSwitcherEvent(previouslyProtected: before, isProtected: before)
        == nil
    )
  }

  @Test(arguments: [Int64(0x00123456), Int64(0xFF123456), Int64(0x1FF123456)])
  func privacyColorIgnoresCallerAlphaAndTruncatesToARGB(argb: Int64) {
    let color = SecureContentNativePolicy.opaqueRGB(from: argb)
    #expect(abs(color.red - CGFloat(0x12) / 255) < 0.0001)
    #expect(abs(color.green - CGFloat(0x34) / 255) < 0.0001)
    #expect(abs(color.blue - CGFloat(0x56) / 255) < 0.0001)
  }
}
