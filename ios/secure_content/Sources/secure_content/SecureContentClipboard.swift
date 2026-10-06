import UIKit

@MainActor
final class SecureContentClipboard {
  private var clearWorkItem: DispatchWorkItem?
  private var ownership = SensitiveClipboardOwnership()
  private var expirationDate: Date?

  func set(
    content: String,
    clearAfterMs: Int64,
    onExpiration: @escaping @MainActor @Sendable () -> Void
  ) {
    cancelTimer()
    var options: [UIPasteboard.OptionsKey: Any] = [.localOnly: true]
    expirationDate = clearAfterMs > 0
      ? Date().addingTimeInterval(TimeInterval(clearAfterMs) / 1_000)
      : nil
    if let expirationDate {
      options[.expirationDate] = expirationDate
    }

    let pasteboard = UIPasteboard.general
    pasteboard.setItems([["public.utf8-plain-text": content]], options: options)
    ownership.record(content: content, changeCount: pasteboard.changeCount)
    if let expirationDate {
      scheduleClear(at: expirationDate, onExpiration: onExpiration)
    }
  }

  func clear() {
    let pasteboard = UIPasteboard.general
    if ownership.ownsClipboard(currentChangeCount: pasteboard.changeCount, currentContent: {
      pasteboard.string
    }) {
      pasteboard.items = []
    }
    ownership.clear()
    expirationDate = nil
    cancelTimer()
  }

  func dispose() {
    cancelTimer()
    expirationDate = nil
    ownership.clear()
  }

  private func cancelTimer() {
    clearWorkItem?.cancel()
    clearWorkItem = nil
  }

  private func scheduleClear(
    at expiration: Date, onExpiration: @escaping @MainActor @Sendable () -> Void
  ) {
    let delay = SecureContentNativePolicy.dispatchDelayMilliseconds(until: expiration, now: Date())
    let workItem = DispatchWorkItem { [weak self] in
      MainActor.assumeIsolated {
        guard let self, self.expirationDate == expiration else { return }
        if Date() < expiration {
          self.scheduleClear(at: expiration, onExpiration: onExpiration)
        } else {
          self.clear()
          onExpiration()
        }
      }
    }
    clearWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delay), execute: workItem)
  }
}
