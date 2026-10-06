import UIKit

@MainActor
final class SecureContentCapture {
  var onChange: (@MainActor () -> Void)?
  private let registrations = NSMapTable<UIWindowScene, Registration>.weakToStrongObjects()

  var isCaptured: Bool {
    if #available(iOS 17.0, *) {
      let connectedScenes = scenes
      if !connectedScenes.isEmpty {
        return connectedScenes.contains { scene in
          switch scene.traitCollection.sceneCaptureState {
          case .active: return true
          case .inactive: return false
          case .unspecified: return scene.screen.isCaptured
          @unknown default: return scene.screen.isCaptured
          }
        }
      }
    }
    return UIScreen.screens.contains(where: \.isCaptured)
  }

  static func isCaptured(in window: UIWindow) -> Bool {
    if #available(iOS 17.0, *) {
      switch window.traitCollection.sceneCaptureState {
      case .active: return true
      case .inactive: return false
      case .unspecified: break
      @unknown default: break
      }
    }
    return window.screen.isCaptured
  }

  func observeScenes() {
    guard #available(iOS 17.0, *) else { return }
    let currentScenes = scenes
    let currentIDs = Set(currentScenes.map { ObjectIdentifier($0) })
    for scene in registrations.keyEnumerator().allObjects.compactMap({ $0 as? UIWindowScene }) {
      if !currentIDs.contains(ObjectIdentifier(scene)) {
        registrations.object(forKey: scene)?.cancel()
        registrations.removeObject(forKey: scene)
      }
    }
    for scene in currentScenes where registrations.object(forKey: scene) == nil {
      let token = scene.registerForTraitChanges([UITraitSceneCaptureState.self]) {
        [weak self] (_: UIWindowScene, _: UITraitCollection) in
        self?.onChange?()
      }
      registrations.setObject(
        Registration { [weak scene] in scene?.unregisterForTraitChanges(token) },
        forKey: scene
      )
    }
  }

  func dispose() {
    for registration in registrations.objectEnumerator()?.allObjects ?? [] {
      (registration as? Registration)?.cancel()
    }
    registrations.removeAllObjects()
    onChange = nil
  }

  private var scenes: [UIWindowScene] {
    UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
  }

  private final class Registration {
    let cancel: @MainActor () -> Void

    init(cancel: @escaping @MainActor () -> Void) {
      self.cancel = cancel
    }
  }
}
