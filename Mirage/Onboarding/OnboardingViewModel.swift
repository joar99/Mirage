import SwiftUI
import Combine

@MainActor
protocol OnboardingViewModelCoordinating: AnyObject {
    func onboardingViewModelDidFinish(_ onboardingViewModel: OnboardingViewModel)
}

@MainActor
final class OnboardingViewModel: ObservableObject {

    struct OnboardingPageModel: Identifiable {
        let id = UUID()
        let title: String
        let imageName: String?
        init(title: String, imageName: String? = nil) {
            self.title = title
            self.imageName = imageName
        }
    }

    weak var delegate: OnboardingViewModelCoordinating?

    @Published var currentPage: Int? = 0

    let pages = [
        OnboardingPageModel(title: "Snap a shot", imageName: "onboardingone"),
        OnboardingPageModel(title: "Get feedback", imageName: "onboardingtwo"),
        OnboardingPageModel(title: "Achieve more with Mirage")
    ]

    func didTapMainAction() {
        if let current = currentPage, current < pages.count - 1 {
            currentPage = current + 1
        } else {
            delegate?.onboardingViewModelDidFinish(self)
        }
    }
}
