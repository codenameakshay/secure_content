import LocalAuthentication
import XCTest

@testable import secure_content

@MainActor
final class SecureContentAuthenticationTests: XCTestCase {
  func testDuplicateTerminalCallbacksEmitOnce() {
    let context = ControlledAuthenticationContext()
    let authentication = SecureContentAuthentication(contextProvider: { context })
    var events: [SecureContentEventType] = []
    authentication.request(reason: "") { events.append($0) }
    XCTAssertEqual(context.reason, "Authenticate")

    context.complete(success: true)
    context.complete(success: false)
    drainMainQueue()

    XCTAssertEqual(events, [.biometricAuthSucceeded])
    XCTAssertNil(authentication.context)
  }

  func testCancelledAndReplacedRequestsCannotUnlock() {
    let first = ControlledAuthenticationContext()
    let second = ControlledAuthenticationContext()
    var nextContext: LAContext = first
    let authentication = SecureContentAuthentication(contextProvider: { nextContext })
    var events: [SecureContentEventType] = []
    authentication.request(reason: "First") { events.append($0) }
    nextContext = second
    authentication.request(reason: "Second") { events.append($0) }
    XCTAssertEqual(first.invalidationCount, 1)

    first.complete(success: true)
    drainMainQueue()
    XCTAssertTrue(events.isEmpty)
    XCTAssertTrue(authentication.context === second)

    authentication.cancel()
    second.complete(success: true)
    drainMainQueue()
    XCTAssertTrue(events.isEmpty)
    XCTAssertNil(authentication.context)
    XCTAssertEqual(second.invalidationCount, 1)
  }

  private func drainMainQueue() {
    let drained = expectation(description: "Authentication callbacks drained")
    DispatchQueue.main.async { drained.fulfill() }
    wait(for: [drained], timeout: 2)
  }
}

final class ControlledAuthenticationContext: LAContext {
  private let lock = NSLock()
  private var reply: ((Bool, Error?) -> Void)?
  private var storedReason: String?
  private var storedInvalidationCount = 0

  var reason: String? { lock.withLock { storedReason } }
  var invalidationCount: Int { lock.withLock { storedInvalidationCount } }

  override func canEvaluatePolicy(_ policy: LAPolicy, error: NSErrorPointer) -> Bool {
    if invalidationCount > 0 { return super.canEvaluatePolicy(policy, error: error) }
    return true
  }

  override func evaluatePolicy(
    _ policy: LAPolicy,
    localizedReason: String,
    reply: @escaping (Bool, Error?) -> Void
  ) {
    lock.withLock {
      storedReason = localizedReason
      self.reply = reply
    }
  }

  override func invalidate() {
    lock.withLock { storedInvalidationCount += 1 }
    super.invalidate()
  }

  @MainActor
  func complete(success: Bool) {
    let callback = lock.withLock { reply }
    callback?(success, nil)
  }
}
