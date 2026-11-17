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

  func testBiometricOnlyUsesBiometricPolicyAndHidesFallback() {
    let context = ControlledAuthenticationContext()
    let authentication = SecureContentAuthentication(contextProvider: { context })
    var results: [AuthResult] = []
    authentication.authenticate(reason: "Unlock", biometricOnly: true) { results.append($0) }

    XCTAssertEqual(context.evaluatedPolicy, .deviceOwnerAuthenticationWithBiometrics)
    XCTAssertEqual(context.localizedFallbackTitle, "")
    context.complete(success: true)
    drainMainQueue()
    XCTAssertEqual(results, [AuthResult(status: .success)])
  }

  func testDefaultPolicyStillAllowsThePasscode() {
    let context = ControlledAuthenticationContext()
    let authentication = SecureContentAuthentication(contextProvider: { context })
    authentication.authenticate(reason: "Unlock", biometricOnly: false) { _ in }
    XCTAssertEqual(context.evaluatedPolicy, .deviceOwnerAuthentication)
    XCTAssertNil(context.localizedFallbackTitle)

    let legacy = ControlledAuthenticationContext()
    SecureContentAuthentication(contextProvider: { legacy }).request(reason: "Unlock") { _ in }
    XCTAssertEqual(legacy.evaluatedPolicy, .deviceOwnerAuthentication)
  }

  func testEvaluationErrorsMapToStatuses() {
    let expected: [(LAError.Code, AuthStatus)] = [
      (.userCancel, .canceled), (.systemCancel, .canceled), (.appCancel, .canceled),
      (.userFallback, .canceled), (.authenticationFailed, .failed),
      (.biometryLockout, .permanentLockout), (.biometryNotEnrolled, .notEnrolled),
      (.biometryNotAvailable, .notAvailable), (.passcodeNotSet, .notAvailable),
      (.invalidContext, .error), (.notInteractive, .error),
    ]
    for (code, status) in expected {
      let context = ControlledAuthenticationContext()
      let authentication = SecureContentAuthentication(contextProvider: { context })
      var results: [AuthResult] = []
      authentication.authenticate(reason: "r", biometricOnly: true) { results.append($0) }
      context.complete(success: false, error: LAError(code))
      drainMainQueue()
      XCTAssertEqual(results.map(\.status), [status], "\(code)")
      XCTAssertNotNil(results.first?.message, "\(code)")
    }
  }

  func testUnavailablePolicyRepliesWithoutPrompting() {
    let context = ControlledAuthenticationContext()
    context.canEvaluateError = LAError(.biometryNotEnrolled)
    let authentication = SecureContentAuthentication(contextProvider: { context })
    var results: [AuthResult] = []
    authentication.authenticate(reason: "r", biometricOnly: true) { results.append($0) }
    XCTAssertEqual(results.map(\.status), [.notEnrolled])
    XCTAssertNil(context.evaluatedPolicy)
    XCTAssertNil(authentication.context)
  }

  func testCancelledOrReplacedAuthenticateRepliesOnceAsCanceled() {
    let first = ControlledAuthenticationContext()
    let second = ControlledAuthenticationContext()
    var nextContext: LAContext = first
    let authentication = SecureContentAuthentication(contextProvider: { nextContext })
    var firstResults: [AuthResult] = []
    var secondResults: [AuthResult] = []
    authentication.authenticate(reason: "1", biometricOnly: true) { firstResults.append($0) }
    nextContext = second
    authentication.authenticate(reason: "2", biometricOnly: true) { secondResults.append($0) }
    XCTAssertEqual(firstResults, [AuthResult(status: .canceled)])

    first.complete(success: true)
    authentication.cancel()
    second.complete(success: true)
    drainMainQueue()
    XCTAssertEqual(firstResults, [AuthResult(status: .canceled)])
    XCTAssertEqual(secondResults, [AuthResult(status: .canceled)])
  }

  func testOnlyASystemCancelWhileInactiveIsAnInterruption() {
    let cases: [(LAError.Code, Bool, Bool?)] = [
      (.systemCancel, false, true), (.systemCancel, true, nil), (.userCancel, false, nil),
    ]
    for (code, active, expected) in cases {
      let context = ControlledAuthenticationContext()
      let authentication = SecureContentAuthentication(
        contextProvider: { context }, appIsActive: { active })
      var results: [AuthResult] = []
      authentication.authenticate(reason: "r", biometricOnly: true) { results.append($0) }
      context.complete(success: false, error: LAError(code))
      drainMainQueue()
      XCTAssertEqual(results.map(\.status), [.canceled], "\(code) active=\(active)")
      XCTAssertEqual(results.map(\.interrupted), [expected], "\(code) active=\(active)")
    }
  }

    func testCapabilityReportsEnrolledBiometricsAndLockout() {
    let context = ControlledAuthenticationContext()
    let authentication = SecureContentAuthentication(contextProvider: { context })
    XCTAssertTrue(authentication.biometricCapability().isAvailable)

    context.canEvaluateError = LAError(.biometryLockout)
    XCTAssertTrue(authentication.biometricCapability().isAvailable)

    context.canEvaluateError = LAError(.biometryNotEnrolled)
    XCTAssertFalse(authentication.biometricCapability().isAvailable)
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
  private var storedPolicy: LAPolicy?
  private var storedCanEvaluateError: LAError?

  var reason: String? { lock.withLock { storedReason } }
  var invalidationCount: Int { lock.withLock { storedInvalidationCount } }
  var evaluatedPolicy: LAPolicy? { lock.withLock { storedPolicy } }
  var canEvaluateError: LAError? {
    get { lock.withLock { storedCanEvaluateError } }
    set { lock.withLock { storedCanEvaluateError = newValue } }
  }

  override func canEvaluatePolicy(_ policy: LAPolicy, error: NSErrorPointer) -> Bool {
    if invalidationCount > 0 { return super.canEvaluatePolicy(policy, error: error) }
    if let canEvaluateError {
      error?.pointee = canEvaluateError as NSError
      return false
    }
    return true
  }

  override func evaluatePolicy(
    _ policy: LAPolicy,
    localizedReason: String,
    reply: @escaping (Bool, Error?) -> Void
  ) {
    lock.withLock {
      storedReason = localizedReason
      storedPolicy = policy
      self.reply = reply
    }
  }

  override func invalidate() {
    lock.withLock { storedInvalidationCount += 1 }
    super.invalidate()
  }

  @MainActor
  func complete(success: Bool, error: Error? = nil) {
    let callback = lock.withLock { reply }
    callback?(success, error)
  }
}
