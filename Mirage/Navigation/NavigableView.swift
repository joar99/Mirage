import SwiftUI

/// A lightweight wrapper for storing type-erased views (`AnyView`)
/// inside a `NavigationPath`. This enables UIKit-style push navigation
/// where views are directly managed by a coordinator.
///
/// Designed for use in any SwiftUI-based coordinator managing a `NavigationStack`.
///
/// Example:
/// ```swift
/// coordinator.push(MyDetailView().eraseToAnyView())
/// ```
struct NavigableView: Hashable, Identifiable {
    let id = UUID()
    let view: AnyView
    let onRootViewDidPop: (() -> Void)?

    init(view: AnyView,
         onRootViewDidPop: (() -> Void)? = nil) {
        self.view = view
        self.onRootViewDidPop = onRootViewDidPop
    }

    static func == (lhs: NavigableView, rhs: NavigableView) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
