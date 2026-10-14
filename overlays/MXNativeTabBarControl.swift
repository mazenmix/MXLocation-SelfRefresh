import SwiftUI
import UIKit

// Fullscreen WITHOUT re-creating MapKit/MapLibre or changing their camera.
// iOS 26 uses a floating UIKit tab bar. Fading that native bar out preserves
// the safe-area layout and keeps the SAME map UIView and exact zoom in place.
struct MXNativeTabBarControl: UIViewRepresentable {
    let hideTabBar: Bool

    func makeUIView(context: Context) -> TrackingView {
        let view = TrackingView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.applyHidden = hideTabBar
        return view
    }

    func updateUIView(_ view: TrackingView, context: Context) {
        view.applyHidden = hideTabBar
        view.updateBar()
    }

    final class TrackingView: UIView {
        var applyHidden = false
        private weak var lastBar: UITabBar?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            updateBar()
        }

        private func findTabBar() -> UITabBar? {
            var current: UIResponder? = self
            while let responder = current {
                if let tabs = responder as? UITabBarController { return tabs.tabBar }
                if let controller = responder as? UIViewController,
                   let tabs = controller.tabBarController { return tabs.tabBar }
                current = responder.next
            }
            guard let root = window?.rootViewController else { return nil }
            func descend(_ viewController: UIViewController) -> UITabBar? {
                if let tabs = viewController as? UITabBarController { return tabs.tabBar }
                for child in viewController.children {
                    if let bar = descend(child) { return bar }
                }
                return nil
            }
            return descend(root)
        }

        func updateBar() {
            // SwiftUI may call update before the native view joins the hierarchy.
            // Re-run once after attachment. No animation of size or map geometry.
            if let bar = findTabBar() {
                lastBar = bar
                bar.alpha = applyHidden ? 0 : 1
                bar.isUserInteractionEnabled = !applyHidden
                bar.accessibilityElementsHidden = applyHidden
            } else if window == nil {
                return
            } else {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.window != nil else { return }
                    if let bar = self.findTabBar() {
                        self.lastBar = bar
                        bar.alpha = self.applyHidden ? 0 : 1
                        bar.isUserInteractionEnabled = !self.applyHidden
                        bar.accessibilityElementsHidden = self.applyHidden
                    }
                }
            }
        }

        deinit {
            // Never leave the floating tabs invisible after leaving the screen.
            lastBar?.alpha = 1
            lastBar?.isUserInteractionEnabled = true
            lastBar?.accessibilityElementsHidden = false
        }
    }
}
