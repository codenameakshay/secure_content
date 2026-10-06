import XCTest

@testable import SecureContentNativePolicies

final class SecureContentNativePolicyTests: XCTestCase {
  func testClipboardOwnershipDoesNotClearAReplacementWithSameText() {
    var ownership = SensitiveClipboardOwnership()
    ownership.record(content: "one-time code", changeCount: 10)
    var clipboardReads = 0

    XCTAssertTrue(
      ownership.ownsClipboard(currentChangeCount: 10) {
        clipboardReads += 1
        return "one-time code"
      }
    )
    XCTAssertFalse(
      ownership.ownsClipboard(currentChangeCount: 11) {
        clipboardReads += 1
        return "one-time code"
      }
    )
    XCTAssertEqual(clipboardReads, 1, "A replaced clipboard should not be read.")
    XCTAssertFalse(
      ownership.ownsClipboard(currentChangeCount: 10) {
        clipboardReads += 1
        return "different"
      }
    )

    ownership.clear()
    XCTAssertFalse(ownership.ownsClipboard(currentChangeCount: 10) { "one-time code" })
  }

  func testClipboardDispatchDelayIsBoundedForVeryLongExpiration() {
    let now = Date(timeIntervalSince1970: 0)
    let distantExpiration = Date(timeIntervalSince1970: Double(Int64.max))

    XCTAssertEqual(
      SecureContentNativePolicy.dispatchDelayMilliseconds(until: distantExpiration, now: now),
      3_600_000
    )
    XCTAssertEqual(
      SecureContentNativePolicy.dispatchDelayMilliseconds(until: now, now: now),
      1
    )
  }

  func testAppSwitcherCoverRequiresEnabledProtectedInactiveScene() {
    XCTAssertTrue(
      SecureContentNativePolicy.shouldCoverAppSwitcher(
        enabled: true,
        protectInAppSwitcher: true,
        sceneIsActive: false
      )
    )
    XCTAssertFalse(
      SecureContentNativePolicy.shouldCoverAppSwitcher(
        enabled: false,
        protectInAppSwitcher: true,
        sceneIsActive: false
      )
    )
    XCTAssertFalse(
      SecureContentNativePolicy.shouldCoverAppSwitcher(
        enabled: true,
        protectInAppSwitcher: false,
        sceneIsActive: false
      )
    )
    XCTAssertFalse(
      SecureContentNativePolicy.shouldCoverAppSwitcher(
        enabled: true,
        protectInAppSwitcher: true,
        sceneIsActive: true
      )
    )
  }

  func testRecordingEventsRepresentAggregateCaptureTransitionsOnly() {
    XCTAssertEqual(
      SecureContentNativePolicy.recordingEvent(previouslyCaptured: false, isCaptured: true),
      "recordingStarted"
    )
    XCTAssertNil(
      SecureContentNativePolicy.recordingEvent(previouslyCaptured: true, isCaptured: true)
    )
    XCTAssertEqual(
      SecureContentNativePolicy.recordingEvent(previouslyCaptured: true, isCaptured: false),
      "recordingStopped"
    )
  }
}
