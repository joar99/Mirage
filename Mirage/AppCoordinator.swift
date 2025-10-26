import SwiftUI
import Combine

struct RootView: View {
    @ObservedObject var appCoordinator: AppCoordinator

    var body: some View {
        ZStack {
            TabView {
                NavigationControllerPresenter(controller: appCoordinator.cameraNav)
                    .tabItem { Label("Camera", systemImage: "camera") }

                NavigationControllerPresenter(controller: appCoordinator.homeNav)
                    .tabItem { Label("Gallery", systemImage: "photo") }

                NavigationControllerPresenter(controller: appCoordinator.settingsNav)
                    .tabItem { Label("Settings", systemImage: "gear") }
            }
        }
        .fullScreenCover(isPresented: $appCoordinator.coreFlowActive) {
            NavigationControllerPresenter(controller: appCoordinator.globalNavigation)
        }
    }
}

@MainActor
final class AppCoordinator: ObservableObject, CoordinatorProtocol {

    // MARK: - Properties

    @Published var coreFlowActive: Bool = false

    var childCoordinators: [CoordinatorProtocol] = []

    let homeNav = NavigationController()
    let cameraNav = NavigationController()
    let settingsNav = NavigationController()

    let globalNavigation = NavigationController()

    private let homeCoordinator: HomeCoordinator
    private let cameraCoordinator: CameraCoordinator
    private let settingsCoordinator: SettingsCoordinator

    // MARK: - Onboarding
    lazy var onboardingViewModel: OnboardingViewModel? = {
        let viewModel = OnboardingViewModel()
        viewModel.delegate = self
        return viewModel
    }()

    init() {
        self.homeCoordinator = HomeCoordinator(navigation: homeNav)
        self.cameraCoordinator = CameraCoordinator(navigation: cameraNav)
        self.settingsCoordinator = SettingsCoordinator(navigation: settingsNav)

        append(child: homeCoordinator)
        append(child: cameraCoordinator)
        append(child: settingsCoordinator)

        // setupOnboarding()
    }

    private func setupOnboarding() {
        coreFlowActive = true
        guard let viewModel = onboardingViewModel else { return }
        let onboardingView = OnboardingView(viewModel: viewModel)
        globalNavigation.pushView(onboardingView.navigationBarBackButtonHidden(true))
    }

}

// MARK: - OnboardingViewModelCoordinating

extension AppCoordinator: OnboardingViewModelCoordinating {
    func onboardingViewModelDidFinish(_ onboardingViewModel: OnboardingViewModel) {
        coreFlowActive = false
        self.onboardingViewModel = nil
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            await MainActor.run {
                globalNavigation.popToRoot()
            }
        }
    }
}
