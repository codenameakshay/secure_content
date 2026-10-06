import Flutter
import UIKit

public final class SecureContentPlugin: NSObject, FlutterPlugin, SecureContentHostApi {
  private let runtime: SecureContentRuntime

  public override init() {
    runtime = MainActor.assumeIsolated { SecureContentRuntime() }
    super.init()
  }

  @MainActor
  init(
    windowProvider: (() -> [UIWindow])?,
    sceneActivationProvider: ((UIWindow) -> Bool)?
  ) {
    runtime = SecureContentRuntime(
      windowProvider: windowProvider,
      sceneActivationProvider: sceneActivationProvider
    )
    super.init()
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    MainActor.assumeIsolated {
      let instance = SecureContentPlugin()
      instance.runtime.connect(binaryMessenger: registrar.messenger())
      SecureContentHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: instance)
      registrar.publish(instance)
    }
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
    MainActor.assumeIsolated {
      SecureContentHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: nil)
      runtime.dispose()
    }
  }

  func configureProtection(config: ProtectionConfig) throws {
    MainActor.assumeIsolated { runtime.configureProtection(config: config) }
  }

  func isScreenCaptured() throws -> Bool {
    MainActor.assumeIsolated { runtime.isScreenCaptured }
  }

  func requestBiometricAuth(reason: String) throws {
    MainActor.assumeIsolated { runtime.requestBiometricAuth(reason: reason) }
  }

  func checkIntegrity() throws {
    MainActor.assumeIsolated { runtime.checkIntegrity() }
  }

  func setSensitiveClipboard(content: String, clearAfterMs: Int64) throws {
    MainActor.assumeIsolated {
      runtime.setSensitiveClipboard(content: content, clearAfterMs: clearAfterMs)
    }
  }

  func clearSensitiveClipboard() throws {
    MainActor.assumeIsolated { runtime.clearSensitiveClipboard() }
  }

}
