import SwiftUI

struct OnboardingView: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        ZStack {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(viewModel.pages.enumerated()), id: \.offset) { index, page in
                        OnboardingPage(title: page.title, imageName: page.imageName)
                            .containerRelativeFrame(.horizontal)
                            .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollPosition(id: $viewModel.currentPage)
            .scrollTargetBehavior(.paging)
            .ignoresSafeArea()

            VStack {
                Image("applogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 350)
                    .shadow(radius: 5)
                Spacer()
            }
            .ignoresSafeArea(edges: .top)

            VStack {
                Spacer()
                Button(action: {
                    withAnimation(.easeInOut) {
                        viewModel.didTapMainAction()
                    }
                }) {
                    Text(viewModel.currentPage == viewModel.pages.count - 1 ? "Get Started" : "Next")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(12)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 40)
                }
            }
        }
    }
}

struct OnboardingPage: View {
    let title: String
    let imageName: String?

    var body: some View {
        VStack {

            if let imageName {
                Image(imageName)
                    .scaleEffect(0.7)
            }

            Text(title)
                .font(.title2)
                .shadow(radius: 5)
        }
    }
}

#Preview {
    let viewModel = OnboardingViewModel()
    OnboardingView(viewModel: viewModel)
}
