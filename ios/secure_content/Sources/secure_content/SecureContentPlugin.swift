import Flutter
import UIKit

@MainActor
public final class SecureContentPlugin: NSObject, @preconcurrency FlutterPlugin,
  @preconcurrency SecureContentHostApi
{
  private let runtime: SecureContentRuntime

  public override init() {
    MainActor.preconditionIsolated()
    runtime = SecureContentRuntime()
    super.init()
  }

  init(
    windowProvider: (() -> [UIWindow])?,
    sceneActivationProvider: ((UIWindow) -> Bool)?
  ) {
    MainActor.preconditionIsolated()
    runtime = SecureContentRuntime(
      windowProvider: windowProvider,
      sceneActivationProvider: sceneActivationProvider
    )
    super.init()
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    MainActor.preconditionIsolated()
    let instance = SecureContentPlugin()
    instance.runtime.connect(binaryMessenger: registrar.messenger())
    SecureContentHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: instance)
    registrar.publish(instance)
  }

  deinit {
    let runtime = runtime
    if Thread.isMainThread {
      MainActor.assumeIsolated { runtime.dispose() }
    } else {
      DispatchQueue.main.async { runtime.dispose() }
    }
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    MainActor.preconditionIsolated()
    SecureContentHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: nil)
    runtime.dispose()
  }

  func configureProtection(config: ProtectionConfig) throws {
    MainActor.preconditionIsolated()
    runtime.configureProtection(config: config)
  }

  func isScreenCaptured() throws -> Bool {
    MainActor.preconditionIsolated()
    return runtime.isScreenCaptured
  }

  func requestBiometricAuth(reason: String) throws {
    MainActor.preconditionIsolated()
    runtime.requestBiometricAuth(reason: reason)
  }

  func checkIntegrity() throws {
    MainActor.preconditionIsolated()
    runtime.checkIntegrity()
  }

  func setSensitiveClipboard(content: String, clearAfterMs: Int64) throws {
    MainActor.preconditionIsolated()
    runtime.setSensitiveClipboard(content: content, clearAfterMs: clearAfterMs)
  }

  func clearSensitiveClipboard() throws {
    MainActor.preconditionIsolated()
    runtime.clearSensitiveClipboard()
  }
}
