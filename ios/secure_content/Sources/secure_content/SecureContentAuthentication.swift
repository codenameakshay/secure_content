import LocalAuthentication

@MainActor
final class SecureContentAuthentication {
  private(set) var context: LAContext?
  private var generation: UInt64 = 0
  private let contextProvider: @MainActor () -> LAContext

  init(contextProvider: @escaping @MainActor () -> LAContext = LAContext.init) {
    self.contextProvider = contextProvider
  }

  func request(
    reason: String, emit: @escaping @MainActor @Sendable (SecureContentEventType) -> Void
  ) {
    cancel()
    let context = contextProvider()
    var error: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
      emit(.biometricUnavailable)
      return
    }

    self.context = context
    let requestGeneration = generation
    context.evaluatePolicy(
      .deviceOwnerAuthentication,
      localizedReason: reason.isEmpty ? "Authenticate" : reason
    ) { [weak self] success, _ in
      DispatchQueue.main.async {
        guard let self, self.generation == requestGeneration, self.context != nil else { return }
        self.generation &+= 1
        self.context = nil
        emit(success ? .biometricAuthSucceeded : .biometricAuthFailed)
      }
    }
  }

  func cancel() {
    generation &+= 1
    context?.invalidate()
    context = nil
  }
}
