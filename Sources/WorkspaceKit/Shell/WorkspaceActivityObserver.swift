import SwiftUI

#if os(macOS)
  import AppKit

  struct WorkspaceActivityObserver: NSViewRepresentable {
    let onActivity: () -> Void
    func makeNSView(context: Context) -> ActivityView {
      let view = ActivityView()
      view.onActivity = onActivity
      return view
    }
    func updateNSView(_ view: ActivityView, context: Context) { view.onActivity = onActivity }
    static func dismantleNSView(_ view: ActivityView, coordinator: ()) { view.stopMonitoring() }

    final class ActivityView: NSView {
      var onActivity: (() -> Void)?
      private var monitor: Any?
      override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor {
          NSEvent.removeMonitor(monitor)
          self.monitor = nil
        }
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [
          .keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel, .leftMouseDragged,
        ]) { [weak self] event in
          MainActor.assumeIsolated { self?.onActivity?() }
          return event
        }
      }
      func stopMonitoring() {
        if let monitor {
          NSEvent.removeMonitor(monitor)
          self.monitor = nil
        }
      }
    }
  }
#else
  import UIKit

  struct WorkspaceActivityObserver: UIViewRepresentable {
    let onActivity: () -> Void
    func makeUIView(context: Context) -> ActivityView {
      let view = ActivityView()
      view.onActivity = onActivity
      return view
    }
    func updateUIView(_ view: ActivityView, context: Context) { view.onActivity = onActivity }

    final class ActivityView: UIView {
      var onActivity: (() -> Void)?
      private var observer: ActivityGesture?
      override func didMoveToWindow() {
        super.didMoveToWindow()
        if let observer { observer.view?.removeGestureRecognizer(observer) }
        guard let window else { return }
        let gesture = ActivityGesture()
        gesture.cancelsTouchesInView = false
        gesture.delaysTouchesBegan = false
        gesture.onActivity = { [weak self] in self?.onActivity?() }
        window.addGestureRecognizer(gesture)
        observer = gesture
      }
    }
    final class ActivityGesture: UIGestureRecognizer {
      var onActivity: (() -> Void)?
      override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        onActivity?()
        state = .failed
      }
      override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent) {
        onActivity?()
        state = .failed
      }
      override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
      override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
      }
    }
  }
#endif
