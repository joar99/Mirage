import SwiftUI
import Combine

@MainActor
final class CameraCoordinator: CoordinatorProtocol, ObservableObject {
    let navigation: NavigationController
    var childCoordinators: [CoordinatorProtocol] = []

    lazy var cameraViewModel: CameraViewModel = {
        let cameraViewModel = CameraViewModel()
        cameraViewModel.delegate = self
        return cameraViewModel
    }()

    init(navigation: NavigationController) {
        self.navigation = navigation
        navigation.pushView(CameraView(viewModel: cameraViewModel).navigationBarBackButtonHidden(true))
    }
}

// MARK: - CameraViewModelCoordinating

extension CameraCoordinator: CameraViewModelCoordinating {
    
}
