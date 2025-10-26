import SwiftUI
import Combine

struct NavigationControllerPresenter: View {
    @ObservedObject var controller: NavigationController
    var body: some View {
        NavigationStack(path: $controller.path) {
            EmptyView()
                .navigationDestination(for: NavigableView.self) { nav in
                    nav.view
                        .applyAlert(presentedAlert: $controller.presentedAlert)
                        .applyModal(presentedModal: $controller.presentedModal)
                }
        }
        .onChange(of: controller.path) {
            controller.syncPoppedWrappers()
        }
    }
}

@MainActor
final class NavigationController: ObservableObject {
    @Published var path = NavigationPath()
    @Published var presentedModal: PresentedModal?
    @Published var presentedAlert: PresentedAlert?

    private var wrappers: [NavigableView] = []

    func pushView<V: View>(_ view: V, onRootViewDidPop: (() -> Void)? = nil) {
        let navigableView = NavigableView(view: AnyView(view), onRootViewDidPop: onRootViewDidPop)
        wrappers.append(navigableView)
        path.append(navigableView)
    }

    func setRootView<V: View>(_ view: V) {
        wrappers.removeAll()
        path = NavigationPath()
        pushView(view)
    }

    func pop() {
        guard !wrappers.isEmpty else { return }
        wrappers.removeLast().onRootViewDidPop?()
        path.removeLast()
    }

    func popToRoot() {
        while !wrappers.isEmpty {
            wrappers.removeLast().onRootViewDidPop?()
        }
        path = NavigationPath()
    }

    func presentModal<V: View>(_ view: V, fullScreen: Bool = false) {
        presentedModal = fullScreen ? .fullScreen(AnyView(view)) : .modal(AnyView(view))
    }

    func dismissModal() {
        presentedModal = nil
    }

    func presentAlert(_ alert: PresentedAlert) {
        presentedAlert = alert
    }

    func dismissAlert() {
        presentedAlert = nil
    }

    fileprivate func syncPoppedWrappers() {
        while wrappers.count > path.count {
            wrappers.removeLast().onRootViewDidPop?()
        }
    }
}
