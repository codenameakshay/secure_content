import LocalAuthentication
import Testing

@testable import secure_content

@MainActor
struct SecureContentAuthenticationTests {
  @Test
  func duplicateTerminalCallbacksEmitOnce() async {
    let context = ControlledAuthenticationContext()
    let authentication = SecureContentAuthentication(contextProvider: { context })
    var events: [SecureContentEventType] = []
    authentication.request(reason: "") { events.append($0) }
    #expect(context.reason == "Authenticate")

    context.complete(success: true)
    context.complete(success: false)
    await drainMainQueue()

    #expect(events == [.biometricAuthSucceeded])
    #expect(authentication.context == nil)
  }

  @Test
  func cancelledAndReplacedRequestsCannotUnlock() async {
    let first = ControlledAuthenticationContext()
    let second = ControlledAuthenticationContext()
    var nextContext: LAContext = first
    let authentication = SecureContentAuthentication(contextProvider: { nextContext })
    var events: [SecureContentEventType] = []
    authentication.request(reason: "First") { events.append($0) }
    nextContext = second
    authentication.request(reason: "Second") { events.append($0) }
    #expect(first.invalidationCount == 1)

    first.complete(success: true)
    await drainMainQueue()
    #expect(events.isEmpty)
    #expect(authentication.context === second)

    authentication.cancel()
    second.complete(success: true)
    await drainMainQueue()
    #expect(events.isEmpty)
    #expect(authentication.context == nil)
    #expect(second.invalidationCount == 1)
  }

  private func drainMainQueue() async {
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async { continuation.resume() }
    }
  }
}

final class ControlledAuthenticationContext: LAContext {
  @MainActor private var reply: ((Bool, Error?) -> Void)?
  @MainActor private(set) var reason: String?
  @MainActor private(set) var invalidationCount = 0

  override func canEvaluatePolicy(_ policy: LAPolicy, error: NSErrorPointer) -> Bool {
    MainActor.assumeIsolated {
      if invalidationCount > 0 { return super.canEvaluatePolicy(policy, error: error) }
      return true
    }
  }

  override func evaluatePolicy(
    _ policy: LAPolicy,
    localizedReason: String,
    reply: @escaping (Bool, Error?) -> Void
  ) {
    MainActor.assumeIsolated {
      reason = localizedReason
      self.reply = reply
    }
  }

  override func invalidate() {
    MainActor.assumeIsolated { invalidationCount += 1 }
    super.invalidate()
  }

  @MainActor
  func complete(success: Bool) {
    reply?(success, nil)
  }
}
