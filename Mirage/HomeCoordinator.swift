import SwiftUI
import Combine

@MainActor
final class HomeCoordinator: CoordinatorProtocol, ObservableObject {
    let navigation: NavigationController
    var childCoordinators: [CoordinatorProtocol] = []

    init(navigation: NavigationController) {
        self.navigation = navigation
        navigation.pushView(HomeView())
    }
}

struct HomeView: View {
    var body: some View {
        VStack {
            Text("Home")
                .font(.largeTitle)
        }
    }
}

@MainActor
final class SettingsCoordinator: CoordinatorProtocol, ObservableObject {
    let navigation: NavigationController
    var childCoordinators: [CoordinatorProtocol] = []

    init(navigation: NavigationController) {
        self.navigation = navigation
        navigation.pushView(SettingsView())
    }
}

struct SettingsView: View {
    var body: some View {
        VStack {
            Text("Settings")
                .font(.largeTitle)
        }
    }
}

@MainActor
final class LoginCoordinator: CoordinatorProtocol, ObservableObject {
    let navigation: NavigationController
    var childCoordinators: [CoordinatorProtocol] = []

    init(navigation: NavigationController) {
        self.navigation = navigation
        return
    }

    private func goToMFA() {
        return
    }

    private func finish() {
        navigation.dismissModal()
    }
}
