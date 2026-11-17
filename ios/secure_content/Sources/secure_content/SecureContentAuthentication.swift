import LocalAuthentication
import UIKit

@MainActor
final class SecureContentAuthentication {
  private(set) var context: LAContext?
  private var generation: UInt64 = 0
  private var completion: ((_ success: Bool, _ code: LAError.Code?, _ message: String?) -> Void)?
  private var onCancel: (() -> Void)?
  private let contextProvider: @MainActor () -> LAContext
  private let appIsActive: @MainActor () -> Bool

  init(
    contextProvider: @escaping @MainActor () -> LAContext = LAContext.init,
    appIsActive: @escaping @MainActor () -> Bool = {
      UIApplication.shared.applicationState == .active
    }
  ) {
    self.contextProvider = contextProvider
    self.appIsActive = appIsActive
  }

  /// Accepts a biometric or the device passcode, and reports a coarse event.
  func request(
    reason: String, emit: @escaping @MainActor @Sendable (SecureContentEventType) -> Void
  ) {
    evaluate(reason: reason, biometricOnly: false, onUnavailable: { _, _ in
      emit(.biometricUnavailable)
    }) { success, _, _ in
      emit(success ? .biometricAuthSucceeded : .biometricAuthFailed)
    }
  }

  /// Replies exactly once, including when a later request or teardown
  /// cancels this one.
  func authenticate(
    reason: String, biometricOnly: Bool, reply: @escaping @MainActor (AuthResult) -> Void
  ) {
    evaluate(
      reason: reason, biometricOnly: biometricOnly,
      onUnavailable: { code, message in
        reply(AuthResult(status: Self.status(for: code, unavailable: true), message: message))
      },
      onCancel: { reply(AuthResult(status: .canceled)) }
    ) { [weak self] success, code, message in
      guard !success else { return reply(AuthResult(status: .success)) }
      // The system closes the prompt when the app leaves the foreground.
      let interrupted = code == .systemCancel && self?.appIsActive() == false
      reply(
        AuthResult(
          status: Self.status(for: code, unavailable: false), message: message,
          interrupted: interrupted ? true : nil))
    }
  }

  func biometricCapability() -> BiometricCapability {
    let context = contextProvider()
    var error: NSError?
    let canEvaluate = context.canEvaluatePolicy(
      .deviceOwnerAuthenticationWithBiometrics, error: &error)
    // A lockout still means biometrics are set up; authenticate reports it.
    let available = canEvaluate || Self.code(of: error) == .biometryLockout
    var types: [BiometryType] = []
    switch context.biometryType {
    case .faceID: types = [.face]
    case .touchID: types = [.fingerprint]
    default:
      if #available(iOS 17.0, *), context.biometryType == .opticID { types = [.iris] }
    }
    return BiometricCapability(isAvailable: available, types: types)
  }

  func cancel() {
    generation &+= 1
    context?.invalidate()
    context = nil
    completion = nil
    let onCancel = self.onCancel
    self.onCancel = nil
    onCancel?()
  }

  static func policy(biometricOnly: Bool) -> LAPolicy {
    biometricOnly ? .deviceOwnerAuthenticationWithBiometrics : .deviceOwnerAuthentication
  }

  /// Maps an `LAError` code. [unavailable] is true when the policy could not
  /// be evaluated at all, so a missing code means no usable authentication.
  static func status(for code: LAError.Code?, unavailable: Bool) -> AuthStatus {
    switch code {
    case .userCancel?, .systemCancel?, .appCancel?, .userFallback?: return .canceled
    case .authenticationFailed?: return .failed
    case .biometryLockout?: return .permanentLockout
    case .biometryNotEnrolled?: return .notEnrolled
    case .biometryNotAvailable?, .passcodeNotSet?: return .notAvailable
    case nil: return unavailable ? .notAvailable : .error
    default: return .error
    }
  }

  private nonisolated static func code(of error: Error?) -> LAError.Code? {
    guard let error = error as NSError?, error.domain == LAErrorDomain else { return nil }
    return LAError.Code(rawValue: error.code)
  }

  private func evaluate(
    reason: String,
    biometricOnly: Bool,
    onUnavailable: (_ code: LAError.Code?, _ message: String?) -> Void,
    onCancel: (() -> Void)? = nil,
    completion: @escaping (_ success: Bool, _ code: LAError.Code?, _ message: String?) -> Void
  ) {
    cancel()
    let context = contextProvider()
    if biometricOnly {
      // An empty title hides the "Enter Password" fallback button.
      context.localizedFallbackTitle = ""
    }
    let policy = Self.policy(biometricOnly: biometricOnly)
    var error: NSError?
    guard context.canEvaluatePolicy(policy, error: &error) else {
      onUnavailable(Self.code(of: error), error?.localizedDescription)
      return
    }

    self.context = context
    self.completion = completion
    self.onCancel = onCancel
    let requestGeneration = generation
    context.evaluatePolicy(
      policy,
      localizedReason: reason.isEmpty ? "Authenticate" : reason
    ) { [weak self] success, error in
      let code = Self.code(of: error)
      let message = error?.localizedDescription
      DispatchQueue.main.async { [weak self] in
        guard let self, self.generation == requestGeneration, self.context != nil else { return }
        self.generation &+= 1
        self.context = nil
        let completion = self.completion
        self.completion = nil
        self.onCancel = nil
        completion?(success, code, message)
      }
    }
  }
}
